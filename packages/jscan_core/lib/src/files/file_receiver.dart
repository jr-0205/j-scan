import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../protocol/constants.dart';
import '../protocol/protocol_exception.dart';
import 'file_transfer.dart';

/// Recibe archivos por partes, reanuda desde un `.part` y verifica SHA-256.
///
/// Los archivos incompletos quedan en `<destino>/.jscan-partial/<transferId>.part`
/// para poder continuar tras una desconexión.
final class FileReceiver {
  FileReceiver({
    required Directory destination,
    this.onProgress,
    this.onReceived,
    this.onCanceled,
  }) : _destination = destination;

  Directory _destination;

  /// Progreso agregado (como máximo ~100 avisos por archivo).
  final void Function(FileTransferProgress progress)? onProgress;

  /// Un archivo quedó completo y verificado.
  final void Function(ReceivedFile file)? onReceived;

  /// El celular canceló una transferencia y se borró su parte.
  final void Function(String transferId, String name)? onCanceled;

  final Map<String, _ActiveTransfer> _active = <String, _ActiveTransfer>{};

  Directory get destination => _destination;

  bool get hasActiveTransfers => _active.isNotEmpty;

  /// Cambia la carpeta de destino para las nuevas transferencias.
  ///
  /// Devuelve `false` si hay transferencias en curso.
  bool setDestination(Directory directory) {
    if (_active.isNotEmpty) return false;
    _destination = directory;
    return true;
  }

  /// Acepta una oferta y devuelve desde qué byte debe continuar el celular.
  Future<FileAccept> accept(
    FileOffer offer, {
    required String sessionId,
    String? fromDeviceId,
    String? fromDeviceName,
  }) async {
    final previous = _active.remove(offer.transferId);
    if (previous != null) {
      await previous.close();
    }

    final partial = await _partialFile(offer.transferId);
    var received = await partial.exists() ? await partial.length() : 0;
    if (received > offer.size) {
      await partial.delete();
      received = 0;
    }

    final digestSink = _DigestCollector();
    final hasher = sha256.startChunkedConversion(digestSink);
    if (received > 0) {
      await for (final chunk in partial.openRead()) {
        hasher.add(chunk);
      }
    }

    final handle = await partial.open(mode: FileMode.append);
    final transfer = _ActiveTransfer(
      offer: offer,
      partial: partial,
      handle: handle,
      hasher: hasher,
      digestSink: digestSink,
      received: received,
      sessionId: sessionId,
      fromDeviceId: fromDeviceId,
      fromDeviceName: fromDeviceName,
      startedAt: DateTime.now(),
      lastReported: received,
    );
    _active[offer.transferId] = transfer;

    if (received > 0) {
      onProgress?.call(transfer.progress());
    }

    return FileAccept(
      transferId: offer.transferId,
      offset: received,
      chunkSize: offer.chunkSize,
    );
  }

  /// Escribe un trozo en la posición exacta esperada.
  Future<FileTransferProgress> writeChunk(
    String transferId,
    int offset,
    List<int> data,
  ) async {
    final transfer = _active[transferId];
    if (transfer == null) {
      throw const ProtocolException(
        ProtocolErrorCode.transferNotFound,
        'No hay una transferencia activa con ese transferId',
      );
    }
    if (offset != transfer.received) {
      throw ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'Offset inesperado: se esperaba ${transfer.received} y llegó $offset',
      );
    }
    if (data.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'file_chunk requiere datos',
      );
    }
    if (data.length > JScanDefaults.maxFileChunkBytes) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El trozo supera el máximo permitido',
      );
    }
    if (transfer.received + data.length > transfer.offer.size) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El trozo excede el tamaño anunciado del archivo',
      );
    }

    await transfer.handle.writeFrom(data);
    transfer.hasher.add(data);
    transfer.received += data.length;

    final progress = transfer.progress();
    _maybeReport(transfer, progress);
    return progress;
  }

  /// Verifica tamaño y SHA-256 y mueve el archivo a su nombre definitivo.
  Future<ReceivedFile> complete(
    String transferId, {
    required int size,
    required String sha256Hex,
  }) async {
    final transfer = _active.remove(transferId);
    if (transfer == null) {
      throw const ProtocolException(
        ProtocolErrorCode.transferNotFound,
        'No hay una transferencia activa con ese transferId',
      );
    }

    await transfer.close();
    final digest = transfer.digestSink.value.toString();
    final expected = transfer.offer.sha256.toLowerCase();

    if (size != transfer.offer.size || transfer.received != size) {
      await _deleteQuietly(transfer.partial);
      throw ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'Tamaño incompleto: se recibieron ${transfer.received} de '
        '${transfer.offer.size} bytes',
      );
    }
    if (digest != expected || sha256Hex.toLowerCase() != expected) {
      await _deleteQuietly(transfer.partial);
      throw const ProtocolException(
        ProtocolErrorCode.checksumMismatch,
        'El SHA-256 del archivo no coincide; se descartó la transferencia',
      );
    }

    await _destination.create(recursive: true);
    final target = uniqueFilePath(_destination, transfer.offer.name);
    try {
      await transfer.partial.rename(target);
    } on FileSystemException {
      await transfer.partial.copy(target);
      await _deleteQuietly(transfer.partial);
    }

    final received = ReceivedFile(
      id: transferId,
      name: target.split(Platform.pathSeparator).last,
      path: target,
      size: transfer.received,
      sha256: digest,
      receivedAt: DateTime.now(),
      mimeType: transfer.offer.mimeType,
      fromDeviceId: transfer.fromDeviceId,
      fromDeviceName: transfer.fromDeviceName,
      duration: DateTime.now().difference(transfer.startedAt),
    );
    onProgress?.call(
      transfer.progress(phase: FileTransferPhase.completed),
    );
    onReceived?.call(received);
    return received;
  }

  /// Cancela una transferencia y borra su parte.
  Future<bool> cancel(String transferId) async {
    final transfer = _active.remove(transferId);
    if (transfer == null) return false;
    await transfer.close();
    await _deleteQuietly(transfer.partial);
    onCanceled?.call(transferId, transfer.offer.name);
    return true;
  }

  /// Cierra las transferencias de una sesión, conservando los `.part`.
  Future<void> abortSession(String sessionId) async {
    final pending = _active.entries
        .where((entry) => entry.value.sessionId == sessionId)
        .map((entry) => entry.key)
        .toList();
    for (final transferId in pending) {
      final transfer = _active.remove(transferId);
      await transfer?.close();
    }
  }

  Future<void> dispose() async {
    for (final transfer in _active.values) {
      await transfer.close();
    }
    _active.clear();
  }

  Future<File> _partialFile(String transferId) async {
    final directory = Directory(
      '${_destination.path}${Platform.pathSeparator}.jscan-partial',
    );
    await directory.create(recursive: true);
    return File(
      '${directory.path}${Platform.pathSeparator}$transferId.part',
    );
  }

  void _maybeReport(
    _ActiveTransfer transfer,
    FileTransferProgress progress,
  ) {
    final step = transfer.offer.size ~/ 100;
    final threshold = step < 256 * 1024 ? 256 * 1024 : step;
    final done = transfer.received >= transfer.offer.size;
    if (!done && transfer.received - transfer.lastReported < threshold) {
      return;
    }
    transfer.lastReported = transfer.received;
    onProgress?.call(progress);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Se conserva para una limpieza manual; no invalida la respuesta.
    }
  }
}

final class _ActiveTransfer {
  _ActiveTransfer({
    required this.offer,
    required this.partial,
    required this.handle,
    required this.hasher,
    required this.digestSink,
    required this.received,
    required this.sessionId,
    required this.fromDeviceId,
    required this.fromDeviceName,
    required this.startedAt,
    required this.lastReported,
  });

  final FileOffer offer;
  final File partial;
  final RandomAccessFile handle;
  final ByteConversionSink hasher;
  final _DigestCollector digestSink;
  final String sessionId;
  final String? fromDeviceId;
  final String? fromDeviceName;
  final DateTime startedAt;

  int received;
  int lastReported;

  FileTransferProgress progress({
    FileTransferPhase phase = FileTransferPhase.uploading,
  }) {
    return FileTransferProgress(
      transferId: offer.transferId,
      name: offer.name,
      sentBytes: received,
      totalBytes: offer.size,
      phase: phase,
    );
  }

  Future<void> close() async {
    try {
      await handle.close();
    } catch (_) {
      // Ya estaba cerrado.
    }
    try {
      hasher.close();
    } catch (_) {
      // Cerrar dos veces no debe romper la limpieza.
    }
  }
}

final class _DigestCollector implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest value) {
    _value = value;
  }

  @override
  void close() {}
}

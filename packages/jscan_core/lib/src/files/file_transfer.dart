import 'dart:io';

import 'package:crypto/crypto.dart';

import '../protocol/constants.dart';
import '../protocol/protocol_exception.dart';

/// Fase de una transferencia de archivo.
enum FileTransferPhase { hashing, uploading, completed }

/// Progreso de una transferencia, tanto al enviar como al recibir.
final class FileTransferProgress {
  const FileTransferProgress({
    required this.transferId,
    required this.name,
    required this.sentBytes,
    required this.totalBytes,
    this.phase = FileTransferPhase.uploading,
  });

  final String transferId;
  final String name;
  final int sentBytes;
  final int totalBytes;
  final FileTransferPhase phase;

  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = sentBytes / totalBytes;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  int get percent => (fraction * 100).round();

  FileTransferProgress copyWith({
    int? sentBytes,
    int? totalBytes,
    FileTransferPhase? phase,
  }) {
    return FileTransferProgress(
      transferId: transferId,
      name: name,
      sentBytes: sentBytes ?? this.sentBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      phase: phase ?? this.phase,
    );
  }
}

/// Metadatos de `file_offer` (celular → PC).
final class FileOffer {
  const FileOffer({
    required this.transferId,
    required this.name,
    required this.size,
    required this.sha256,
    required this.chunkSize,
    this.mimeType,
  });

  factory FileOffer.parse(Map<String, Object?> payload) {
    final transferId = payload['transferId'];
    final name = payload['name'];
    final size = payload['size'];
    final sha256 = payload['sha256'];
    final chunkSize = payload['chunkSize'];

    if (transferId is! String || !_transferIdPattern.hasMatch(transferId)) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'file_offer requiere un transferId hexadecimal válido',
      );
    }
    if (name is! String || name.trim().isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'file_offer requiere un nombre de archivo',
      );
    }
    if (size is! int || size <= 0) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'file_offer requiere un tamaño positivo',
      );
    }
    if (size > JScanDefaults.maxFileBytes) {
      throw const ProtocolException(
        ProtocolErrorCode.fileTooLarge,
        'El archivo supera el máximo de ${JScanDefaults.maxFileBytes} bytes',
      );
    }
    if (sha256 is! String || !_sha256Pattern.hasMatch(sha256)) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'file_offer requiere un sha256 hexadecimal de 64 caracteres',
      );
    }
    if (chunkSize is! int ||
        chunkSize < JScanDefaults.minFileChunkBytes ||
        chunkSize > JScanDefaults.maxFileChunkBytes) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'chunkSize debe estar entre '
        '${JScanDefaults.minFileChunkBytes} y '
        '${JScanDefaults.maxFileChunkBytes} bytes',
      );
    }
    if (name.length > 255) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El nombre del archivo es demasiado largo',
      );
    }

    final mimeType = payload['mimeType'];
    return FileOffer(
      transferId: transferId,
      name: name,
      size: size,
      sha256: sha256.toLowerCase(),
      chunkSize: chunkSize,
      mimeType: mimeType is String && mimeType.isNotEmpty ? mimeType : null,
    );
  }

  final String transferId;

  /// Nombre original propuesto por el celular; la PC lo sanea antes de usarlo.
  final String name;
  final int size;

  /// SHA-256 completo del contenido, en hexadecimal minúscula.
  final String sha256;
  final int chunkSize;
  final String? mimeType;

  Map<String, Object?> toJson() => <String, Object?>{
        'transferId': transferId,
        'name': name,
        'size': size,
        'sha256': sha256,
        'chunkSize': chunkSize,
        if (mimeType != null) 'mimeType': mimeType,
      };
}

/// Respuesta `file_accept` (PC → celular).
final class FileAccept {
  const FileAccept({
    required this.transferId,
    required this.offset,
    required this.chunkSize,
  });

  factory FileAccept.fromEnvelopePayload(Map<String, Object?> payload) {
    final transferId = payload['transferId'];
    final offset = payload['offset'];
    final chunkSize = payload['chunkSize'];
    if (transferId is! String || offset is! int || chunkSize is! int) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'file_accept inválido',
      );
    }
    return FileAccept(
      transferId: transferId,
      offset: offset,
      chunkSize: chunkSize,
    );
  }

  final String transferId;

  /// Bytes que la PC ya tiene y verificó; el celular continúa desde aquí.
  final int offset;
  final int chunkSize;

  Map<String, Object?> toJson() => <String, Object?>{
        'transferId': transferId,
        'offset': offset,
        'chunkSize': chunkSize,
      };
}

/// Resultado final de `file_done` (PC → celular).
final class FileDelivery {
  const FileDelivery({
    required this.transferId,
    required this.name,
    required this.path,
    required this.size,
    required this.sha256,
    required this.elapsed,
  });

  final String transferId;
  final String name;
  final String path;
  final int size;
  final String sha256;
  final Duration elapsed;

  int get elapsedMs => elapsed.inMilliseconds;
}

/// El usuario canceló una transferencia de archivo.
final class FileTransferCanceledException implements Exception {
  const FileTransferCanceledException([this.message = 'Envío cancelado']);

  final String message;

  @override
  String toString() => 'FileTransferCanceledException: $message';
}

/// Archivo recibido y verificado por la PC.
final class ReceivedFile {
  const ReceivedFile({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.sha256,
    required this.receivedAt,
    this.mimeType,
    this.fromDeviceId,
    this.fromDeviceName,
    this.duration = Duration.zero,
  });

  final String id;
  final String name;
  final String path;
  final int size;
  final String sha256;
  final DateTime receivedAt;
  final String? mimeType;
  final String? fromDeviceId;
  final String? fromDeviceName;
  final Duration duration;

  bool get isImage => _imageExtensions.contains(_extension(name));
  bool get isVideo => _videoExtensions.contains(_extension(name));
  bool get isAudio => _audioExtensions.contains(_extension(name));

  /// Tamaño legible para la UI (por ejemplo `1.2 GB`).
  String get readableSize {
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = size.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final decimals = unit == 0 ? 0 : (value >= 100 ? 0 : 1);
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'path': path,
        'size': size,
        'sha256': sha256,
        'receivedAt': receivedAt.toUtc().millisecondsSinceEpoch,
        'mimeType': mimeType,
        'fromDeviceId': fromDeviceId,
        'fromDeviceName': fromDeviceName,
        'durationMs': duration.inMilliseconds,
      };
}

/// Calcula el SHA-256 de [file] por bloques, sin cargarlo entero en memoria.
///
/// [onProgress] recibe los bytes procesados y el total. Si [shouldCancel]
/// devuelve `true`, lanza [FileTransferCanceledException].
Future<String> hashFile(
  File file, {
  void Function(int processed, int total)? onProgress,
  bool Function()? shouldCancel,
  int bufferSize = 1024 * 1024,
}) async {
  final sink = _DigestCollector();
  final hasher = sha256.startChunkedConversion(sink);
  final total = await file.length();
  final handle = await file.open();
  try {
    var processed = 0;
    while (true) {
      if (shouldCancel?.call() ?? false) {
        throw const FileTransferCanceledException();
      }
      final data = await handle.read(bufferSize);
      if (data.isEmpty) break;
      hasher.add(data);
      processed += data.length;
      onProgress?.call(processed, total);
    }
    hasher.close();
    return sink.value.toString();
  } finally {
    await handle.close();
  }
}

/// Limpia un nombre recibido para que no pueda escapar de la carpeta destino.
String sanitizeFileName(String name) {
  final base = name.replaceAll('\\', '/').split('/').last.trim();
  var cleaned = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    cleaned = 'archivo';
  }

  final dot = cleaned.lastIndexOf('.');
  final stem = dot > 0 ? cleaned.substring(0, dot) : cleaned;
  final reserved = <String>{
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };
  if (reserved.contains(stem.toUpperCase())) {
    cleaned = '_$cleaned';
  }
  if (cleaned.length > 200) {
    final ext = dot > 0 ? cleaned.substring(dot) : '';
    final keep = ext.length < 20 ? ext : '';
    cleaned = '${cleaned.substring(0, 200 - keep.length)}$keep';
  }
  return cleaned;
}

/// Devuelve una ruta libre dentro de [directory] para [name].
String uniqueFilePath(Directory directory, String name) {
  final separator = Platform.pathSeparator;
  final safe = sanitizeFileName(name);
  var candidate = File('${directory.path}$separator$safe');
  if (!candidate.existsSync()) return candidate.path;

  final dot = safe.lastIndexOf('.');
  final stem = dot > 0 ? safe.substring(0, dot) : safe;
  final extension = dot > 0 ? safe.substring(dot) : '';
  for (var index = 1; index < 10000; index++) {
    candidate = File('${directory.path}$separator$stem ($index)$extension');
    if (!candidate.existsSync()) return candidate.path;
  }
  return '${directory.path}$separator$stem-'
      '${DateTime.now().millisecondsSinceEpoch}$extension';
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

final RegExp _transferIdPattern = RegExp(r'^[a-f0-9]{16,128}$');
final RegExp _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

const Set<String> _imageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'heif',
  'bmp',
  'tif',
  'tiff',
};

const Set<String> _videoExtensions = <String>{
  'mp4',
  'mov',
  'mkv',
  'avi',
  'webm',
  '3gp',
  'm4v',
  'ts',
};

const Set<String> _audioExtensions = <String>{
  'mp3',
  'm4a',
  'aac',
  'wav',
  'ogg',
  'flac',
  'opus',
  'amr',
};

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

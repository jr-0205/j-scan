import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jscan_core/jscan_core.dart';

import 'platform/error_messages.dart';
import 'platform/foreground_service.dart';
import 'storage/mobile_store.dart';

enum ScanStatus { idle, scanning, ready, error }

/// Resultado de probar la conexión con una PC.
final class PeerProbeResult {
  const PeerProbeResult({
    this.rtts = const <Duration>[],
    this.serverName,
    this.error,
  });

  final List<Duration> rtts;
  final String? serverName;
  final String? error;

  bool get ok => error == null && rtts.isNotEmpty;

  Duration? get bestRtt {
    if (rtts.isEmpty) return null;
    return rtts.reduce((a, b) => a < b ? a : b);
  }

  Duration? get averageRtt {
    if (rtts.isEmpty) return null;
    final total = rtts.fold<int>(0, (sum, rtt) => sum + rtt.inMicroseconds);
    return Duration(microseconds: total ~/ rtts.length);
  }
}

/// Resultado de enviar un texto o el portapapeles a una PC.
final class SendResult {
  const SendResult({
    required this.ok,
    this.error,
    this.delivery,
    this.serverName,
    this.elapsed = Duration.zero,
  });

  final bool ok;
  final String? error;
  final MessageDelivery? delivery;
  final String? serverName;
  final Duration elapsed;

  int get elapsedMs => elapsed.inMilliseconds;
}

/// Entrada del historial local de envíos (solo en memoria).
final class SentMessage {
  const SentMessage({
    required this.text,
    required this.kind,
    required this.serverName,
    required this.sentAt,
    required this.result,
  });

  final String text;
  final HistoryKind kind;
  final String serverName;
  final DateTime sentAt;
  final SendResult result;
}

enum FileTaskStatus {
  queued,
  hashing,
  sending,
  completed,
  failed,
  canceled,
}

/// Una transferencia de archivo en curso o terminada.
final class FileSendTask {
  FileSendTask({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.serverId,
    required this.serverName,
  }) : totalBytes = size;

  final String id;
  final String path;
  final String name;
  final int size;
  final String serverId;
  final String serverName;

  FileTaskStatus status = FileTaskStatus.queued;
  int sentBytes = 0;
  int totalBytes;
  String? sha256;
  String? error;
  DateTime? finishedAt;

  /// El usuario pidió cancelar; el envío lo detecta antes del próximo bloque.
  bool cancelRequested = false;

  bool get isActive =>
      status == FileTaskStatus.queued ||
      status == FileTaskStatus.hashing ||
      status == FileTaskStatus.sending;

  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = sentBytes / totalBytes;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  int get percent => (fraction * 100).round();

  String get readableSize => formatFileSize(size);

  String get statusLabel => switch (status) {
        FileTaskStatus.queued => 'En cola',
        FileTaskStatus.hashing => 'Calculando SHA-256',
        FileTaskStatus.sending => cancelRequested ? 'Cancelando…' : 'Enviando',
        FileTaskStatus.completed => 'Recibido por la PC',
        FileTaskStatus.failed => 'Error',
        FileTaskStatus.canceled => 'Cancelado',
      };
}

String formatFileSize(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final decimals = unit == 0 ? 0 : (value >= 100 ? 0 : 1);
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

/// Descubrimiento mDNS, emparejamiento por QR y conexiones cifradas.
final class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    this.autoStart = true,
    KeyValueStore? store,
    MobileRepository? repository,
  }) : _repository = repository ??
            MobileRepository(store ?? const FlutterKeyValueStore()) {
    if (autoStart) {
      unawaited(initialize());
    }
  }

  final bool autoStart;
  final MobileRepository _repository;
  final MdnsBrowser _browser = MdnsBrowser();
  final Map<String, PeerProbeResult> _results = <String, PeerProbeResult>{};
  final Map<String, PeerProbeResult> _serverResults =
      <String, PeerProbeResult>{};
  final Set<String> _probing = <String>{};

  StreamSubscription<List<DiscoveredPeer>>? _subscription;
  Completer<void>? _initCompleter;
  LocalIdentity? _identity;

  ScanStatus status = ScanStatus.idle;
  String? errorMessage;
  DateTime? lastScan;
  List<DiscoveredPeer> peers = const <DiscoveredPeer>[];
  List<PairedServer> pairedServers = const <PairedServer>[];
  List<SentMessage> sentMessages = const <SentMessage>[];
  List<FileSendTask> fileTasks = const <FileSendTask>[];

  /// Texto compartido desde otra app cuando no se puede enviar automáticamente.
  String? pendingSharedText;

  /// Archivos compartidos desde otra app pendientes de elegir PC.
  List<String> pendingSharedFiles = const <String>[];

  final Queue<FileSendTask> _fileQueue = Queue<FileSendTask>();
  final ForegroundTransferService _foreground = ForegroundTransferService();
  bool _processingFile = false;
  int _taskCounter = 0;

  /// Reintentos automáticos de una transferencia ante un corte de red.
  static const int _maxAutoRetries = 1;
  static const Duration _autoRetryDelay = Duration(milliseconds: 1200);

  bool _ready = false;

  int get activeFileTransfers =>
      fileTasks.where((task) => task.isActive).length;

  bool get ready => _ready;

  bool get hasIdentity => _identity != null;

  String get deviceName {
    final hostname = Platform.localHostname;
    if (hostname.isEmpty || hostname == 'localhost') {
      final id = _identity?.id ?? '0000';
      return 'Celular ${id.substring(0, id.length < 4 ? id.length : 4)}';
    }
    return hostname;
  }

  String get deviceId => _identity?.id ?? '—';

  PeerProbeResult? resultFor(DiscoveredPeer peer) =>
      _results[peer.instanceName];

  PeerProbeResult? resultForServer(PairedServer server) =>
      _serverResults[server.serverId];

  bool isProbing(DiscoveredPeer peer) => _probing.contains(peer.instanceName);

  bool isProbingServer(PairedServer server) =>
      _probing.contains('server:${server.serverId}');

  bool isPaired(String serverId) =>
      pairedServers.any((server) => server.serverId == serverId);

  PairedServer? serverForPeer(DiscoveredPeer peer) {
    for (final server in pairedServers) {
      if (server.serverId == peer.id) return server;
    }
    return null;
  }

  /// Carga (o crea) la identidad del celular y las PCs emparejadas.
  Future<void> initialize({bool scan = true}) async {
    if (_ready) {
      if (scan) await start();
      return;
    }

    final existing = _initCompleter;
    if (existing != null) {
      await existing.future;
      if (scan) await start();
      return;
    }

    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      _identity = await _repository.loadOrCreateIdentity();
      pairedServers = await _repository.loadServers();
      _ready = true;
      notifyListeners();
      completer.complete();
    } catch (error) {
      status = ScanStatus.error;
      errorMessage = describeError(
        error,
        fallback: 'No se pudo cargar la identidad del celular.',
      );
      completer.complete();
      notifyListeners();
    } finally {
      _initCompleter = null;
    }

    if (scan) await start();
  }

  Future<void> start() async {
    if (!_ready) {
      await initialize(scan: false);
      if (!_ready) return;
    }
    if (status == ScanStatus.scanning) return;

    status = ScanStatus.scanning;
    errorMessage = null;
    notifyListeners();

    try {
      _subscription ??= _browser.peers.listen(_onPeers);
      if (!_browser.isRunning) {
        await _browser.start();
      }
      await scan();
    } catch (error) {
      status = ScanStatus.error;
      errorMessage = describeError(
        error,
        fallback: 'No se pudo iniciar el descubrimiento de PCs.',
      );
      notifyListeners();
    }
  }

  Future<void> scan({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!_ready) {
      await initialize(scan: false);
      if (!_ready) return;
    }

    status = ScanStatus.scanning;
    errorMessage = null;
    notifyListeners();

    try {
      final found = await _browser.refresh(timeout: timeout);
      peers = found;
      lastScan = DateTime.now();
      status = ScanStatus.ready;
    } catch (error) {
      status = ScanStatus.error;
      errorMessage = describeError(
        error,
        fallback: 'No se pudieron buscar PCs en la red.',
      );
    }
    notifyListeners();
  }

  void _onPeers(List<DiscoveredPeer> found) {
    peers = found;
    if (status != ScanStatus.ready) {
      status = ScanStatus.ready;
    }
    notifyListeners();
  }

  /// Empareja el celular con la PC descrita por el QR [raw].
  Future<PairedServer> pairWithCode(String raw) async {
    await initialize(scan: false);
    final identity = _identity;
    if (identity == null) {
      throw const JScanConnectionException(
        'La identidad del celular no está disponible',
      );
    }

    final code = PairingCode.decode(raw);
    if (code.isExpired()) {
      throw const ProtocolException(
        ProtocolErrorCode.pairingExpired,
        'El código QR caducó; genera uno nuevo en la PC',
      );
    }

    final result = await JScanClient.pair(
      code: code,
      identity: identity,
      device: _deviceInfo(identity),
    );
    await _upsertServer(result.server);
    return result.server;
  }

  /// Conecta y mide tres pings contra una PC descubierta por mDNS.
  Future<PeerProbeResult> probe(DiscoveredPeer peer) async {
    final key = peer.instanceName;
    if (_probing.contains(key)) {
      return _results[key] ?? const PeerProbeResult(error: 'Prueba en curso');
    }

    final paired = serverForPeer(peer);
    if (paired == null) {
      final result = PeerProbeResult(
        error: 'PC sin emparejar. Escanea el QR que muestra '
            '${peer.name} en la app de la PC.',
      );
      _results[key] = result;
      notifyListeners();
      return result;
    }

    _probing.add(key);
    notifyListeners();

    var result = const PeerProbeResult(error: 'Error desconocido');
    try {
      final updated = paired.copyWith(
        host: peer.connectHost,
        port: peer.port,
        name: peer.name,
      );
      result = await _pingServer(updated);
      if (result.ok) {
        await _upsertServer(updated.copyWith(lastSeenAt: DateTime.now()));
      }
    } finally {
      _probing.remove(key);
      _results[key] = result;
      notifyListeners();
    }
    return result;
  }

  /// Conecta y mide tres pings contra una PC emparejada (sin mDNS).
  Future<PeerProbeResult> probeServer(PairedServer server) async {
    final key = 'server:${server.serverId}';
    if (_probing.contains(key)) {
      return _serverResults[server.serverId] ??
          const PeerProbeResult(error: 'Prueba en curso');
    }

    _probing.add(key);
    notifyListeners();

    var result = const PeerProbeResult(error: 'Error desconocido');
    try {
      result = await _pingServer(server);
      if (result.ok) {
        await _upsertServer(server.copyWith(lastSeenAt: DateTime.now()));
      }
    } finally {
      _probing.remove(key);
      _serverResults[server.serverId] = result;
      notifyListeners();
    }
    return result;
  }

  Future<PeerProbeResult> _pingServer(PairedServer server) async {
    final identity = _identity;
    if (identity == null) {
      return const PeerProbeResult(error: 'Falta la identidad del celular');
    }

    JScanClient? client;
    try {
      client = await JScanClient.connectPaired(
        server: server,
        identity: identity,
        device: _deviceInfo(identity),
      );
      final rtts = <Duration>[
        await client.ping(),
        await client.ping(),
        await client.ping(),
      ];
      return PeerProbeResult(
        rtts: rtts,
        serverName: client.serverInfo?.name ?? server.name,
      );
    } on ProtocolException catch (error) {
      return PeerProbeResult(error: describeError(error));
    } catch (error) {
      return PeerProbeResult(error: describeError(error));
    } finally {
      await client?.close();
    }
  }

  /// Envía un texto (o el portapapeles) cifrado a una PC emparejada.
  ///
  /// Abre una sesión nueva, autentica con X25519, envía el mensaje y espera la
  /// confirmación del servidor. La conexión se cierra al terminar.
  Future<SendResult> sendTextTo(
    PairedServer server,
    String text, {
    bool fromClipboard = false,
  }) async {
    await initialize(scan: false);
    final identity = _identity;
    final kind = fromClipboard ? HistoryKind.clipboard : HistoryKind.text;
    final serverName = server.name;
    final stopwatch = Stopwatch()..start();

    if (identity == null) {
      return _recordFailure(
        text: text,
        kind: kind,
        serverName: serverName,
        error: 'La identidad del celular no está disponible',
        stopwatch: stopwatch,
      );
    }
    if (text.trim().isEmpty) {
      return _recordFailure(
        text: text,
        kind: kind,
        serverName: serverName,
        error: 'No hay texto para enviar',
        stopwatch: stopwatch,
      );
    }

    var attempts = 0;
    while (true) {
      attempts += 1;
      JScanClient? client;
      try {
        client = await JScanClient.connectPaired(
          server: server,
          identity: identity,
          device: _deviceInfo(identity),
        );
        final delivery = fromClipboard
            ? await client.sendClipboard(text)
            : await client.sendText(text);
        stopwatch.stop();

        final result = SendResult(
          ok: true,
          delivery: delivery,
          serverName: client.serverInfo?.name ?? serverName,
          elapsed: stopwatch.elapsed,
        );
        _recordSent(text, kind, result);
        return result;
      } on ProtocolException catch (error) {
        return _recordFailure(
          text: text,
          kind: kind,
          serverName: serverName,
          error: describeError(error),
          stopwatch: stopwatch,
        );
      } catch (error) {
        if (attempts <= _maxAutoRetries && isTransientNetworkError(error)) {
          await Future<void>.delayed(_autoRetryDelay);
          continue;
        }
        return _recordFailure(
          text: text,
          kind: kind,
          serverName: serverName,
          error: describeError(error),
          stopwatch: stopwatch,
        );
      } finally {
        await client?.close();
      }
    }
  }

  /// Envía automáticamente un texto recibido por «Compartir».
  ///
  /// Si hay exactamente una PC emparejada se envía al instante; con cero o
  /// varias se guarda en [pendingSharedText] para que la UI pregunte.
  Future<SendResult?> sendSharedText(String text) async {
    await initialize(scan: false);
    if (pairedServers.length != 1) {
      pendingSharedText = text;
      notifyListeners();
      return null;
    }
    pendingSharedText = null;
    return sendTextTo(pairedServers.first, text);
  }

  void clearPendingSharedText() {
    if (pendingSharedText == null) return;
    pendingSharedText = null;
    notifyListeners();
  }

  /// Encola el envío de [paths] hacia [server].
  ///
  /// Las transferencias se ejecutan de una en una para no saturar el Wi-Fi y
  /// para que el progreso y la reanudación sean claros.
  Future<void> sendFilesTo(PairedServer server, List<String> paths) async {
    await initialize(scan: false);
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final size = await file.length();
      if (size <= 0) continue;
      final task = FileSendTask(
        id: 'f${DateTime.now().microsecondsSinceEpoch}-${_taskCounter++}',
        path: path,
        name: file.uri.pathSegments.last,
        size: size,
        serverId: server.serverId,
        serverName: server.name,
      );
      fileTasks = <FileSendTask>[task, ...fileTasks].take(40).toList();
      _fileQueue.add(task);
    }
    notifyListeners();
    _pumpFileQueue();
  }

  /// Envía archivos compartidos desde otra app.
  ///
  /// Con una sola PC emparejada se envían al instante; si no, quedan en
  /// [pendingSharedFiles] para que la UI pregunte el destino.
  Future<void> sendSharedFiles(List<String> paths) async {
    await initialize(scan: false);
    if (paths.isEmpty) return;
    if (pairedServers.length != 1) {
      pendingSharedFiles = paths;
      notifyListeners();
      return;
    }
    pendingSharedFiles = const <String>[];
    await sendFilesTo(pairedServers.first, paths);
  }

  void clearPendingSharedFiles() {
    if (pendingSharedFiles.isEmpty) return;
    pendingSharedFiles = const <String>[];
    notifyListeners();
  }

  /// Cancela una tarea en cola o en curso.
  void cancelFileTask(FileSendTask task) {
    if (!task.isActive) return;
    task.cancelRequested = true;
    if (task.status == FileTaskStatus.queued) {
      _fileQueue.remove(task);
      task.status = FileTaskStatus.canceled;
      task.finishedAt = DateTime.now();
    }
    notifyListeners();
  }

  /// Reintenta una tarea fallida o cancelada con [server].
  Future<void> retryFileTask(FileSendTask task, PairedServer server) async {
    if (task.isActive) return;
    task
      ..status = FileTaskStatus.queued
      ..sentBytes = 0
      ..totalBytes = task.size
      ..error = null
      ..sha256 = null
      ..finishedAt = null
      ..cancelRequested = false;
    _fileQueue.add(task);
    notifyListeners();
    _pumpFileQueue();
  }

  void _pumpFileQueue() {
    if (_processingFile) return;
    if (_fileQueue.isEmpty) {
      unawaited(_foreground.stop());
      return;
    }

    final task = _fileQueue.removeFirst();
    _processingFile = true;
    unawaited(
      _runFileTask(task).whenComplete(() {
        _processingFile = false;
        _pumpFileQueue();
      }),
    );
  }

  Future<void> _runFileTask(FileSendTask task) async {
    final identity = _identity;
    if (identity == null) {
      task
        ..status = FileTaskStatus.failed
        ..error = 'La identidad del celular no está disponible';
      notifyListeners();
      return;
    }

    PairedServer? selected;
    for (final item in pairedServers) {
      if (item.serverId == task.serverId) {
        selected = item;
        break;
      }
    }
    final target = selected;
    if (target == null) {
      task
        ..status = FileTaskStatus.failed
        ..error = 'La PC de destino ya no está emparejada';
      notifyListeners();
      return;
    }

    var attempts = 0;
    while (true) {
      attempts += 1;
      task
        ..status = FileTaskStatus.hashing
        ..sentBytes = 0
        ..totalBytes = task.size
        ..error = null;
      notifyListeners();
      unawaited(_foreground.start(title: 'Preparando ${task.name}'));
      _updateForeground(task);

      JScanClient? client;
      try {
        client = await JScanClient.connectPaired(
          server: target,
          identity: identity,
          device: _deviceInfo(identity),
        );
        final delivery = await client.sendFile(
          File(task.path),
          name: task.name,
          shouldCancel: () => task.cancelRequested,
          onProgress: (progress) {
            task
              ..sentBytes = progress.sentBytes
              ..totalBytes = progress.totalBytes
              ..status = switch (progress.phase) {
                FileTransferPhase.hashing => FileTaskStatus.hashing,
                FileTransferPhase.uploading => FileTaskStatus.sending,
                FileTransferPhase.completed => FileTaskStatus.completed,
              };
            _updateForeground(task);
            notifyListeners();
          },
        );
        task
          ..status = FileTaskStatus.completed
          ..sentBytes = task.totalBytes
          ..sha256 = delivery.sha256
          ..finishedAt = DateTime.now();
        return;
      } on FileTransferCanceledException {
        task
          ..status = FileTaskStatus.canceled
          ..finishedAt = DateTime.now();
        return;
      } on ProtocolException catch (error) {
        if (error.code == ProtocolErrorCode.cancelled) {
          task
            ..status = FileTaskStatus.canceled
            ..finishedAt = DateTime.now();
        } else {
          task
            ..status = FileTaskStatus.failed
            ..error = describeError(error)
            ..finishedAt = DateTime.now();
        }
        return;
      } catch (error) {
        if (task.cancelRequested) {
          task
            ..status = FileTaskStatus.canceled
            ..finishedAt = DateTime.now();
          return;
        }
        final retry =
            attempts <= _maxAutoRetries && isTransientNetworkError(error);
        if (retry) {
          // La PC puede estar ocupada o el Wi-Fi haber tenido un corte corto.
          // `sendFile` reanuda desde el offset que recuerda la PC gracias al
          // SHA-256, así que reintentar no duplica datos ya recibidos.
          await Future<void>.delayed(_autoRetryDelay);
          continue;
        }
        task
          ..status = FileTaskStatus.failed
          ..error = describeError(
            error,
            fallback: 'No se pudo enviar el archivo.',
          )
          ..finishedAt = DateTime.now();
        return;
      } finally {
        await client?.close();
        notifyListeners();
      }
    }
  }

  void _updateForeground(FileSendTask task) {
    if (!task.isActive) return;
    unawaited(
      _foreground.update(
        title: task.status == FileTaskStatus.hashing
            ? 'Preparando ${task.name}'
            : 'Enviando ${task.name}',
        progress: task.status == FileTaskStatus.hashing ? 0 : task.percent,
      ),
    );
  }

  SendResult _recordFailure({
    required String text,
    required HistoryKind kind,
    required String serverName,
    required String error,
    required Stopwatch stopwatch,
  }) {
    stopwatch.stop();
    final result = SendResult(
      ok: false,
      error: error,
      serverName: serverName,
      elapsed: stopwatch.elapsed,
    );
    _recordSent(text, kind, result);
    return result;
  }

  void _recordSent(String text, HistoryKind kind, SendResult result) {
    sentMessages = <SentMessage>[
      SentMessage(
        text: text,
        kind: kind,
        serverName: result.serverName ?? 'PC',
        sentAt: DateTime.now(),
        result: result,
      ),
      ...sentMessages,
    ].take(30).toList();
    notifyListeners();
  }

  Future<void> removeServer(PairedServer server) async {
    pairedServers = pairedServers
        .where((item) => item.serverId != server.serverId)
        .toList();
    _serverResults.remove(server.serverId);
    await _repository.saveServers(pairedServers);
    notifyListeners();
  }

  Future<void> _upsertServer(PairedServer server) async {
    final list = <PairedServer>[...pairedServers];
    final index = list.indexWhere(
      (item) => item.serverId == server.serverId,
    );
    if (index == -1) {
      list.insert(0, server);
    } else {
      list[index] = server;
    }
    pairedServers = list;
    await _repository.saveServers(list);
    notifyListeners();
  }

  DeviceInfo _deviceInfo(LocalIdentity identity) {
    return DeviceInfo(
      id: identity.id,
      name: deviceName,
      platform: currentPlatform(),
      appVersion: '0.2.1',
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_browser.stop());
    unawaited(_foreground.stop());
    super.dispose();
  }
}

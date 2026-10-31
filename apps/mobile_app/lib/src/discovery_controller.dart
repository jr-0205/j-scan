import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jscan_core/jscan_core.dart';

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
  bool _ready = false;

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
      errorMessage = 'No se pudo cargar la identidad: $error';
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
      errorMessage = 'No se pudo iniciar el descubrimiento: $error';
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
      errorMessage = 'Error al buscar PCs: $error';
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
      return PeerProbeResult(error: '${error.code}: ${error.message}');
    } catch (error) {
      return PeerProbeResult(error: '$error');
    } finally {
      await client?.close();
    }
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
      appVersion: '0.1.0',
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_browser.stop());
    super.dispose();
  }
}

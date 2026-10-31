import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jscan_core/jscan_core.dart';

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

/// Descubrimiento mDNS y pruebas de conexión desde el celular.
final class DiscoveryController extends ChangeNotifier {
  DiscoveryController({this.autoStart = true}) {
    if (autoStart) {
      unawaited(start());
    }
  }

  final bool autoStart;

  final MdnsBrowser _browser = MdnsBrowser();
  final Map<String, PeerProbeResult> _results = <String, PeerProbeResult>{};
  final Set<String> _probing = <String>{};
  final String _deviceId = newId(4);

  StreamSubscription<List<DiscoveredPeer>>? _subscription;
  ScanStatus status = ScanStatus.idle;
  String? errorMessage;
  DateTime? lastScan;
  List<DiscoveredPeer> peers = const <DiscoveredPeer>[];

  String get deviceName {
    final hostname = Platform.localHostname;
    if (hostname.isEmpty || hostname == 'localhost') {
      return 'Celular ${_deviceId.substring(0, 4)}';
    }
    return hostname;
  }

  PeerProbeResult? resultFor(DiscoveredPeer peer) =>
      _results[peer.instanceName];

  bool isProbing(DiscoveredPeer peer) => _probing.contains(peer.instanceName);

  Future<void> start() async {
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

  /// Conecta, hace el handshake y mide tres pings contra [peer].
  Future<PeerProbeResult> probe(DiscoveredPeer peer) async {
    final key = peer.instanceName;
    if (_probing.contains(key)) {
      return _results[key] ?? const PeerProbeResult(error: 'Prueba en curso');
    }

    _probing.add(key);
    notifyListeners();

    PeerProbeResult result = const PeerProbeResult(
      error: 'Error desconocido',
    );
    JScanClient? client;
    try {
      client = await _connect(peer.connectHost, peer.port);
      final rtts = <Duration>[
        await client.ping(),
        await client.ping(),
        await client.ping(),
      ];
      result = PeerProbeResult(
        rtts: rtts,
        serverName: client.serverInfo?.name ?? peer.name,
      );
    } on ProtocolException catch (error) {
      result = PeerProbeResult(
        error: '${error.code}: ${error.message}',
      );
    } catch (error) {
      result = PeerProbeResult(error: '$error');
    } finally {
      await client?.close();
      _probing.remove(key);
      _results[key] = result;
      notifyListeners();
    }
    return result;
  }

  /// Prueba una IP escrita a mano (útil si el router bloquea multicast).
  Future<PeerProbeResult> probeManual({
    required String host,
    required int port,
  }) async {
    JScanClient? client;
    try {
      client = await _connect(host, port);
      final rtts = <Duration>[
        await client.ping(),
        await client.ping(),
        await client.ping(),
      ];
      return PeerProbeResult(
        rtts: rtts,
        serverName: client.serverInfo?.name ?? host,
      );
    } on ProtocolException catch (error) {
      return PeerProbeResult(
        error: '${error.code}: ${error.message}',
      );
    } catch (error) {
      return PeerProbeResult(error: '$error');
    } finally {
      await client?.close();
    }
  }

  Future<JScanClient> _connect(String host, int port) {
    return JScanClient.connect(
      host: host,
      port: port,
      timeout: const Duration(seconds: 5),
      device: DeviceInfo(
        id: _deviceId,
        name: deviceName,
        platform: currentPlatform(),
        appVersion: '0.1.0',
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_browser.stop());
    super.dispose();
  }
}

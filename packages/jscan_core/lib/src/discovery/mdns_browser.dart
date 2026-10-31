import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../network/network_info.dart';
import '../protocol/constants.dart';
import 'discovered_peer.dart';
import 'dns.dart';

final class _ServiceEntry {
  String? host;
  int? port;
  Map<String, String> txt = const <String, String>{};
  DateTime lastSeen = DateTime.now();
}

/// Descubre PCs J-SCAN con consultas mDNS.
///
/// Escucha en un puerto efímero y pide respuestas unicast (bit QU), así evita
/// los problemas de bindear 5353 en Android/iOS y no requiere `MulticastLock`.
final class MdnsBrowser {
  MdnsBrowser({
    this.serviceType = JScanDefaults.serviceType,
    this.queryInterval = const Duration(seconds: 3),
    this.onError,
  });

  final String serviceType;
  final Duration queryInterval;
  final void Function(Object error, StackTrace stackTrace)? onError;

  final Map<String, _ServiceEntry> _services = <String, _ServiceEntry>{};
  final Map<String, String> _addresses = <String, String>{};
  final Map<String, DateTime> _addressSeen = <String, DateTime>{};
  List<String> _localSubnets = const <String>[];
  final StreamController<List<DiscoveredPeer>> _controller =
      StreamController<List<DiscoveredPeer>>.broadcast();

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _timer;
  List<DiscoveredPeer> _current = const <DiscoveredPeer>[];

  /// Emite la lista completa cada vez que cambia.
  Stream<List<DiscoveredPeer>> get peers => _controller.stream;

  /// Última lista conocida, ordenada por nombre.
  List<DiscoveredPeer> get current =>
      List<DiscoveredPeer>.unmodifiable(_current);

  bool get isRunning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.multicastLoopback = true;
    _socket = socket;
    _localSubnets = _subnetsOf(await localIPv4Addresses());
    _subscription = socket.listen(_handleSocketEvent);
    await query();
    _timer = Timer.periodic(queryInterval, (_) {
      query().catchError((Object error, StackTrace stackTrace) {
        onError?.call(error, stackTrace);
      });
    });
  }

  /// Envía una consulta PTR y espera [timeout] para juntar respuestas.
  Future<List<DiscoveredPeer>> refresh({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    await query();
    await Future<void>.delayed(timeout);
    return current;
  }

  /// Envía una consulta mDNS PTR pidiendo respuesta unicast.
  Future<void> query() async {
    final socket = _socket;
    if (socket == null) return;
    final packet = encodeDnsQuery(
      id: Random.secure().nextInt(0xFFFF),
      name: serviceType,
      type: DnsType.ptr,
      unicastResponse: true,
    );
    socket.send(
      packet,
      InternetAddress(MdnsSettings.multicastGroup),
      MdnsSettings.port,
    );
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    await _controller.close();
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;

    while (true) {
      final datagram = socket.receive();
      if (datagram == null) break;
      _handleDatagram(datagram);
    }
  }

  void _handleDatagram(Datagram datagram) {
    final DnsPacket packet;
    try {
      packet = parseDnsPacket(datagram.data);
    } on FormatException {
      return;
    }

    var changed = false;
    final now = DateTime.now();

    for (final record in packet.records) {
      final name = record.name.toLowerCase();
      final service = serviceType.toLowerCase();

      if (record.type == DnsType.ptr && name == service) {
        final target = record.target?.toLowerCase();
        if (target == null || target.isEmpty) continue;
        if (record.ttl == 0) {
          changed = _services.remove(target) != null || changed;
          continue;
        }
        final entry = _services.putIfAbsent(target, _ServiceEntry.new);
        entry.lastSeen = now;
        changed = true;
      } else if (record.type == DnsType.srv && _isInstance(name)) {
        if (record.ttl == 0) {
          changed = _services.remove(name) != null || changed;
          continue;
        }
        final entry = _services.putIfAbsent(name, _ServiceEntry.new);
        final nextHost = record.target;
        final nextPort = record.port;
        if (nextHost != null && nextPort != null) {
          changed = entry.host != nextHost || entry.port != nextPort || changed;
          entry.host = nextHost;
          entry.port = nextPort;
          entry.lastSeen = now;
        }
      } else if (record.type == DnsType.txt && _isInstance(name)) {
        if (record.ttl == 0) {
          changed = _services.remove(name) != null || changed;
          continue;
        }
        final entry = _services.putIfAbsent(name, _ServiceEntry.new);
        final parsed = _parseTxt(record.txt ?? const <String>[]);
        entry.txt = parsed;
        entry.lastSeen = now;
        changed = true;
      } else if (record.type == DnsType.a) {
        final host = name;
        if (record.ttl == 0) {
          changed = _addresses.remove(host) != null || changed;
          _addressSeen.remove(host);
          continue;
        }
        final address = record.address;
        if (address == null) continue;
        final previous = _addresses[host];
        // Varias A para el mismo host: quedarse con la de la misma subred
        // que el celular; si no, con la primera privada.
        if (previous == null ||
            _addressScore(address) < _addressScore(previous)) {
          _addresses[host] = address;
          changed = true;
        }
        _addressSeen[host] = now;
      }
    }

    if (changed) {
      _emitPeers();
    }
  }

  bool _isInstance(String name) {
    final suffix = '.${serviceType.toLowerCase()}';
    return name.endsWith(suffix) && name.length > suffix.length;
  }

  List<String> _subnetsOf(List<String> addresses) {
    final subnets = <String>{};
    for (final address in addresses) {
      final parts = address.split('.');
      if (parts.length >= 3) {
        subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }
    return subnets.toList();
  }

  int _addressScore(String address) {
    final parts = address.split('.');
    if (parts.length >= 3) {
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      if (_localSubnets.contains(subnet)) return 0;
    }
    if (address.startsWith('192.168.')) return 20;
    if (address.startsWith('10.')) return 21;
    if (address.startsWith('172.') && parts.length > 1) {
      final second = int.tryParse(parts[1]);
      if (second != null && second >= 16 && second <= 31) return 22;
    }
    if (address.startsWith('127.')) return 40;
    return 30;
  }

  Map<String, String> _parseTxt(List<String> records) {
    final result = <String, String>{};
    for (final record in records) {
      final separator = record.indexOf('=');
      if (separator <= 0) continue;
      result[record.substring(0, separator)] = record.substring(separator + 1);
    }
    return result;
  }

  void _emitPeers() {
    final now = DateTime.now();
    _services.removeWhere(
      (_, entry) => now.difference(entry.lastSeen) > const Duration(minutes: 5),
    );

    final peers = <DiscoveredPeer>[];
    for (final entry in _services.entries) {
      final service = entry.value;
      final host = service.host;
      final port = service.port;
      if (host == null || port == null) continue;

      final address = _addresses[host.toLowerCase()];
      if (address == null) continue;

      final txt = service.txt;
      final label = entry.key.split('.').first;
      peers.add(
        DiscoveredPeer(
          instanceName: entry.key,
          id: txt['id'] ?? '',
          name: txt['name'] ?? label,
          host: host,
          address: address,
          port: port,
          protocolVersion:
              int.tryParse(txt['proto'] ?? '') ?? JScanDefaults.protocolVersion,
          txt: Map<String, String>.unmodifiable(txt),
        ),
      );
    }

    peers.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final signature = peers.map((peer) => peer.signature).join('\n');
    final previous = _current.map((peer) => peer.signature).join('\n');
    if (signature == previous) return;

    _current = List<DiscoveredPeer>.unmodifiable(peers);
    if (!_controller.isClosed) {
      _controller.add(_current);
    }
  }
}

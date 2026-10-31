import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../network/network_info.dart';
import '../protocol/constants.dart';
import 'dns.dart';

/// Publica la PC en la red local mediante mDNS/DNS-SD.
///
/// Escucha consultas en el puerto 5353 y responde con PTR, SRV, TXT y A.
/// Si el puerto está ocupado por otro servicio mDNS, sigue enviando anuncios
/// periódicos desde un puerto efímero y lo reporta por [onError].
final class MdnsAdvertiser {
  MdnsAdvertiser({
    required this.serverId,
    required this.displayName,
    this.port = JScanDefaults.port,
    this.serviceType = JScanDefaults.serviceType,
    this.protocolVersion = JScanDefaults.protocolVersion,
    this.wsPath = JScanDefaults.wsPath,
    this.os = '',
    this.includeLoopback = false,
    this.announceInterval = const Duration(seconds: 60),
    this.onError,
  }) : _shortId = _shorten(serverId);

  final String serverId;
  final String displayName;
  final int port;
  final String serviceType;
  final int protocolVersion;
  final String wsPath;
  final String os;
  final bool includeLoopback;
  final Duration announceInterval;
  final void Function(Object error, StackTrace stackTrace)? onError;

  final String _shortId;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _announceTimer;
  Timer? _secondAnnouncement;
  bool _started = false;

  bool get isRunning => _started;
  bool get isBindingOnMdnsPort =>
      _socket != null && _socket!.port == MdnsSettings.port;

  String get instanceName => '${JScanDefaults.appName}-$_shortId';
  String get instanceFqdn => '$instanceName.$serviceType';
  String get hostFqdn => '${JScanDefaults.hostPrefix}-$_shortId.local';

  /// Inicia el anunciante. Es idempotente.
  Future<void> start() async {
    if (_started) return;
    final socket = await _bind();
    _socket = socket;
    socket.multicastLoopback = true;
    socket.multicastHops = 255;
    try {
      socket.joinMulticast(InternetAddress(MdnsSettings.multicastGroup));
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
    _subscription = socket.listen(_handleSocketEvent);
    _started = true;

    await _sendAnnouncement();
    _secondAnnouncement = Timer(
      const Duration(seconds: 1),
      () =>
          _sendAnnouncement().catchError((Object error, StackTrace stackTrace) {
        onError?.call(error, stackTrace);
      }),
    );
    _announceTimer = Timer.periodic(announceInterval, (_) {
      _sendAnnouncement().catchError((Object error, StackTrace stackTrace) {
        onError?.call(error, stackTrace);
      });
    });
  }

  /// Deja de anunciar y envía un goodbye (TTL 0).
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _announceTimer?.cancel();
    _secondAnnouncement?.cancel();
    _announceTimer = null;
    _secondAnnouncement = null;

    try {
      await _sendAnnouncement(ttl: 0);
    } catch (_) {
      // El goodbye es best-effort.
    }

    final socket = _socket;
    _socket = null;
    await _subscription?.cancel();
    _subscription = null;
    if (socket != null) {
      try {
        socket.leaveMulticast(InternetAddress(MdnsSettings.multicastGroup));
      } catch (_) {
        // La interfaz pudo desaparecer antes de cerrar.
      }
      socket.close();
    }
  }

  Future<RawDatagramSocket> _bind() async {
    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        MdnsSettings.port,
        reuseAddress: true,
      );
    } on SocketException catch (error) {
      onError?.call(
        StateError(
          'No se pudo escuchar mDNS en 5353 (${error.message}); '
          'se anunciará desde un puerto efímero. El descubrimiento por '
          'consulta puede no funcionar.',
        ),
        StackTrace.current,
      );
      return RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
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
    if (packet.isResponse || packet.questions.isEmpty) return;
    if (!_shouldRespond(packet.questions)) return;

    unawaited(_respond(datagram, packet.id));
  }

  bool _shouldRespond(List<DnsQuestion> questions) {
    final service = serviceType.toLowerCase();
    final instance = instanceFqdn.toLowerCase();
    final host = hostFqdn.toLowerCase();

    for (final question in questions) {
      final name = question.name.toLowerCase();
      if (name == service && _matchesType(question.type, DnsType.ptr)) {
        return true;
      }
      if (name == instance &&
          (_matchesType(question.type, DnsType.srv) ||
              _matchesType(question.type, DnsType.txt))) {
        return true;
      }
      if (name == host && _matchesType(question.type, DnsType.a)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesType(int queryType, int recordType) =>
      queryType == recordType || queryType == DnsType.any;

  Future<void> _respond(Datagram datagram, int queryId) async {
    final socket = _socket;
    if (socket == null) return;
    final records = await _buildRecords(ttl: MdnsSettings.defaultTtl);
    final packet = encodeDnsResponse(id: queryId, answers: records);

    final fromMdnsPort = datagram.port == MdnsSettings.port;
    final target = fromMdnsPort
        ? InternetAddress(MdnsSettings.multicastGroup)
        : datagram.address;
    final targetPort = fromMdnsPort ? MdnsSettings.port : datagram.port;
    socket.send(packet, target, targetPort);
  }

  Future<void> _sendAnnouncement({int ttl = MdnsSettings.defaultTtl}) async {
    final socket = _socket;
    if (socket == null) return;
    final records = await _buildRecords(ttl: ttl);
    final packet = encodeDnsResponse(id: 0, answers: records);
    socket.send(
      packet,
      InternetAddress(MdnsSettings.multicastGroup),
      MdnsSettings.port,
    );
  }

  Future<List<DnsRecord>> _buildRecords({required int ttl}) async {
    var addresses = await localIPv4Addresses(
      includeLoopback: includeLoopback,
    );
    if (addresses.isEmpty) {
      addresses = const <String>['127.0.0.1'];
    }

    return <DnsRecord>[
      DnsRecord.ptr(name: serviceType, target: instanceFqdn, ttl: ttl),
      DnsRecord.srv(
        name: instanceFqdn,
        target: hostFqdn,
        port: port,
        ttl: ttl,
      ),
      DnsRecord.txt(name: instanceFqdn, txt: _txtRecords, ttl: ttl),
      for (final address in addresses)
        DnsRecord.a(
          name: hostFqdn,
          address: address,
          ttl: ttl == 0 ? 0 : MdnsSettings.addressTtl,
        ),
    ];
  }

  List<String> get _txtRecords => <String>[
        'id=$serverId',
        'name=$displayName',
        'proto=$protocolVersion',
        'path=$wsPath',
        if (os.isNotEmpty) 'os=$os',
      ];
}

String _shorten(String value) {
  final clean = value.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  if (clean.isEmpty) {
    return Random.secure().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  }
  return clean.length <= 8 ? clean : clean.substring(0, 8);
}

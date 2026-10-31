import '../crypto/bytes.dart';

/// Celular autorizado por la PC.
final class PairedDevice {
  const PairedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.pairedAt,
    this.appVersion = '0.1.0',
    this.lastSeenAt,
  });

  factory PairedDevice.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('El dispositivo debe ser un objeto JSON');
    }
    final map = Map<String, Object?>.from(json);
    final deviceId = map['deviceId'];
    final name = map['name'];
    final platform = map['platform'];
    final publicKey = map['publicKey'];
    final pairedAt = map['pairedAt'];
    if (deviceId is! String ||
        deviceId.isEmpty ||
        name is! String ||
        name.isEmpty ||
        platform is! String ||
        platform.isEmpty ||
        publicKey is! String ||
        pairedAt is! String) {
      throw const FormatException('Dispositivo emparejado incompleto');
    }

    final lastSeen = map['lastSeenAt'];
    return PairedDevice(
      deviceId: deviceId,
      name: name,
      platform: platform,
      appVersion:
          map['appVersion'] is String ? map['appVersion']! as String : '0.1.0',
      publicKey: decodeBase64(publicKey),
      pairedAt: DateTime.parse(pairedAt),
      lastSeenAt: lastSeen is String ? DateTime.parse(lastSeen) : null,
    );
  }

  final String deviceId;
  final String name;
  final String platform;
  final String appVersion;
  final List<int> publicKey;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;

  PairedDevice copyWith({
    String? name,
    String? platform,
    String? appVersion,
    List<int>? publicKey,
    DateTime? lastSeenAt,
  }) {
    return PairedDevice(
      deviceId: deviceId,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      publicKey: publicKey ?? this.publicKey,
      pairedAt: pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'deviceId': deviceId,
        'name': name,
        'platform': platform,
        'appVersion': appVersion,
        'publicKey': encodeBase64(publicKey),
        'pairedAt': pairedAt.toUtc().toIso8601String(),
        'lastSeenAt': lastSeenAt?.toUtc().toIso8601String(),
      };

  @override
  String toString() => 'PairedDevice($name, $deviceId)';
}

/// PC autorizada en el celular.
final class PairedServer {
  const PairedServer({
    required this.serverId,
    required this.name,
    required this.host,
    required this.port,
    required this.publicKey,
    required this.pairedAt,
    this.lastSeenAt,
  });

  factory PairedServer.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('La PC emparejada debe ser un objeto JSON');
    }
    final map = Map<String, Object?>.from(json);
    final serverId = map['serverId'];
    final name = map['name'];
    final host = map['host'];
    final port = map['port'];
    final publicKey = map['publicKey'];
    final pairedAt = map['pairedAt'];
    if (serverId is! String ||
        serverId.isEmpty ||
        name is! String ||
        name.isEmpty ||
        host is! String ||
        host.isEmpty ||
        port is! int ||
        publicKey is! String ||
        pairedAt is! String) {
      throw const FormatException('PC emparejada incompleta');
    }
    final lastSeen = map['lastSeenAt'];
    return PairedServer(
      serverId: serverId,
      name: name,
      host: host,
      port: port,
      publicKey: decodeBase64(publicKey),
      pairedAt: DateTime.parse(pairedAt),
      lastSeenAt: lastSeen is String ? DateTime.parse(lastSeen) : null,
    );
  }

  final String serverId;
  final String name;
  final String host;
  final int port;
  final List<int> publicKey;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;

  PairedServer copyWith({
    String? name,
    String? host,
    int? port,
    DateTime? lastSeenAt,
  }) {
    return PairedServer(
      serverId: serverId,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      publicKey: publicKey,
      pairedAt: pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'serverId': serverId,
        'name': name,
        'host': host,
        'port': port,
        'publicKey': encodeBase64(publicKey),
        'pairedAt': pairedAt.toUtc().toIso8601String(),
        'lastSeenAt': lastSeenAt?.toUtc().toIso8601String(),
      };

  @override
  String toString() => 'PairedServer($name, $host:$port)';
}

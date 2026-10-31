import '../protocol/device_info.dart';

/// Sesión activa de un cliente conectado al servidor de la PC.
final class ClientSession {
  const ClientSession({
    required this.id,
    required this.connectedAt,
    required this.lastSeen,
    this.device,
    this.remoteAddress = '',
  });

  final String id;
  final DateTime connectedAt;
  final DateTime lastSeen;
  final DeviceInfo? device;
  final String remoteAddress;

  String get displayName =>
      device?.name ??
      'Dispositivo ${id.substring(0, id.length < 4 ? id.length : 4)}';

  ClientSession copyWith({
    DeviceInfo? device,
    DateTime? lastSeen,
    String? remoteAddress,
  }) {
    return ClientSession(
      id: id,
      connectedAt: connectedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      device: device ?? this.device,
      remoteAddress: remoteAddress ?? this.remoteAddress,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'device': device?.toJson(),
        'connectedAt': connectedAt.toUtc().toIso8601String(),
        'lastSeen': lastSeen.toUtc().toIso8601String(),
        'remoteAddress': remoteAddress,
      };

  @override
  String toString() => 'ClientSession($id, $displayName)';
}

import '../protocol/device_info.dart';

/// Estado de autenticación de una conexión WebSocket.
enum ClientSessionState {
  /// Conectado, pero todavía no demostró ser un dispositivo emparejado.
  unauthenticated,

  /// En medio del intercambio de emparejamiento.
  pairing,

  /// Autenticado; todos sus mensajes deben ir cifrados.
  authenticated,
}

/// Sesión activa de un cliente conectado al servidor de la PC.
final class ClientSession {
  const ClientSession({
    required this.id,
    required this.connectedAt,
    required this.lastSeen,
    this.device,
    this.remoteAddress = '',
    this.state = ClientSessionState.unauthenticated,
    this.pairedDeviceId,
  });

  final String id;
  final DateTime connectedAt;
  final DateTime lastSeen;
  final DeviceInfo? device;
  final String remoteAddress;
  final ClientSessionState state;
  final String? pairedDeviceId;

  bool get isAuthenticated => state == ClientSessionState.authenticated;

  String get displayName =>
      device?.name ??
      'Dispositivo ${id.substring(0, id.length < 4 ? id.length : 4)}';

  ClientSession copyWith({
    DeviceInfo? device,
    DateTime? lastSeen,
    String? remoteAddress,
    ClientSessionState? state,
    String? pairedDeviceId,
  }) {
    return ClientSession(
      id: id,
      connectedAt: connectedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      device: device ?? this.device,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      state: state ?? this.state,
      pairedDeviceId: pairedDeviceId ?? this.pairedDeviceId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'device': device?.toJson(),
        'connectedAt': connectedAt.toUtc().toIso8601String(),
        'lastSeen': lastSeen.toUtc().toIso8601String(),
        'remoteAddress': remoteAddress,
        'state': state.name,
        'pairedDeviceId': pairedDeviceId,
      };

  @override
  String toString() => 'ClientSession($id, $displayName, ${state.name})';
}

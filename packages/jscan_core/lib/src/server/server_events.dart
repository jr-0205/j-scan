import '../pairing/paired_device.dart';
import 'client_session.dart';

/// Eventos emitidos por [LocalServer] para que la UI reaccione sin polling.
sealed class ServerEvent {
  const ServerEvent();
}

final class ServerClientConnected extends ServerEvent {
  const ServerClientConnected(this.session);

  final ClientSession session;
}

final class ServerClientUpdated extends ServerEvent {
  const ServerClientUpdated(this.session);

  final ClientSession session;
}

final class ServerClientDisconnected extends ServerEvent {
  const ServerClientDisconnected(this.sessionId);

  final String sessionId;
}

/// Un celular completó `hello` + `challenge` + `auth`.
final class ServerClientAuthenticated extends ServerEvent {
  const ServerClientAuthenticated(this.session);

  final ClientSession session;
}

final class ServerPingReceived extends ServerEvent {
  const ServerPingReceived({required this.session, required this.nonce});

  final ClientSession session;
  final String nonce;
}

/// La ventana de emparejamiento se abrió o cerró.
final class ServerPairingWindowChanged extends ServerEvent {
  const ServerPairingWindowChanged({
    required this.open,
    this.expiresAt,
  });

  final bool open;
  final DateTime? expiresAt;
}

/// Un dispositivo nuevo fue aceptado y guardado.
final class ServerDevicePaired extends ServerEvent {
  const ServerDevicePaired(this.device);

  final PairedDevice device;
}

/// Un dispositivo fue eliminado de la lista de autorizados.
final class ServerDeviceRemoved extends ServerEvent {
  const ServerDeviceRemoved(this.deviceId);

  final String deviceId;
}

/// Un intento de emparejamiento falló (token inválido, rechazo, etc.).
final class ServerPairingFailed extends ServerEvent {
  const ServerPairingFailed({required this.code, required this.message});

  final String code;
  final String message;
}

final class ServerErrorEvent extends ServerEvent {
  const ServerErrorEvent({required this.code, required this.message});

  final String code;
  final String message;
}

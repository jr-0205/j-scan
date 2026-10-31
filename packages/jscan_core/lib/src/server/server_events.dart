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

final class ServerPingReceived extends ServerEvent {
  const ServerPingReceived({required this.session, required this.nonce});

  final ClientSession session;
  final String nonce;
}

final class ServerErrorEvent extends ServerEvent {
  const ServerErrorEvent({required this.code, required this.message});

  final String code;
  final String message;
}

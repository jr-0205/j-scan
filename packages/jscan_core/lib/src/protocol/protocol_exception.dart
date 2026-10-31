/// Error de protocolo con un código estable para la UI y los tests.
final class ProtocolException implements Exception {
  const ProtocolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ProtocolException($code): $message';

  Map<String, Object?> toPayload() => {'code': code, 'message': message};
}

/// Códigos de error definidos en `docs/protocol.md`.
abstract final class ProtocolErrorCode {
  static const String invalidMessage = 'invalid_message';
  static const String unsupportedVersion = 'unsupported_version';
  static const String unsupportedType = 'unsupported_type';
  static const String invalidPayload = 'invalid_payload';
  static const String internalError = 'internal_error';
}

/// Fallo al abrir o mantener la conexión WebSocket.
final class JScanConnectionException implements Exception {
  const JScanConnectionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'JScanConnectionException: $message${cause == null ? '' : ' ($cause)'}';
}

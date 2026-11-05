/// Valores compartidos por el protocolo y el descubrimiento.
abstract final class JScanDefaults {
  /// Puerto fijo del servidor de la PC.
  static const int port = 47821;

  /// Tipo de servicio DNS-SD anunciado por la PC.
  static const String serviceType = '_jscan._tcp.local';

  /// Etiqueta del servicio sin el dominio.
  static const String serviceLabel = '_jscan._tcp';

  /// Dominio mDNS.
  static const String domain = 'local';

  /// Ruta del WebSocket dentro del servidor HTTP.
  static const String wsPath = '/ws';

  /// Versión del protocolo descrita en `docs/protocol.md`.
  static const int protocolVersion = 1;

  /// Nombre comercial usado en la UI y los TXT de mDNS.
  static const String appName = 'J-SCAN';

  /// Prefijo del host mDNS publicado por la PC.
  static const String hostPrefix = 'jscan';

  /// Tamaño máximo de un frame de texto aceptado (1 MiB).
  static const int maxFrameBytes = 1024 * 1024;

  /// Tamaño máximo del contenido útil de `text`/`clipboard` (64 KiB).
  static const int maxTextBytes = 64 * 1024;

  /// Versión del contenido del QR de emparejamiento.
  static const int pairingCodeVersion = 1;

  /// Duración por defecto de la ventana para escanear el QR.
  static const Duration pairingWindow = Duration(minutes: 3);

  /// Tiempo máximo que la PC espera la confirmación del usuario.
  static const Duration pairingConfirmationTimeout = Duration(minutes: 1);
}

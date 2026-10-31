import 'dart:convert';

import '../protocol/constants.dart';
import '../protocol/device_info.dart';
import '../protocol/protocol_exception.dart';
import 'bytes.dart';

/// Datos que viajan en el QR de emparejamiento de la PC.
///
/// Formato: `jscan://pair?d=<base64url(JSON)>`. El JSON incluye la IP, el
/// puerto, la clave pública X25519 del servidor y un token de un solo uso.
final class PairingCode {
  const PairingCode({
    required this.serverId,
    required this.serverName,
    required this.host,
    required this.port,
    required this.serverPublicKey,
    required this.token,
    required this.expiresAt,
    this.version = JScanDefaults.pairingCodeVersion,
  });

  factory PairingCode.fromServer({
    required DeviceInfo server,
    required String host,
    required int port,
    required List<int> serverPublicKey,
    required List<int> token,
    required DateTime expiresAt,
  }) {
    return PairingCode(
      serverId: server.id,
      serverName: server.name,
      host: host,
      port: port,
      serverPublicKey: serverPublicKey,
      token: token,
      expiresAt: expiresAt,
    );
  }

  static const String scheme = 'jscan';
  static const String pairHost = 'pair';

  final int version;
  final String serverId;
  final String serverName;
  final String host;
  final int port;
  final List<int> serverPublicKey;
  final List<int> token;
  final DateTime expiresAt;

  bool isExpired([DateTime? now]) =>
      !(now ?? DateTime.now()).isBefore(expiresAt);

  /// Texto que se dibuja como QR.
  String encode() {
    final payload = <String, Object?>{
      'v': version,
      'sid': serverId,
      'name': serverName,
      'host': host,
      'port': port,
      'spk': encodeBase64(serverPublicKey),
      'tok': encodeBase64(token),
      'exp': expiresAt.toUtc().millisecondsSinceEpoch,
    };
    final encoded = encodeBase64(utf8.encode(jsonEncode(payload)));
    return 'jscan://pair?d=$encoded';
  }

  /// Acepta el texto completo del QR o solo la parte codificada.
  factory PairingCode.decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El código de emparejamiento está vacío',
      );
    }

    String payload;
    if (trimmed.startsWith('jscan://')) {
      final uri = Uri.tryParse(trimmed);
      final value = uri?.queryParameters['d'];
      if (uri == null ||
          uri.host != pairHost ||
          value == null ||
          value.isEmpty) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidPayload,
          'El enlace no es un código J-SCAN válido',
        );
      }
      payload = value;
    } else {
      payload = trimmed;
    }

    final Map<String, Object?> map;
    try {
      final decoded = jsonDecode(utf8.decode(decodeBase64(payload)));
      if (decoded is! Map) {
        throw const FormatException('El contenido no es un objeto');
      }
      map = Map<String, Object?>.from(decoded);
    } catch (error) {
      throw ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'No se pudo leer el código de emparejamiento: $error',
      );
    }

    final version = map['v'];
    if (version != JScanDefaults.pairingCodeVersion) {
      throw ProtocolException(
        ProtocolErrorCode.unsupportedVersion,
        'Código de emparejamiento de versión no soportada: $version',
      );
    }

    final serverId = map['sid'];
    final serverName = map['name'];
    final host = map['host'];
    final port = map['port'];
    final spk = map['spk'];
    final token = map['tok'];
    final expiresAt = map['exp'];

    if (serverId is! String ||
        serverId.isEmpty ||
        serverName is! String ||
        serverName.isEmpty ||
        host is! String ||
        host.isEmpty ||
        port is! int ||
        port <= 0 ||
        port > 65535 ||
        spk is! String ||
        token is! String ||
        expiresAt is! int) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El código de emparejamiento está incompleto',
      );
    }

    final publicKey = decodeBase64(spk);
    final pairingToken = decodeBase64(token);
    if (publicKey.length != 32) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'La clave pública del servidor no es válida',
      );
    }
    if (pairingToken.length < 16) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El token de emparejamiento es demasiado corto',
      );
    }

    return PairingCode(
      version: version as int,
      serverId: serverId,
      serverName: serverName,
      host: host,
      port: port,
      serverPublicKey: publicKey,
      token: pairingToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
    );
  }

  PairingCode copyWith({
    String? serverId,
    String? serverName,
    String? host,
    int? port,
    List<int>? serverPublicKey,
    List<int>? token,
    DateTime? expiresAt,
  }) {
    return PairingCode(
      version: version,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      host: host ?? this.host,
      port: port ?? this.port,
      serverPublicKey: serverPublicKey ?? this.serverPublicKey,
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  String toString() => 'PairingCode($serverId, $host:$port, expira $expiresAt)';
}

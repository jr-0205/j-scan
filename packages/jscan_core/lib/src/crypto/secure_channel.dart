import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../protocol/messages.dart';
import '../protocol/protocol_exception.dart';
import 'bytes.dart';

/// Derivación de claves y cifrado autenticado del protocolo J-SCAN.
///
/// - X25519 para el secreto compartido.
/// - HKDF-SHA256 para separar las claves de emparejamiento, autenticación y
///   sesión.
/// - ChaCha20-Poly1305 para cifrar cada mensaje.
abstract final class SecureChannel {
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final Chacha20 _cipher = Chacha20.poly1305Aead();
  static final Hmac _hmac = Hmac.sha256();

  /// Texto asociado a todos los sobres cifrados (`encrypted`).
  static const String envelopeAad = 'jscan-encrypted-v1';

  static Future<List<int>> _derive({
    required List<int> secret,
    required List<int> salt,
    required String info,
  }) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: utf8.encode(info),
    );
    return key.bytes;
  }

  /// Clave usada durante el emparejamiento inicial (token + prueba).
  static Future<List<int>> derivePairingKey(
    List<int> sharedSecret,
    String serverId,
  ) {
    return _derive(
      secret: sharedSecret,
      salt: utf8.encode(serverId),
      info: 'jscan-pair-v1',
    );
  }

  /// Clave usada para demostrar posesión de la identidad emparejada.
  static Future<List<int>> deriveAuthKey(
    List<int> sharedSecret,
    String serverId,
  ) {
    return _derive(
      secret: sharedSecret,
      salt: utf8.encode(serverId),
      info: 'jscan-auth-v1',
    );
  }

  /// Clave de sesión, distinta en cada conexión gracias al nonce del servidor.
  static Future<List<int>> deriveSessionKey({
    required List<int> sharedSecret,
    required String serverId,
    required String deviceId,
    required List<int> serverNonce,
  }) {
    return _derive(
      secret: sharedSecret,
      salt: serverNonce,
      info: 'jscan-session-v1|$serverId|$deviceId',
    );
  }

  /// Cifra [plaintext] y devuelve `nonce` y `box` en base64.
  static Future<Map<String, String>> seal({
    required List<int> key,
    required List<int> plaintext,
    required List<int> aad,
  }) async {
    final nonce = secureRandomBytes(12);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return <String, String>{
      'nonce': encodeBase64(box.nonce),
      'box': encodeBase64(<int>[...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Descifra y verifica el MAC de un sobre `nonce`/`box`.
  static Future<List<int>> open({
    required List<int> key,
    required String nonce,
    required String box,
    required List<int> aad,
  }) async {
    final nonceBytes = decodeBase64(nonce);
    final boxBytes = decodeBase64(box);
    if (nonceBytes.length != 12) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'Nonce de cifrado inválido',
      );
    }
    if (boxBytes.length < 16) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'Mensaje cifrado demasiado corto',
      );
    }

    try {
      return await _cipher.decrypt(
        SecretBox(
          boxBytes.sublist(0, boxBytes.length - 16),
          nonce: nonceBytes,
          mac: Mac(boxBytes.sublist(boxBytes.length - 16)),
        ),
        secretKey: SecretKey(key),
        aad: aad,
      );
    } catch (error) {
      throw ProtocolException(
        ProtocolErrorCode.unauthorized,
        'No se pudo descifrar el mensaje: $error',
      );
    }
  }

  static Future<String> hmacBase64({
    required List<int> key,
    required String message,
  }) async {
    final mac = await _hmac.calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(key),
    );
    return encodeBase64(mac.bytes);
  }

  static Future<bool> verifyHmac({
    required List<int> key,
    required String message,
    required String expected,
  }) async {
    try {
      final actual = await hmacBase64(key: key, message: message);
      return constantTimeEquals(decodeBase64(actual), decodeBase64(expected));
    } catch (_) {
      return false;
    }
  }
}

/// Cifra y descifra los sobres de una sesión ya autenticada.
final class SessionCipher {
  SessionCipher._(this._key);

  static Future<SessionCipher> derive({
    required List<int> sharedSecret,
    required String serverId,
    required String deviceId,
    required List<int> serverNonce,
  }) async {
    final key = await SecureChannel.deriveSessionKey(
      sharedSecret: sharedSecret,
      serverId: serverId,
      deviceId: deviceId,
      serverNonce: serverNonce,
    );
    return SessionCipher._(key);
  }

  final List<int> _key;

  Future<Envelope> sealEnvelope(Envelope inner) async {
    final sealed = await SecureChannel.seal(
      key: _key,
      plaintext: utf8.encode(inner.encode()),
      aad: utf8.encode(SecureChannel.envelopeAad),
    );
    return Envelope.create(
      MessageType.encrypted,
      id: inner.id,
      payload: sealed,
    );
  }

  Future<Envelope> openEnvelope(Envelope outer) async {
    final nonce = outer.stringField('nonce');
    final box = outer.stringField('box');
    if (nonce == null || box == null) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El sobre cifrado debe incluir nonce y box',
      );
    }
    final plaintext = await SecureChannel.open(
      key: _key,
      nonce: nonce,
      box: box,
      aad: utf8.encode(SecureChannel.envelopeAad),
    );
    try {
      return Envelope.decode(utf8.decode(plaintext));
    } on ProtocolException {
      rethrow;
    } catch (error) {
      throw ProtocolException(
        ProtocolErrorCode.invalidMessage,
        'El mensaje descifrado no es válido: $error',
      );
    }
  }
}

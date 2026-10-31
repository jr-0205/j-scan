import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/bytes.dart';
import '../crypto/identity.dart';
import '../crypto/pairing_code.dart';
import '../crypto/secure_channel.dart';
import '../pairing/paired_device.dart';
import '../protocol/constants.dart';
import '../protocol/device_info.dart';
import '../protocol/messages.dart';
import '../protocol/protocol_exception.dart';

final class _PendingRequest {
  _PendingRequest(this.expected, this.completer);

  final MessageType expected;
  final Completer<Envelope> completer;
}

/// Resultado de emparejar un celular con una PC.
final class PairingResult {
  const PairingResult({required this.server, required this.serverInfo});

  final PairedServer server;
  final DeviceInfo serverInfo;
}

/// Cliente del protocolo J-SCAN (usado por el celular y por herramientas CLI).
///
/// Sprint 2: emparejamiento por QR + autenticación X25519 + mensajes cifrados.
final class JScanClient {
  JScanClient._(this._channel, this.timeout) {
    _subscription = _channel.stream.listen(
      _handleData,
      onDone: _handleDone,
      onError: _handleStreamError,
    );
  }

  /// Empareja el dispositivo con la PC descrita por [code].
  ///
  /// No mantiene la conexión abierta: la PC cierra la sesión tras aceptar y el
  /// cliente debe volver a entrar con [connectPaired].
  static Future<PairingResult> pair({
    required PairingCode code,
    required LocalIdentity identity,
    required DeviceInfo device,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri(
      scheme: 'ws',
      host: code.host,
      port: code.port,
      path: JScanDefaults.wsPath,
    );
    final client = await _open(uri, timeout);
    try {
      final challenge = await client._request(
        MessageType.pairHello,
        <String, Object?>{
          'device': device.toJson(),
          'publicKey': encodeBase64(identity.publicKey),
        },
        expected: MessageType.pairChallenge,
      );

      final challengeNonce = challenge.stringField('nonce');
      if (challengeNonce == null || challengeNonce.isEmpty) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidPayload,
          'La PC no envió el desafío de emparejamiento',
        );
      }

      final shared = await identity.sharedSecret(code.serverPublicKey);
      final pairingKey = await SecureChannel.derivePairingKey(
        shared,
        code.serverId,
      );
      final aad = utf8.encode(
        'jscan-pair-v1|${code.serverId}|$challengeNonce',
      );
      final sealed = await SecureChannel.seal(
        key: pairingKey,
        plaintext: utf8.encode(
          jsonEncode(<String, Object?>{
            'token': encodeBase64(code.token),
          }),
        ),
        aad: aad,
      );

      final accepted = await client._request(
        MessageType.pairRequest,
        <String, Object?>{
          'challenge': challengeNonce,
          'nonce': sealed['nonce'],
          'box': sealed['box'],
        },
        expected: MessageType.pairAccept,
      );

      final proof = accepted.stringField('proof');
      if (proof == null) {
        throw const ProtocolException(
          ProtocolErrorCode.badProof,
          'La PC no envió la prueba de emparejamiento',
        );
      }
      final expectedProof = await SecureChannel.hmacBase64(
        key: pairingKey,
        message: 'accept|${code.serverId}|${device.id}|$challengeNonce',
      );
      if (!constantTimeEquals(
        decodeBase64(proof),
        decodeBase64(expectedProof),
      )) {
        throw const ProtocolException(
          ProtocolErrorCode.badProof,
          'La prueba de emparejamiento de la PC no es válida',
        );
      }

      final serverJson = accepted.mapField('server');
      final serverInfo = serverJson == null
          ? DeviceInfo(
              id: code.serverId,
              name: code.serverName,
              platform: 'windows',
              appVersion: '0.1.0',
            )
          : DeviceInfo.fromJson(serverJson);

      final now = DateTime.now();
      final server = PairedServer(
        serverId: code.serverId,
        name: serverInfo.name,
        host: code.host,
        port: code.port,
        publicKey: code.serverPublicKey,
        pairedAt: now,
        lastSeenAt: now,
      );

      return PairingResult(server: server, serverInfo: serverInfo);
    } finally {
      await client.close();
    }
  }

  /// Conecta con una PC ya emparejada y completa `hello`/`challenge`/`auth`.
  static Future<JScanClient> connectPaired({
    required PairedServer server,
    required LocalIdentity identity,
    required DeviceInfo device,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final uri = Uri(
      scheme: 'ws',
      host: server.host,
      port: server.port,
      path: JScanDefaults.wsPath,
    );
    final client = await _open(uri, timeout);
    try {
      final challenge = await client._request(
        MessageType.hello,
        <String, Object?>{
          'device': device.toJson(),
          'publicKey': encodeBase64(identity.publicKey),
        },
        expected: MessageType.challenge,
      );

      final serverNonceText = challenge.stringField('nonce');
      if (serverNonceText == null || serverNonceText.isEmpty) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidPayload,
          'La PC no envió el desafío de autenticación',
        );
      }
      final serverNonce = decodeBase64(serverNonceText);
      final shared = await identity.sharedSecret(server.publicKey);
      final authKey = await SecureChannel.deriveAuthKey(
        shared,
        server.serverId,
      );
      final proof = await SecureChannel.hmacBase64(
        key: authKey,
        message: 'auth|${server.serverId}|${device.id}|$serverNonceText',
      );

      // La respuesta `auth_ok` viene cifrada con la clave de sesión, así que
      // debe estar lista antes de enviar `auth`.
      client._cipher = await SessionCipher.derive(
        sharedSecret: shared,
        serverId: server.serverId,
        deviceId: device.id,
        serverNonce: serverNonce,
      );

      final ack = await client._request(
        MessageType.auth,
        <String, Object?>{'proof': proof},
        expected: MessageType.authOk,
        secure: false,
      );

      final serverJson = ack.mapField('server');
      if (serverJson != null) {
        client.serverInfo = DeviceInfo.fromJson(serverJson);
      }
      client.protocolVersion =
          ack.intField('protocolVersion') ?? JScanDefaults.protocolVersion;
      client.wsPath = ack.stringField('wsPath') ?? JScanDefaults.wsPath;
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  static Future<JScanClient> _open(Uri uri, Duration timeout) async {
    final IOWebSocketChannel channel;
    try {
      channel = IOWebSocketChannel.connect(uri, connectTimeout: timeout);
      await channel.ready.timeout(timeout);
    } catch (error) {
      throw JScanConnectionException(
        'No se pudo conectar con $uri',
        cause: error,
      );
    }
    return JScanClient._(channel, timeout);
  }

  final WebSocketChannel _channel;
  final Duration timeout;
  final Map<String, _PendingRequest> _pending = <String, _PendingRequest>{};
  final StreamController<Envelope> _incoming =
      StreamController<Envelope>.broadcast();

  late final StreamSubscription<dynamic> _subscription;
  Future<void> _queue = Future<void>.value();
  SessionCipher? _cipher;
  bool _closed = false;

  DeviceInfo? serverInfo;
  int protocolVersion = JScanDefaults.protocolVersion;
  String wsPath = JScanDefaults.wsPath;

  /// `true` cuando la sesión ya está autenticada y cifrada.
  bool get isEncrypted => _cipher != null;

  /// Mensajes que no corresponden a una petición en curso (futuros push).
  Stream<Envelope> get messages => _incoming.stream;

  bool get isOpen => !_closed;

  /// Envía un `ping` cifrado y devuelve el RTT medido en el cliente.
  Future<Duration> ping() async {
    if (_cipher == null) {
      throw const JScanConnectionException(
        'La sesión no está autenticada; empareja el dispositivo primero',
      );
    }
    final stopwatch = Stopwatch()..start();
    await _request(
      MessageType.ping,
      <String, Object?>{'nonce': newNonce()},
      expected: MessageType.pong,
    );
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  /// Envía un mensaje cifrado sin esperar respuesta (para tipos futuros).
  String send(
    MessageType type, {
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    if (_cipher == null) {
      throw const JScanConnectionException(
        'La sesión no está autenticada; empareja el dispositivo primero',
      );
    }
    final envelope = Envelope.create(type, payload: payload);
    unawaited(_sendEnvelope(envelope));
    return envelope.id;
  }

  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      await _subscription.cancel();
      _failPending(
        const JScanConnectionException('La conexión se cerró'),
      );
      await _incoming.close();
    }
    try {
      await _channel.sink.close(WebSocketStatus.normalClosure);
    } catch (_) {
      // Ya estaba cerrado.
    }
  }

  Future<Envelope> _request(
    MessageType type,
    Map<String, Object?> payload, {
    required MessageType expected,
    bool secure = true,
  }) async {
    if (_closed) {
      throw const JScanConnectionException('La conexión está cerrada');
    }

    final envelope = Envelope.create(type, payload: payload);
    final completer = Completer<Envelope>();
    _pending[envelope.id] = _PendingRequest(expected, completer);

    try {
      await _sendEnvelope(envelope, secure: secure);
    } catch (error) {
      _pending.remove(envelope.id);
      rethrow;
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(envelope.id);
        throw JScanConnectionException(
          'Tiempo de espera agotado esperando ${expected.wire}',
        );
      },
    );
  }

  Future<void> _sendEnvelope(
    Envelope envelope, {
    bool secure = true,
  }) async {
    if (_closed) {
      throw const JScanConnectionException('La conexión está cerrada');
    }
    if (secure) {
      final cipher = _cipher;
      if (cipher != null) {
        final sealed = await cipher.sealEnvelope(envelope);
        _channel.sink.add(sealed.encode());
        return;
      }
    }
    _channel.sink.add(envelope.encode());
  }

  void _handleData(Object? data) {
    if (_closed) return;
    _queue = _queue.then((_) => _processFrame(data)).catchError(
      (Object error, StackTrace stackTrace) {
        _failPending(
          JScanConnectionException(
            'Error al procesar una respuesta',
            cause: error,
          ),
        );
      },
    );
  }

  Future<void> _processFrame(Object? data) async {
    if (_closed) return;

    Envelope envelope;
    try {
      envelope = Envelope.decode(data);
    } on ProtocolException {
      return;
    } catch (_) {
      return;
    }

    if (envelope.type == MessageType.encrypted.wire) {
      final cipher = _cipher;
      if (cipher == null) return;
      try {
        envelope = await cipher.openEnvelope(envelope);
      } catch (error) {
        _failPending(
          JScanConnectionException(
            'No se pudo descifrar la respuesta de la PC',
            cause: error,
          ),
        );
        return;
      }
    }

    final pending = _pending.remove(envelope.id);
    if (pending != null) {
      if (envelope.type == MessageType.error.wire ||
          envelope.type == MessageType.pairReject.wire) {
        pending.completer.completeError(
          ProtocolException(
            envelope.stringField('code') ?? ProtocolErrorCode.internalError,
            envelope.stringField('message') ?? 'Error del servidor',
          ),
        );
      } else if (envelope.type == pending.expected.wire) {
        pending.completer.complete(envelope);
      } else {
        pending.completer.completeError(
          ProtocolException(
            ProtocolErrorCode.invalidMessage,
            'Se esperaba ${pending.expected.wire} y llegó ${envelope.type}',
          ),
        );
      }
      return;
    }

    if (!_incoming.isClosed) {
      _incoming.add(envelope);
    }
  }

  void _handleDone() {
    if (_closed) return;
    _closed = true;
    _failPending(
      const JScanConnectionException('El servidor cerró la conexión'),
    );
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _closed = true;
    _failPending(
      JScanConnectionException('Error de WebSocket', cause: error),
    );
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }

  void _failPending(JScanConnectionException error) {
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _pending.clear();
  }
}

int _nonceCounter = 0;

String newNonce() {
  _nonceCounter += 1;
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '-${_nonceCounter.toRadixString(16)}';
}

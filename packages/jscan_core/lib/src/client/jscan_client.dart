import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/constants.dart';
import '../protocol/device_info.dart';
import '../protocol/messages.dart';
import '../protocol/protocol_exception.dart';

final class _PendingRequest {
  _PendingRequest(this.expected, this.completer);

  final MessageType expected;
  final Completer<Envelope> completer;
}

/// Cliente del protocolo J-SCAN (usado por el celular y por herramientas CLI).
///
/// Abre el WebSocket, hace el `hello` y permite medir el RTT con [ping].
final class JScanClient {
  JScanClient._(this._channel, this.timeout) {
    _subscription = _channel.stream.listen(
      _handleData,
      onDone: _handleDone,
      onError: _handleStreamError,
    );
  }

  /// Conecta con una PC y completa el handshake `hello`/`hello_ack`.
  static Future<JScanClient> connect({
    required String host,
    int port = JScanDefaults.port,
    Duration timeout = const Duration(seconds: 5),
    DeviceInfo? device,
    String appVersion = '0.1.0',
  }) async {
    final uri = Uri(
      scheme: 'ws',
      host: host,
      port: port,
      path: JScanDefaults.wsPath,
    );

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

    final client = JScanClient._(channel, timeout);
    try {
      final deviceInfo = device ??
          DeviceInfo.current(
            id: 'cli-${DateTime.now().millisecondsSinceEpoch}',
            appVersion: appVersion,
          );

      final ack = await client._request(
        MessageType.hello,
        <String, Object?>{'device': deviceInfo.toJson()},
        expected: MessageType.helloAck,
      );

      final server = ack.mapField('server');
      client.serverInfo = server == null ? null : DeviceInfo.fromJson(server);
      client.protocolVersion =
          ack.intField('protocolVersion') ?? JScanDefaults.protocolVersion;
      client.pairingRequired = ack.payload['pairingRequired'] == true;
      client.wsPath = ack.stringField('wsPath') ?? JScanDefaults.wsPath;
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  final WebSocketChannel _channel;
  final Duration timeout;
  final Map<String, _PendingRequest> _pending = <String, _PendingRequest>{};
  final StreamController<Envelope> _incoming =
      StreamController<Envelope>.broadcast();

  late final StreamSubscription<dynamic> _subscription;
  bool _closed = false;

  DeviceInfo? serverInfo;
  int protocolVersion = JScanDefaults.protocolVersion;
  bool pairingRequired = false;
  String wsPath = JScanDefaults.wsPath;

  /// Mensajes que no corresponden a una petición en curso (futuros push).
  Stream<Envelope> get messages => _incoming.stream;

  bool get isOpen => !_closed;

  /// Envía un `ping` y devuelve el RTT medido en el cliente.
  Future<Duration> ping() async {
    final stopwatch = Stopwatch()..start();
    await _request(
      MessageType.ping,
      <String, Object?>{'nonce': newNonce()},
      expected: MessageType.pong,
    );
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  /// Envía un mensaje sin esperar respuesta (para tipos futuros).
  String send(
    MessageType type, {
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    final envelope = Envelope.create(type, payload: payload);
    _sendEnvelope(envelope);
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
  }) {
    if (_closed) {
      throw const JScanConnectionException('La conexión está cerrada');
    }

    final envelope = Envelope.create(type, payload: payload);
    final completer = Completer<Envelope>();
    _pending[envelope.id] = _PendingRequest(expected, completer);

    try {
      _sendEnvelope(envelope);
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

  void _sendEnvelope(Envelope envelope) {
    if (_closed) {
      throw const JScanConnectionException('La conexión está cerrada');
    }
    _channel.sink.add(envelope.encode());
  }

  void _handleData(Object? data) {
    if (_closed) return;

    final Envelope envelope;
    try {
      envelope = Envelope.decode(data);
    } on ProtocolException {
      return;
    } catch (_) {
      return;
    }

    final pending = _pending.remove(envelope.id);
    if (pending != null) {
      if (envelope.type == MessageType.error.wire) {
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

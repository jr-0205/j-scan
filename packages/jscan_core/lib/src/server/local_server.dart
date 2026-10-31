import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../network/network_info.dart';
import '../protocol/constants.dart';
import '../protocol/device_info.dart';
import '../protocol/messages.dart';
import '../protocol/protocol_exception.dart';
import '../util/ids.dart';
import 'client_session.dart';
import 'server_events.dart';

/// Error al iniciar el servidor local (por ejemplo, puerto ocupado).
final class LocalServerException implements Exception {
  const LocalServerException(this.message, {required this.port, this.cause});

  final String message;
  final int port;
  final Object? cause;

  @override
  String toString() =>
      'LocalServerException($port): $message${cause == null ? '' : ' ($cause)'}';
}

/// Servidor HTTP/WebSocket de la PC.
///
/// Sprint 1: `GET /health`, `GET /api/info`, `WS /ws` con `hello` y `ping`.
final class LocalServer {
  LocalServer._({
    required this.id,
    required this.name,
    required this.appVersion,
  }) : startedAt = DateTime.now();

  static Future<LocalServer> start({
    int port = JScanDefaults.port,
    String? id,
    String? name,
    String appVersion = '0.1.0',
    bool includeLoopback = false,
  }) async {
    final server = LocalServer._(
      id: id ?? newId(8),
      name: name ?? Platform.localHostname,
      appVersion: appVersion,
    );
    server._includeLoopback = includeLoopback;

    final wsHandler = webSocketHandler(server._onWebSocket);
    try {
      server._httpServer = await shelf_io.serve(
        server._buildHandler(wsHandler),
        InternetAddress.anyIPv4,
        port,
      );
    } on SocketException catch (error) {
      throw LocalServerException(
        'No se pudo abrir el puerto $port. '
        '¿Otra instancia de J-SCAN está en ejecución?',
        port: port,
        cause: error,
      );
    }
    server._httpServer.autoCompress = true;
    return server;
  }

  final String id;
  final String name;
  final String appVersion;
  final DateTime startedAt;

  late final HttpServer _httpServer;
  late bool _includeLoopback;

  final Map<String, ClientSession> _sessions = <String, ClientSession>{};
  final Map<String, WebSocketChannel> _channels = <String, WebSocketChannel>{};
  final Map<String, StreamSubscription<dynamic>> _subscriptions =
      <String, StreamSubscription<dynamic>>{};
  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();

  bool _stopping = false;

  int get port => _httpServer.port;
  bool get isRunning => !_stopping;

  /// Eventos de conexión, handshake y ping.
  Stream<ServerEvent> get events => _events.stream;

  List<ClientSession> get sessions {
    final list = _sessions.values.toList()
      ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
    return List<ClientSession>.unmodifiable(list);
  }

  Uri httpUri(String host) =>
      Uri(scheme: 'http', host: host, port: port, path: '/health');

  Uri wsUri(String host) =>
      Uri(scheme: 'ws', host: host, port: port, path: JScanDefaults.wsPath);

  Future<Map<String, Object?>> health() async {
    final addresses = await localIPv4Addresses(
      includeLoopback: _includeLoopback,
    );
    return <String, Object?>{
      'status': 'ok',
      'id': id,
      'name': name,
      'platform': currentPlatform(),
      'appVersion': appVersion,
      'protocolVersion': JScanDefaults.protocolVersion,
      'wsPath': JScanDefaults.wsPath,
      'time': DateTime.now().toUtc().toIso8601String(),
      'addresses': addresses,
      'uptimeSeconds': DateTime.now().difference(startedAt).inSeconds,
      'sessions': _sessions.length,
    };
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;

    for (final channel in _channels.values.toList()) {
      try {
        await channel.sink.close(WebSocketStatus.normalClosure);
      } catch (_) {
        // La conexión pudo cerrarse antes.
      }
    }
    _channels.clear();

    for (final subscription in _subscriptions.values.toList()) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _sessions.clear();

    await _httpServer.close(force: true);
    await _events.close();
  }

  Handler _buildHandler(Handler wsHandler) {
    return (Request request) async {
      switch (request.url.path) {
        case 'health':
        case 'api/info':
          return _jsonResponse(await health());
        case 'ws':
          return await wsHandler(request);
        default:
          return _jsonResponse(
            <String, Object?>{
              'error': <String, Object?>{
                'code': 'not_found',
                'message': 'Ruta no encontrada: /${request.url.path}',
              },
            },
            status: 404,
          );
      }
    };
  }

  Response _jsonResponse(Map<String, Object?> body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
  }

  void _onWebSocket(WebSocketChannel channel, String? protocol) {
    if (_stopping) {
      unawaited(channel.sink.close());
      return;
    }

    final now = DateTime.now();
    final session = ClientSession(
      id: newId(6),
      connectedAt: now,
      lastSeen: now,
    );
    _sessions[session.id] = session;
    _channels[session.id] = channel;
    _emit(ServerClientConnected(session));

    _subscriptions[session.id] = channel.stream.listen(
      (data) => _onData(session.id, data),
      onDone: () => _removeSession(session.id),
      onError: (Object error, StackTrace stackTrace) {
        _emit(
          ServerErrorEvent(
            code: ProtocolErrorCode.internalError,
            message: 'Error de WebSocket: $error',
          ),
        );
        _removeSession(session.id);
      },
    );
  }

  void _onData(String sessionId, Object? data) {
    final channel = _channels[sessionId];
    if (channel == null) return;

    final Envelope envelope;
    try {
      envelope = Envelope.decode(data);
    } on ProtocolException catch (error) {
      _send(channel,
          Envelope.create(MessageType.error, payload: error.toPayload()));
      if (error.code == ProtocolErrorCode.unsupportedVersion) {
        unawaited(_closeSession(sessionId));
      }
      return;
    } catch (error) {
      _sendError(
        channel,
        null,
        ProtocolErrorCode.invalidMessage,
        'Mensaje inválido: $error',
      );
      return;
    }

    final type = envelope.knownType;
    if (type == null) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.unsupportedType,
        'Tipo no soportado: ${envelope.type}',
      );
      return;
    }

    switch (type) {
      case MessageType.hello:
        _handleHello(sessionId, channel, envelope);
        break;
      case MessageType.ping:
        _handlePing(sessionId, channel, envelope);
        break;
      case MessageType.helloAck:
      case MessageType.pong:
      case MessageType.error:
        _sendError(
          channel,
          envelope.id,
          ProtocolErrorCode.unsupportedType,
          'El servidor no espera ${type.wire} de un cliente',
        );
        break;
      default:
        _sendError(
          channel,
          envelope.id,
          ProtocolErrorCode.unsupportedType,
          'Tipo no implementado todavía: ${type.wire}',
        );
    }
  }

  void _handleHello(
    String sessionId,
    WebSocketChannel channel,
    Envelope envelope,
  ) {
    try {
      final device = DeviceInfo.fromJson(envelope.payload['device']);
      final current = _sessions[sessionId];
      if (current == null) return;

      final updated = current.copyWith(
        device: device,
        lastSeen: DateTime.now(),
      );
      _sessions[sessionId] = updated;
      _emit(ServerClientUpdated(updated));

      _send(
        channel,
        Envelope.create(
          MessageType.helloAck,
          id: envelope.id,
          payload: <String, Object?>{
            'server': DeviceInfo(
              id: id,
              name: name,
              platform: currentPlatform(),
              appVersion: appVersion,
            ).toJson(),
            'protocolVersion': JScanDefaults.protocolVersion,
            'wsPath': JScanDefaults.wsPath,
            'pairingRequired': false,
          },
        ),
      );
    } on ProtocolException catch (error) {
      _send(
        channel,
        Envelope.create(
          MessageType.error,
          id: envelope.id,
          payload: error.toPayload(),
        ),
      );
    }
  }

  void _handlePing(
    String sessionId,
    WebSocketChannel channel,
    Envelope envelope,
  ) {
    final current = _sessions[sessionId];
    if (current == null) return;

    final updated = current.copyWith(lastSeen: DateTime.now());
    _sessions[sessionId] = updated;

    final nonce = envelope.stringField('nonce') ?? envelope.id;
    _send(
      channel,
      Envelope.create(
        MessageType.pong,
        id: envelope.id,
        payload: <String, Object?>{
          'nonce': nonce,
          'serverTime': DateTime.now().millisecondsSinceEpoch,
        },
      ),
    );
    _emit(ServerPingReceived(session: updated, nonce: nonce));
  }

  void _send(WebSocketChannel channel, Envelope envelope) {
    try {
      channel.sink.add(envelope.encode());
    } catch (error) {
      _emit(
        ServerErrorEvent(
          code: ProtocolErrorCode.internalError,
          message: 'No se pudo enviar ${envelope.type}: $error',
        ),
      );
    }
  }

  void _sendError(
    WebSocketChannel channel,
    String? id,
    String code,
    String message,
  ) {
    _send(
      channel,
      Envelope.create(
        MessageType.error,
        id: id,
        payload: <String, Object?>{'code': code, 'message': message},
      ),
    );
  }

  Future<void> _closeSession(String sessionId) async {
    final channel = _channels[sessionId];
    if (channel == null) return;
    try {
      await channel.sink.close(WebSocketStatus.normalClosure);
    } catch (_) {
      // Ignorado: el objetivo es liberar la sesión.
    }
    _removeSession(sessionId);
  }

  void _removeSession(String sessionId) {
    final removed = _sessions.remove(sessionId);
    _channels.remove(sessionId);
    final subscription = _subscriptions.remove(sessionId);
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (removed != null) {
      _emit(ServerClientDisconnected(sessionId));
    }
  }

  void _emit(ServerEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }
}

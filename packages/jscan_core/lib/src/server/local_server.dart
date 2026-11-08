import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/bytes.dart';
import '../crypto/identity.dart';
import '../crypto/pairing_code.dart';
import '../crypto/secure_channel.dart';
import '../files/file_receiver.dart';
import '../files/file_transfer.dart';
import '../history/history_entry.dart';
import '../history/history_repository.dart';
import '../network/network_info.dart';
import '../pairing/paired_device.dart';
import '../pairing/pairing_manager.dart';
import '../pairing/repositories.dart';
import '../protocol/constants.dart';
import '../protocol/device_info.dart';
import '../protocol/messages.dart';
import '../protocol/protocol_exception.dart';
import '../text/text_payload.dart';
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
/// Sprint 2: `GET /health`, `GET /api/info`, `WS /ws` con emparejamiento por QR,
/// autenticación X25519 y mensajes cifrados con ChaCha20-Poly1305.
final class LocalServer {
  LocalServer._({
    required this.identity,
    required PairedDeviceRepository devices,
    required HistoryRepository history,
    required this.name,
    required this.appVersion,
    PairingConfirmation? onPairingRequest,
    Duration pairingWindow = JScanDefaults.pairingWindow,
    Duration pairingConfirmationTimeout =
        JScanDefaults.pairingConfirmationTimeout,
  })  : _devices = devices,
        _history = history,
        startedAt = DateTime.now() {
    _pairing = PairingManager(
      identity: identity,
      serverName: name,
      appVersion: appVersion,
      devices: devices,
      onConfirm: onPairingRequest,
      windowDuration: pairingWindow,
      confirmationTimeout: pairingConfirmationTimeout,
    );
  }

  static Future<LocalServer> start({
    required LocalIdentity identity,
    required PairedDeviceRepository pairedDevices,
    HistoryRepository? history,
    Directory? downloadDirectory,
    int port = JScanDefaults.port,
    String? name,
    String appVersion = '0.1.0',
    bool includeLoopback = false,
    PairingConfirmation? onPairingRequest,
    Duration pairingWindow = JScanDefaults.pairingWindow,
    Duration pairingConfirmationTimeout =
        JScanDefaults.pairingConfirmationTimeout,
  }) async {
    final server = LocalServer._(
      identity: identity,
      devices: pairedDevices,
      history: history ?? InMemoryHistoryRepository(),
      name: name ?? Platform.localHostname,
      appVersion: appVersion,
      onPairingRequest: onPairingRequest,
      pairingWindow: pairingWindow,
      pairingConfirmationTimeout: pairingConfirmationTimeout,
    );
    server._includeLoopback = includeLoopback;
    if (downloadDirectory != null) {
      server._configureFileReceiver(downloadDirectory);
    }

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

  final LocalIdentity identity;
  final String name;
  final String appVersion;
  final DateTime startedAt;

  final PairedDeviceRepository _devices;
  final HistoryRepository _history;
  FileReceiver? _files;
  late final PairingManager _pairing;
  late final HttpServer _httpServer;
  late bool _includeLoopback;

  final Map<String, _SessionRuntime> _runtimes = <String, _SessionRuntime>{};
  final Map<String, WebSocketChannel> _channels = <String, WebSocketChannel>{};
  final Map<String, StreamSubscription<dynamic>> _subscriptions =
      <String, StreamSubscription<dynamic>>{};
  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();

  bool _stopping = false;

  String get id => identity.id;
  int get port => _httpServer.port;
  bool get isRunning => !_stopping;

  /// QR vigente, o `null` si la ventana de emparejamiento está cerrada.
  PairingCode? get pairingCode => _pairing.currentCode;
  bool get isPairingOpen => _pairing.isOpen;
  DateTime? get pairingExpiresAt => _pairing.expiresAt;

  /// Eventos de conexión, autenticación, emparejamiento y ping.
  Stream<ServerEvent> get events => _events.stream;

  List<ClientSession> get sessions {
    final list = _runtimes.values.map((runtime) => runtime.session).toList()
      ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
    return List<ClientSession>.unmodifiable(list);
  }

  Uri httpUri(String host) =>
      Uri(scheme: 'http', host: host, port: port, path: '/health');

  Uri wsUri(String host) =>
      Uri(scheme: 'ws', host: host, port: port, path: JScanDefaults.wsPath);

  /// Abre una ventana de emparejamiento y genera un QR nuevo.
  Future<PairingCode> openPairing({String? host, Duration? duration}) async {
    final address = host ??
        await primaryLocalAddress() ??
        InternetAddress.loopbackIPv4.address;
    final code = _pairing.open(
      host: address,
      port: port,
      duration: duration,
    );
    _emit(ServerPairingWindowChanged(open: true, expiresAt: code.expiresAt));
    return code;
  }

  /// Cierra la ventana y descarta los códigos pendientes.
  void closePairing() {
    final wasOpen = _pairing.isOpen;
    _pairing.close();
    if (wasOpen) {
      _emit(const ServerPairingWindowChanged(open: false));
    }
  }

  Future<List<PairedDevice>> listPairedDevices() => _devices.all();

  /// Historial persistido de textos y portapapeles recibidos.
  Future<List<HistoryEntry>> listHistory({int limit = 100}) =>
      _history.recent(limit: limit);

  Future<bool> deleteHistoryEntry(String id) => _history.remove(id);

  Future<void> clearHistory() => _history.clear();

  /// Carpeta donde se guardan los archivos recibidos (o `null` si está
  /// deshabilitada).
  Directory? get downloadDirectory => _files?.destination;

  /// Cambia la carpeta para nuevas transferencias. `false` si hay alguna activa.
  bool setDownloadDirectory(Directory directory) {
    final files = _files;
    if (files == null) {
      _configureFileReceiver(directory);
      return true;
    }
    return files.setDestination(directory);
  }

  void _configureFileReceiver(Directory directory) {
    _files = FileReceiver(
      destination: directory,
      onProgress: (progress) => _emit(ServerFileProgress(progress)),
      onReceived: (file) => _emit(ServerFileReceived(file)),
      onCanceled: (transferId, name) => _emit(
        ServerFileCanceled(transferId: transferId, name: name),
      ),
    );
  }

  /// Revoca un dispositivo. Sus sesiones activas se cierran de inmediato.
  Future<bool> removePairedDevice(String deviceId) async {
    final existing = await _devices.find(deviceId);
    if (existing == null) return false;

    await _devices.remove(deviceId);

    for (final runtime in _runtimes.values.toList()) {
      if (runtime.session.pairedDeviceId != deviceId) continue;
      final cipher = runtime.cipher;
      if (cipher != null) {
        await _sendSecure(
          runtime,
          Envelope.create(
            MessageType.error,
            payload: <String, Object?>{
              'code': ProtocolErrorCode.notPaired,
              'message': 'Este dispositivo fue desautorizado por la PC',
            },
          ),
        );
      }
      await _closeSession(runtime.session.id);
    }

    _emit(ServerDeviceRemoved(deviceId));
    return true;
  }

  Future<Map<String, Object?>> health() async {
    final addresses = await localIPv4Addresses(
      includeLoopback: _includeLoopback,
    );
    final paired = await _devices.all();
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
      'sessions': _runtimes.length,
      'pairingRequired': true,
      'pairingOpen': _pairing.isOpen,
      'pairedDevices': paired.length,
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
    _runtimes.clear();

    await _httpServer.close(force: true);
    await _events.close();
    await _history.close();
    await _files?.dispose();
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
    final runtime = _SessionRuntime(session);
    _runtimes[session.id] = runtime;
    _channels[session.id] = channel;
    _emit(ServerClientConnected(session));

    _subscriptions[session.id] = channel.stream.listen(
      (data) => _enqueue(runtime, data),
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

  void _enqueue(_SessionRuntime runtime, Object? data) {
    runtime.queue = runtime.queue.then((_) async {
      try {
        await _handleFrame(runtime, data);
      } catch (error) {
        _emit(
          ServerErrorEvent(
            code: ProtocolErrorCode.internalError,
            message: 'Error al procesar un mensaje: $error',
          ),
        );
      }
    });
  }

  Future<void> _handleFrame(_SessionRuntime runtime, Object? data) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;

    final Envelope outer;
    try {
      outer = Envelope.decode(data);
    } on ProtocolException catch (error) {
      _sendError(channel, null, error.code, error.message);
      if (error.code == ProtocolErrorCode.unsupportedVersion) {
        await _closeSession(runtime.session.id);
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

    final type = outer.knownType;
    if (type == null) {
      _sendError(
        channel,
        outer.id,
        ProtocolErrorCode.unsupportedType,
        'Tipo no soportado: ${outer.type}',
      );
      return;
    }

    if (type == MessageType.encrypted) {
      final cipher = runtime.cipher;
      if (cipher == null) {
        _sendError(
          channel,
          outer.id,
          ProtocolErrorCode.notPaired,
          'Empareja este dispositivo antes de enviar mensajes cifrados',
        );
        await _closeSession(runtime.session.id);
        return;
      }

      final Envelope inner;
      try {
        inner = await cipher.openEnvelope(outer);
      } catch (error) {
        _sendError(
          channel,
          outer.id,
          ProtocolErrorCode.unauthorized,
          'No se pudo descifrar el mensaje: $error',
        );
        await _closeSession(runtime.session.id);
        return;
      }

      await _handleSecure(runtime, inner);
      return;
    }

    if (runtime.cipher != null) {
      _sendError(
        channel,
        outer.id,
        ProtocolErrorCode.unauthorized,
        'Los mensajes de una sesión autenticada deben ir cifrados',
      );
      await _closeSession(runtime.session.id);
      return;
    }

    switch (type) {
      case MessageType.pairHello:
        _handlePairHello(runtime, outer);
        break;
      case MessageType.pairRequest:
        await _handlePairRequest(runtime, outer);
        break;
      case MessageType.hello:
        await _handleHello(runtime, outer);
        break;
      case MessageType.auth:
        await _handleAuth(runtime, outer);
        break;
      case MessageType.ping:
      case MessageType.text:
      case MessageType.clipboard:
      case MessageType.fileOffer:
      case MessageType.fileChunk:
      case MessageType.fileComplete:
      case MessageType.cancel:
        await _rejectNotPaired(runtime, outer, channel);
        break;
      case MessageType.helloAck:
      case MessageType.challenge:
      case MessageType.authOk:
      case MessageType.pong:
      case MessageType.error:
      case MessageType.pairChallenge:
      case MessageType.pairAccept:
      case MessageType.pairReject:
      case MessageType.textAck:
      case MessageType.clipboardAck:
      case MessageType.fileAccept:
      case MessageType.fileAck:
      case MessageType.fileDone:
      case MessageType.encrypted:
        _sendError(
          channel,
          outer.id,
          ProtocolErrorCode.unsupportedType,
          'El servidor no espera ${type.wire} de un cliente',
        );
        break;
    }
  }

  void _handlePairHello(_SessionRuntime runtime, Envelope envelope) {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;

    try {
      final device = DeviceInfo.fromJson(envelope.payload['device']);
      final publicKey = _requireBytes(envelope.payload['publicKey']);
      final challenge = _pairing.begin(
        sessionId: runtime.session.id,
        device: device,
        devicePublicKey: publicKey,
      );

      runtime.session = runtime.session.copyWith(
        device: device,
        lastSeen: DateTime.now(),
        state: ClientSessionState.pairing,
      );
      _emit(ServerClientUpdated(runtime.session));

      _send(
        channel,
        Envelope.create(
          MessageType.pairChallenge,
          id: envelope.id,
          payload: <String, Object?>{
            'nonce': encodeBase64(challenge.nonce),
            'serverId': id,
            'serverName': name,
            'protocolVersion': JScanDefaults.protocolVersion,
            'expiresAt': challenge.expiresAt.toUtc().millisecondsSinceEpoch,
          },
        ),
      );
    } on ProtocolException catch (error) {
      _sendError(channel, envelope.id, error.code, error.message);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo iniciar el emparejamiento: $error',
      );
    }
  }

  Future<void> _handlePairRequest(
    _SessionRuntime runtime,
    Envelope envelope,
  ) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;

    try {
      final challenge = envelope.stringField('challenge');
      final nonce = envelope.stringField('nonce');
      final box = envelope.stringField('box');
      if (challenge == null || nonce == null || box == null) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidPayload,
          'pair_request requiere challenge, nonce y box',
        );
      }

      final outcome = await _pairing.finish(
        sessionId: runtime.session.id,
        challenge: challenge,
        nonce: nonce,
        box: box,
        remoteAddress: runtime.session.remoteAddress,
      );

      _send(
        channel,
        Envelope.create(
          MessageType.pairAccept,
          id: envelope.id,
          payload: <String, Object?>{
            'deviceId': outcome.device.deviceId,
            'server': DeviceInfo(
              id: id,
              name: name,
              platform: currentPlatform(),
              appVersion: appVersion,
            ).toJson(),
            'proof': outcome.proof,
            'pairedAt': outcome.pairedAt.toUtc().millisecondsSinceEpoch,
          },
        ),
      );
      _emit(ServerDevicePaired(outcome.device));
      _emit(const ServerPairingWindowChanged(open: false));

      // El celular cierra la conexión y vuelve a entrar ya autenticado.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _closeSession(runtime.session.id);
    } on ProtocolException catch (error) {
      _send(
        channel,
        Envelope.create(
          MessageType.pairReject,
          id: envelope.id,
          payload: <String, Object?>{
            'code': error.code,
            'message': error.message,
          },
        ),
      );
      _emit(
        ServerPairingFailed(code: error.code, message: error.message),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _closeSession(runtime.session.id);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo completar el emparejamiento: $error',
      );
      await _closeSession(runtime.session.id);
    }
  }

  Future<void> _handleHello(_SessionRuntime runtime, Envelope envelope) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;

    try {
      final device = DeviceInfo.fromJson(envelope.payload['device']);
      final publicKey = _requireBytes(envelope.payload['publicKey']);
      final paired = await _devices.find(device.id);

      if (paired == null || !constantTimeEquals(paired.publicKey, publicKey)) {
        _sendError(
          channel,
          envelope.id,
          ProtocolErrorCode.notPaired,
          'Este dispositivo no está emparejado con la PC',
        );
        await _closeSession(runtime.session.id);
        return;
      }

      final nonce = secureRandomBytes(32);
      runtime.auth = _AuthChallenge(device: paired, nonce: nonce);
      runtime.session = runtime.session.copyWith(
        device: device,
        lastSeen: DateTime.now(),
        state: ClientSessionState.unauthenticated,
      );
      _emit(ServerClientUpdated(runtime.session));

      _send(
        channel,
        Envelope.create(
          MessageType.challenge,
          id: envelope.id,
          payload: <String, Object?>{
            'nonce': encodeBase64(nonce),
            'serverId': id,
            'deviceId': device.id,
          },
        ),
      );
    } on ProtocolException catch (error) {
      _sendError(channel, envelope.id, error.code, error.message);
      await _closeSession(runtime.session.id);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo autenticar: $error',
      );
      await _closeSession(runtime.session.id);
    }
  }

  Future<void> _handleAuth(_SessionRuntime runtime, Envelope envelope) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;

    final challenge = runtime.auth;
    if (challenge == null) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.notPaired,
        'Primero envía hello y espera el challenge',
      );
      await _closeSession(runtime.session.id);
      return;
    }

    final proof = envelope.stringField('proof');
    if (proof == null || proof.isEmpty) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.invalidPayload,
        'auth requiere proof',
      );
      await _closeSession(runtime.session.id);
      return;
    }

    try {
      final shared = await identity.sharedSecret(challenge.device.publicKey);
      final authKey = await SecureChannel.deriveAuthKey(shared, id);
      final valid = await SecureChannel.verifyHmac(
        key: authKey,
        message: 'auth|$id|${challenge.device.deviceId}|'
            '${encodeBase64(challenge.nonce)}',
        expected: proof,
      );
      if (!valid) {
        _sendError(
          channel,
          envelope.id,
          ProtocolErrorCode.badProof,
          'La prueba de identidad no es válida',
        );
        await _closeSession(runtime.session.id);
        return;
      }

      final cipher = await SessionCipher.derive(
        sharedSecret: shared,
        serverId: id,
        deviceId: challenge.device.deviceId,
        serverNonce: challenge.nonce,
      );
      runtime.cipher = cipher;
      runtime.auth = null;

      final now = DateTime.now();
      runtime.session = runtime.session.copyWith(
        lastSeen: now,
        state: ClientSessionState.authenticated,
        pairedDeviceId: challenge.device.deviceId,
      );
      await _devices.upsert(challenge.device.copyWith(lastSeenAt: now));
      _emit(ServerClientAuthenticated(runtime.session));
      _emit(ServerClientUpdated(runtime.session));

      await _sendSecure(
        runtime,
        Envelope.create(
          MessageType.authOk,
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
          },
        ),
      );
    } on ProtocolException catch (error) {
      _sendError(channel, envelope.id, error.code, error.message);
      await _closeSession(runtime.session.id);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo verificar la identidad: $error',
      );
      await _closeSession(runtime.session.id);
    }
  }

  Future<void> _handleSecure(
    _SessionRuntime runtime,
    Envelope envelope,
  ) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;

    switch (envelope.knownType) {
      case MessageType.ping:
        final nonce = envelope.stringField('nonce') ?? envelope.id;
        final updated = runtime.session.copyWith(lastSeen: DateTime.now());
        runtime.session = updated;
        await _sendSecure(
          runtime,
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
        break;
      case MessageType.text:
      case MessageType.clipboard:
        await _handleIncomingText(runtime, envelope);
        break;
      case MessageType.fileOffer:
        await _handleFileOffer(runtime, envelope);
        break;
      case MessageType.fileChunk:
        await _handleFileChunk(runtime, envelope);
        break;
      case MessageType.fileComplete:
        await _handleFileComplete(runtime, envelope);
        break;
      case MessageType.cancel:
        await _handleFileCancel(runtime, envelope);
        break;
      case MessageType.error:
        // El cliente informa de un error propio; no requiere respuesta.
        break;
      default:
        _sendError(
          channel,
          envelope.id,
          ProtocolErrorCode.unsupportedType,
          'Tipo no soportado en una sesión autenticada: ${envelope.type}',
        );
    }
  }

  Future<void> _handleIncomingText(
    _SessionRuntime runtime,
    Envelope envelope,
  ) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;

    final isClipboard = envelope.knownType == MessageType.clipboard;
    final kind = isClipboard ? HistoryKind.clipboard : HistoryKind.text;

    try {
      final payload = TextPayload.parse(envelope.payload);
      final now = DateTime.now();
      final entry = HistoryEntry(
        id: newId(10),
        kind: kind,
        text: payload.text,
        receivedAt: now,
        fromDeviceId: runtime.session.pairedDeviceId,
        fromDeviceName: runtime.session.displayName,
      );

      await _history.save(entry);
      runtime.session = runtime.session.copyWith(lastSeen: now);
      _emit(ServerMessageReceived(entry));

      await _sendSecure(
        runtime,
        Envelope.create(
          isClipboard ? MessageType.clipboardAck : MessageType.textAck,
          id: envelope.id,
          payload: <String, Object?>{
            'historyId': entry.id,
            'kind': payload.kind.wire,
            'receivedAt': now.millisecondsSinceEpoch,
          },
        ),
      );
    } on ProtocolException catch (error) {
      _sendError(channel, envelope.id, error.code, error.message);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo guardar el mensaje: $error',
      );
    }
  }

  Future<void> _handleFileOffer(
    _SessionRuntime runtime,
    Envelope envelope,
  ) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;
    final files = _files;
    if (files == null) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.unsupportedType,
        'La PC no tiene una carpeta de recepción configurada',
      );
      return;
    }

    try {
      final offer = FileOffer.parse(envelope.payload);
      final accept = await files.accept(
        offer,
        sessionId: runtime.session.id,
        fromDeviceId: runtime.session.pairedDeviceId,
        fromDeviceName: runtime.session.displayName,
      );
      runtime.session = runtime.session.copyWith(lastSeen: DateTime.now());
      await _sendSecure(
        runtime,
        Envelope.create(
          MessageType.fileAccept,
          id: envelope.id,
          payload: accept.toJson(),
        ),
      );
    } on ProtocolException catch (error) {
      _sendError(channel, envelope.id, error.code, error.message);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo aceptar el archivo: $error',
      );
    }
  }

  Future<void> _handleFileChunk(
    _SessionRuntime runtime,
    Envelope envelope,
  ) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;
    final files = _files;
    if (files == null) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.unsupportedType,
        'La PC no tiene una carpeta de recepción configurada',
      );
      return;
    }

    try {
      final transferId = envelope.stringField('transferId');
      final offset = envelope.intField('offset');
      final data = envelope.stringField('data');
      if (transferId == null || offset == null || data == null) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidPayload,
          'file_chunk requiere transferId, offset y data',
        );
      }
      final List<int> bytes;
      try {
        bytes = decodeBase64(data);
      } catch (_) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidPayload,
          'data no es base64 válido',
        );
      }

      final progress = await files.writeChunk(transferId, offset, bytes);
      runtime.session = runtime.session.copyWith(lastSeen: DateTime.now());
      await _sendSecure(
        runtime,
        Envelope.create(
          MessageType.fileAck,
          id: envelope.id,
          payload: <String, Object?>{
            'transferId': progress.transferId,
            'receivedBytes': progress.sentBytes,
          },
        ),
      );
    } on ProtocolException catch (error) {
      _sendError(channel, envelope.id, error.code, error.message);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo guardar el trozo: $error',
      );
    }
  }

  Future<void> _handleFileComplete(
    _SessionRuntime runtime,
    Envelope envelope,
  ) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;
    final files = _files;
    if (files == null) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.unsupportedType,
        'La PC no tiene una carpeta de recepción configurada',
      );
      return;
    }

    try {
      final transferId = envelope.stringField('transferId');
      final size = envelope.intField('size');
      final sha256 = envelope.stringField('sha256');
      if (transferId == null || size == null || sha256 == null) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidPayload,
          'file_complete requiere transferId, size y sha256',
        );
      }

      final received = await files.complete(
        transferId,
        size: size,
        sha256Hex: sha256,
      );
      runtime.session = runtime.session.copyWith(lastSeen: DateTime.now());
      await _sendSecure(
        runtime,
        Envelope.create(
          MessageType.fileDone,
          id: envelope.id,
          payload: <String, Object?>{
            'transferId': received.id,
            'name': received.name,
            'size': received.size,
            'sha256': received.sha256,
            'elapsedMs': received.duration.inMilliseconds,
          },
        ),
      );
    } on ProtocolException catch (error) {
      _sendError(channel, envelope.id, error.code, error.message);
    } catch (error) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.internalError,
        'No se pudo completar el archivo: $error',
      );
    }
  }

  Future<void> _handleFileCancel(
    _SessionRuntime runtime,
    Envelope envelope,
  ) async {
    final channel = _channels[runtime.session.id];
    if (channel == null) return;
    final transferId = envelope.stringField('transferId');
    if (transferId == null) {
      _sendError(
        channel,
        envelope.id,
        ProtocolErrorCode.invalidPayload,
        'cancel requiere transferId',
      );
      return;
    }
    await _files?.cancel(transferId);
    runtime.session = runtime.session.copyWith(lastSeen: DateTime.now());
  }

  Future<void> _rejectNotPaired(
    _SessionRuntime runtime,
    Envelope envelope,
    WebSocketChannel channel,
  ) async {
    _sendError(
      channel,
      envelope.id,
      ProtocolErrorCode.notPaired,
      'Empareja este dispositivo antes de enviar mensajes',
    );
    await _closeSession(runtime.session.id);
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

  Future<void> _sendSecure(_SessionRuntime runtime, Envelope inner) async {
    final cipher = runtime.cipher;
    final channel = _channels[runtime.session.id];
    if (cipher == null || channel == null) return;
    try {
      final sealed = await cipher.sealEnvelope(inner);
      _send(channel, sealed);
    } catch (error) {
      _emit(
        ServerErrorEvent(
          code: ProtocolErrorCode.internalError,
          message: 'No se pudo cifrar ${inner.type}: $error',
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

  List<int> _requireBytes(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'Falta la clave pública (publicKey)',
      );
    }
    try {
      return decodeBase64(value);
    } catch (_) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'publicKey no es base64 válido',
      );
    }
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
    final removed = _runtimes.remove(sessionId);
    _channels.remove(sessionId);
    final subscription = _subscriptions.remove(sessionId);
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    unawaited(_files?.abortSession(sessionId));
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

final class _SessionRuntime {
  _SessionRuntime(this.session);

  ClientSession session;
  SessionCipher? cipher;
  _AuthChallenge? auth;
  Future<void> queue = Future<void>.value();
}

final class _AuthChallenge {
  const _AuthChallenge({required this.device, required this.nonce});

  final PairedDevice device;
  final List<int> nonce;
}

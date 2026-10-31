import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  group('LocalServer + JScanClient', () {
    late LocalServer server;
    late LocalIdentity phoneIdentity;
    late InMemoryPairedDeviceRepository devices;

    setUp(() async {
      final serverIdentity = await LocalIdentity.generate(id: 'testserver');
      devices = InMemoryPairedDeviceRepository();
      phoneIdentity = await LocalIdentity.generate(id: 'phone1');
      server = await LocalServer.start(
        identity: serverIdentity,
        pairedDevices: devices,
        port: 0,
        name: 'PC de prueba',
        onPairingRequest: (_) async => true,
      );
    });

    tearDown(() async {
      await server.stop();
    });

    Future<PairedServer> pairPhone() async {
      final code = await server.openPairing(host: '127.0.0.1');
      final result = await JScanClient.pair(
        code: code,
        identity: phoneIdentity,
        device: const DeviceInfo(
          id: 'phone1',
          name: 'Pixel de prueba',
          platform: 'android',
        ),
      );
      return result.server;
    }

    test('expone /health sin autenticación', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as Map<String, Object?>;
      expect(body['status'], 'ok');
      expect(body['id'], 'testserver');
      expect(body['name'], 'PC de prueba');
      expect(body['protocolVersion'], JScanDefaults.protocolVersion);
      expect(body['wsPath'], JScanDefaults.wsPath);
      expect(body['pairingRequired'], isTrue);
      expect(body['pairedDevices'], 0);
      expect(body['addresses'], isA<List<Object?>>());
    });

    test('responde 404 en rutas desconocidas', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:${server.port}/nada'),
      );

      expect(response.statusCode, 404);
    });

    test('empareja, autentica con cifrado y mide el ping', () async {
      final events = <ServerEvent>[];
      final subscription = server.events.listen(events.add);

      final paired = await pairPhone();
      final stored = await devices.all();
      expect(stored, hasLength(1));
      expect(stored.single.deviceId, 'phone1');
      expect(stored.single.publicKey, phoneIdentity.publicKey);

      final client = await JScanClient.connectPaired(
        server: paired,
        identity: phoneIdentity,
        device: const DeviceInfo(
          id: 'phone1',
          name: 'Pixel de prueba',
          platform: 'android',
        ),
      );

      expect(client.isEncrypted, isTrue);
      expect(client.serverInfo?.id, 'testserver');
      expect(client.serverInfo?.name, 'PC de prueba');
      expect(client.protocolVersion, 1);

      final rtt = await client.ping();
      expect(rtt, lessThan(const Duration(seconds: 2)));
      expect(rtt, greaterThanOrEqualTo(Duration.zero));

      // Da tiempo a que lleguen los eventos al stream.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(events.whereType<ServerClientConnected>(), isNotEmpty);
      expect(events.whereType<ServerClientAuthenticated>(), isNotEmpty);
      expect(events.whereType<ServerPingReceived>(), isNotEmpty);
      expect(server.sessions.single.device?.name, 'Pixel de prueba');
      expect(
        server.sessions.single.state,
        ClientSessionState.authenticated,
      );

      await client.close();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.sessions, isEmpty);

      await subscription.cancel();
    });

    test('un dispositivo no emparejado no puede hacer ping y se cierra',
        () async {
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      );
      await channel.ready;

      final first = Completer<Envelope>();
      final closed = Completer<void>();
      final subscription = channel.stream.listen(
        (data) {
          if (!first.isCompleted) {
            first.complete(Envelope.decode(data));
          }
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) closed.complete();
        },
      );

      channel.sink.add(
        jsonEncode(<String, Object?>{
          'v': 1,
          'id': 'raw1',
          'type': 'ping',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': <String, Object?>{'nonce': 'n1'},
        }),
      );

      final error = await first.future.timeout(const Duration(seconds: 2));
      expect(error.type, MessageType.error.wire);
      expect(error.id, 'raw1');
      expect(error.stringField('code'), ProtocolErrorCode.notPaired);

      await closed.future.timeout(const Duration(seconds: 2));
      await subscription.cancel();
    });

    test('rechaza un hello de un dispositivo desconocido', () async {
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      );
      await channel.ready;

      final messages = <Envelope>[];
      final closed = Completer<void>();
      final subscription = channel.stream.listen(
        (data) => messages.add(Envelope.decode(data)),
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) closed.complete();
        },
      );

      channel.sink.add(
        jsonEncode(<String, Object?>{
          'v': 1,
          'id': 'raw2',
          'type': 'hello',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': <String, Object?>{
            'device': const DeviceInfo(
              id: 'intruso',
              name: 'Intruso',
              platform: 'android',
            ).toJson(),
            'publicKey': encodeBase64(phoneIdentity.publicKey),
          },
        }),
      );

      await closed.future.timeout(const Duration(seconds: 2));
      expect(messages, isNotEmpty);
      expect(messages.first.type, MessageType.error.wire);
      expect(messages.first.stringField('code'), ProtocolErrorCode.notPaired);

      await subscription.cancel();
    });

    test('responde error a un tipo desconocido sin cerrar la conexión',
        () async {
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      );
      await channel.ready;

      channel.sink.add(
        jsonEncode(<String, Object?>{
          'v': 1,
          'id': 'raw3',
          'type': 'tipo_futuro',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': <String, Object?>{},
        }),
      );

      final first = Envelope.decode(await channel.stream.first);
      expect(first.type, MessageType.error.wire);
      expect(first.id, 'raw3');
      expect(first.stringField('code'), ProtocolErrorCode.unsupportedType);

      await channel.sink.close();
    });

    test('rechaza versiones de protocolo distintas y cierra', () async {
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      );
      await channel.ready;

      final messages = <Envelope>[];
      final closed = Completer<void>();
      final subscription = channel.stream.listen(
        (data) => messages.add(Envelope.decode(data)),
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) closed.complete();
        },
      );

      channel.sink.add(
        jsonEncode(<String, Object?>{
          'v': 2,
          'id': 'raw4',
          'type': 'ping',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': <String, Object?>{},
        }),
      );

      await closed.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );

      expect(messages, isNotEmpty);
      expect(messages.first.type, MessageType.error.wire);
      expect(
        messages.first.stringField('code'),
        ProtocolErrorCode.unsupportedVersion,
      );

      await subscription.cancel();
    });
  });
}

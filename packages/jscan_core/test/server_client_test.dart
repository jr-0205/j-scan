import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  group('LocalServer + JScanClient', () {
    late LocalServer server;

    setUp(() async {
      server = await LocalServer.start(
        port: 0,
        id: 'testserver',
        name: 'PC de prueba',
      );
    });

    tearDown(() async {
      await server.stop();
    });

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
      expect(body['addresses'], isA<List<Object?>>());
    });

    test('responde 404 en rutas desconocidas', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:${server.port}/nada'),
      );

      expect(response.statusCode, 404);
    });

    test('hace hello y ping con RTT medible', () async {
      final events = <ServerEvent>[];
      final subscription = server.events.listen(events.add);

      final client = await JScanClient.connect(
        host: '127.0.0.1',
        port: server.port,
        device: const DeviceInfo(
          id: 'phone1',
          name: 'Pixel de prueba',
          platform: 'android',
        ),
      );

      expect(client.serverInfo?.id, 'testserver');
      expect(client.serverInfo?.name, 'PC de prueba');
      expect(client.protocolVersion, 1);
      expect(client.pairingRequired, isFalse);

      final rtt = await client.ping();
      expect(rtt, lessThan(const Duration(seconds: 2)));
      expect(rtt, greaterThanOrEqualTo(Duration.zero));

      // Da tiempo a que lleguen los eventos al stream.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.whereType<ServerClientConnected>(), isNotEmpty);
      expect(events.whereType<ServerClientUpdated>(), isNotEmpty);
      expect(events.whereType<ServerPingReceived>(), isNotEmpty);
      expect(server.sessions.single.device?.name, 'Pixel de prueba');

      await client.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.sessions, isEmpty);

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
          'id': 'raw1',
          'type': 'tipo_futuro',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': <String, Object?>{},
        }),
      );

      final first = Envelope.decode(await channel.stream.first);
      expect(first.type, MessageType.error.wire);
      expect(first.id, 'raw1');
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
          'id': 'raw2',
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

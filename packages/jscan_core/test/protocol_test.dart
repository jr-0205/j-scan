import 'dart:convert';

import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('Envelope', () {
    test('hace roundtrip de creación, encode y decode', () {
      final original = Envelope.create(
        MessageType.ping,
        payload: <String, Object?>{'nonce': 'abc123'},
      );

      final decoded = Envelope.decode(original.encode());

      expect(decoded.id, original.id);
      expect(decoded.type, 'ping');
      expect(decoded.knownType, MessageType.ping);
      expect(decoded.timestamp, original.timestamp);
      expect(decoded.stringField('nonce'), 'abc123');
    });

    test('acepta frames binarios UTF-8', () {
      final original = Envelope.create(MessageType.hello);
      final decoded = Envelope.decode(utf8.encode(original.encode()));

      expect(decoded.type, 'hello');
    });

    test('rechaza versiones distintas de 1', () {
      final raw = jsonEncode(<String, Object?>{
        'v': 99,
        'id': 'abc',
        'type': 'ping',
        'ts': 1,
        'payload': <String, Object?>{},
      });

      expect(
        () => Envelope.decode(raw),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.unsupportedVersion,
          ),
        ),
      );
    });

    test('rechaza JSON inválido', () {
      expect(
        () => Envelope.decode('{no es json'),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rechaza payload que no es objeto', () {
      final raw = jsonEncode(<String, Object?>{
        'v': 1,
        'id': 'abc',
        'type': 'ping',
        'ts': 1,
        'payload': 'texto',
      });

      expect(
        () => Envelope.decode(raw),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.invalidPayload,
          ),
        ),
      );
    });

    test('mantiene tipos desconocidos para responder error', () {
      final envelope = Envelope.decode(
        jsonEncode(<String, Object?>{
          'v': 1,
          'id': 'abc',
          'type': 'mensaje_futuro',
          'ts': 1,
          'payload': <String, Object?>{},
        }),
      );

      expect(envelope.knownType, isNull);
      expect(envelope.type, 'mensaje_futuro');
    });
  });

  group('DeviceInfo', () {
    test('valida campos obligatorios', () {
      expect(
        () => DeviceInfo.fromJson(<String, Object?>{'id': 'abc'}),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('hace roundtrip', () {
      const device = DeviceInfo(
        id: 'abc',
        name: 'Pixel',
        platform: 'android',
        appVersion: '0.1.0',
      );

      final decoded = DeviceInfo.fromJson(device.toJson());

      expect(decoded.id, device.id);
      expect(decoded.name, device.name);
      expect(decoded.platform, device.platform);
    });
  });
}

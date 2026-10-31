import 'dart:async';

import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('Emparejamiento y seguridad', () {
    late LocalIdentity serverIdentity;
    late LocalIdentity phoneIdentity;
    late InMemoryPairedDeviceRepository devices;
    late LocalServer server;
    var accept = true;
    var requests = 0;

    const phone = DeviceInfo(
      id: 'phone1',
      name: 'Pixel de prueba',
      platform: 'android',
    );

    setUp(() async {
      accept = true;
      requests = 0;
      serverIdentity = await LocalIdentity.generate(id: 'pc1');
      phoneIdentity = await LocalIdentity.generate(id: 'phone1');
      devices = InMemoryPairedDeviceRepository();
      server = await LocalServer.start(
        identity: serverIdentity,
        pairedDevices: devices,
        port: 0,
        name: 'PC de prueba',
        onPairingRequest: (_) async {
          requests += 1;
          return accept;
        },
        pairingWindow: const Duration(minutes: 1),
      );
    });

    tearDown(() async {
      await server.stop();
    });

    Future<PairingCode> openCode({Duration? duration}) =>
        server.openPairing(host: '127.0.0.1', duration: duration);

    Future<PairingResult> pair(PairingCode code) {
      return JScanClient.pair(
        code: code,
        identity: phoneIdentity,
        device: phone,
      );
    }

    test('la PC confirma, guarda el dispositivo y permite reconectar',
        () async {
      final result = await pair(await openCode());

      expect(requests, 1);
      expect(server.isPairingOpen, isFalse);
      expect(result.server.serverId, 'pc1');
      expect(result.server.host, '127.0.0.1');
      expect(result.serverInfo.name, 'PC de prueba');

      final stored = await devices.all();
      expect(stored, hasLength(1));
      expect(stored.single.deviceId, 'phone1');
      expect(stored.single.name, 'Pixel de prueba');

      final client = await JScanClient.connectPaired(
        server: result.server,
        identity: phoneIdentity,
        device: phone,
      );
      expect(client.isEncrypted, isTrue);
      expect(await client.ping(), lessThan(const Duration(seconds: 2)));
      await client.close();

      // Una segunda conexión reutiliza la misma identidad y la misma clave.
      final again = await JScanClient.connectPaired(
        server: result.server,
        identity: phoneIdentity,
        device: phone,
      );
      expect(await again.ping(), lessThan(const Duration(seconds: 2)));
      await again.close();
    });

    test('la PC puede rechazar y no guarda nada', () async {
      accept = false;
      final code = await openCode();

      await expectLater(
        pair(code),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.pairingRejected,
          ),
        ),
      );
      expect(await devices.all(), isEmpty);
    });

    test('un token incorrecto no empareja', () async {
      final code = await openCode();
      final tampered = code.copyWith(token: secureRandomBytes(32));

      await expectLater(
        pair(tampered),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.invalidToken,
          ),
        ),
      );
      expect(await devices.all(), isEmpty);
    });

    test('un QR caducado no empareja', () async {
      final code = await openCode(
        duration: const Duration(milliseconds: 80),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await expectLater(
        pair(code),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.pairingClosed,
          ),
        ),
      );
    });

    test('sin ventana abierta no se puede emparejar', () async {
      final code = PairingCode(
        serverId: server.id,
        serverName: server.name,
        host: '127.0.0.1',
        port: server.port,
        serverPublicKey: serverIdentity.publicKey,
        token: secureRandomBytes(32),
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );

      await expectLater(
        pair(code),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.pairingClosed,
          ),
        ),
      );
    });

    test('revocar un dispositivo cierra su sesión y le impide volver',
        () async {
      final result = await pair(await openCode());
      final client = await JScanClient.connectPaired(
        server: result.server,
        identity: phoneIdentity,
        device: phone,
      );
      expect(await client.ping(), lessThan(const Duration(seconds: 2)));

      expect(await server.removePairedDevice('phone1'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await expectLater(
        client.ping(),
        throwsA(isA<JScanConnectionException>()),
      );
      await client.close();

      await expectLater(
        JScanClient.connectPaired(
          server: result.server,
          identity: phoneIdentity,
          device: phone,
        ),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.notPaired,
          ),
        ),
      );
    });

    test('emparejar dos veces la misma identidad no duplica el registro',
        () async {
      await pair(await openCode());
      await pair(await openCode());
      expect(await devices.all(), hasLength(1));
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('código de emparejamiento', () {
    test('codifica y decodifica todos los campos', () {
      final expires = DateTime.now().add(const Duration(minutes: 2));
      final code = PairingCode(
        serverId: 'pc1',
        serverName: 'PC de prueba',
        host: '192.168.1.20',
        port: 47821,
        serverPublicKey: List<int>.generate(32, (i) => i),
        token: List<int>.generate(32, (i) => 255 - i),
        expiresAt: expires,
      );

      final decoded = PairingCode.decode(code.encode());
      expect(decoded.serverId, 'pc1');
      expect(decoded.serverName, 'PC de prueba');
      expect(decoded.host, '192.168.1.20');
      expect(decoded.port, 47821);
      expect(decoded.serverPublicKey, code.serverPublicKey);
      expect(decoded.token, code.token);
      expect(
        decoded.expiresAt.millisecondsSinceEpoch,
        expires.millisecondsSinceEpoch,
      );
      expect(decoded.isExpired(), isFalse);
    });

    test('accepta solo la parte codificada', () {
      final code = PairingCode(
        serverId: 'pc1',
        serverName: 'PC',
        host: '127.0.0.1',
        port: 47821,
        serverPublicKey: List<int>.filled(32, 7),
        token: List<int>.filled(32, 8),
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );
      final raw = code.encode().split('?d=').last;
      expect(PairingCode.decode(raw).serverId, 'pc1');
    });

    test('rechaza un enlace inválido', () {
      expect(
        () => PairingCode.decode('jscan://pair?d=no-es-base64'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => PairingCode.decode('https://ejemplo.com'),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('detecta un código caducado', () {
      final code = PairingCode(
        serverId: 'pc1',
        serverName: 'PC',
        host: '127.0.0.1',
        port: 47821,
        serverPublicKey: List<int>.filled(32, 1),
        token: List<int>.filled(32, 2),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(code.isExpired(), isTrue);
    });
  });

  group('criptografía', () {
    test('X25519 produce el mismo secreto en ambos lados', () async {
      final alice = await LocalIdentity.generate(id: 'alice');
      final bob = await LocalIdentity.generate(id: 'bob');

      final fromAlice = await alice.sharedSecret(bob.publicKey);
      final fromBob = await bob.sharedSecret(alice.publicKey);

      expect(fromAlice, fromBob);
      expect(fromAlice, hasLength(32));
    });

    test('ChaCha20-Poly1305 cifra, descifra y detecta manipulación', () async {
      final shared = secureRandomBytes(32);
      final key = await SecureChannel.derivePairingKey(shared, 'pc1');
      final aad = utf8.encode('contexto');

      final sealed = await SecureChannel.seal(
        key: key,
        plaintext: utf8.encode('hola J-SCAN'),
        aad: aad,
      );
      final clear = await SecureChannel.open(
        key: key,
        nonce: sealed['nonce']!,
        box: sealed['box']!,
        aad: aad,
      );
      expect(utf8.decode(clear), 'hola J-SCAN');

      final tamperedBytes = decodeBase64(sealed['box']!);
      tamperedBytes[tamperedBytes.length - 1] ^= 0x01;
      final tampered = encodeBase64(tamperedBytes);
      expect(
        () => SecureChannel.open(
          key: key,
          nonce: sealed['nonce']!,
          box: tampered,
          aad: aad,
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('las sesiones cifran y descifran sobres', () async {
      final shared = secureRandomBytes(32);
      final nonce = secureRandomBytes(32);
      final sender = await SessionCipher.derive(
        sharedSecret: shared,
        serverId: 'pc1',
        deviceId: 'phone1',
        serverNonce: nonce,
      );
      final receiver = await SessionCipher.derive(
        sharedSecret: shared,
        serverId: 'pc1',
        deviceId: 'phone1',
        serverNonce: nonce,
      );

      final inner = Envelope.create(
        MessageType.ping,
        payload: <String, Object?>{'nonce': 'abc'},
      );
      final outer = await sender.sealEnvelope(inner);
      expect(outer.type, MessageType.encrypted.wire);
      expect(outer.payload['box'], isA<String>());

      final opened = await receiver.openEnvelope(outer);
      expect(opened.type, MessageType.ping.wire);
      expect(opened.id, inner.id);
      expect(opened.stringField('nonce'), 'abc');
    });
  });

  group('persistencia', () {
    test('la identidad se guarda y se recupera con la misma clave', () async {
      final directory = await Directory.systemTemp.createTemp('jscan_id_');
      addTearDown(() => directory.delete(recursive: true));
      final file = LocalIdentityFile(File('${directory.path}/identity.json'));

      final first = await file.loadOrCreate();
      final second = await file.loadOrCreate();

      expect(second.id, first.id);
      expect(second.publicKey, first.publicKey);
      expect(second.seed, first.seed);
    });

    test('los dispositivos emparejados persisten en JSON', () async {
      final directory = await Directory.systemTemp.createTemp('jscan_dev_');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/paired_devices.json';

      final repository = JsonPairedDeviceRepository(File(path));
      final device = PairedDevice(
        deviceId: 'phone1',
        name: 'Pixel',
        platform: 'android',
        publicKey: List<int>.filled(32, 4),
        pairedAt: DateTime.utc(2026, 10, 31, 12),
      );
      await repository.upsert(device);

      final reloaded = JsonPairedDeviceRepository(File(path));
      final devices = await reloaded.all();
      expect(devices, hasLength(1));
      expect(devices.single.deviceId, 'phone1');
      expect(devices.single.publicKey, device.publicKey);
      expect(
        devices.single.pairedAt.toUtc(),
        DateTime.utc(2026, 10, 31, 12),
      );

      await reloaded.remove('phone1');
      expect(await reloaded.all(), isEmpty);
      expect(await JsonPairedDeviceRepository(File(path)).all(), isEmpty);
    });
  });
}

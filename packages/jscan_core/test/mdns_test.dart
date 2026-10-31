import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('mDNS de extremo a extremo', () {
    test(
      'la PC se anuncia, el cliente la descubre, empareja y hace ping cifrado',
      () async {
        final errors = <Object>[];
        final serverIdentity = await LocalIdentity.generate(id: 'e2eserver');
        final phoneIdentity = await LocalIdentity.generate(id: 'e2ephone');
        final server = await LocalServer.start(
          identity: serverIdentity,
          pairedDevices: InMemoryPairedDeviceRepository(),
          port: 0,
          name: 'PC E2E',
          onPairingRequest: (_) async => true,
        );
        final advertiser = MdnsAdvertiser(
          serverId: server.id,
          displayName: server.name,
          port: server.port,
          includeLoopback: true,
          onError: (error, _) => errors.add(error),
        );
        final browser = MdnsBrowser(
          onError: (error, _) => errors.add(error),
        );

        try {
          await advertiser.start();
          await browser.start();

          final peers = await browser.refresh(
            timeout: const Duration(seconds: 3),
          );
          final peer = peers.where((candidate) => candidate.id == 'e2eserver');
          expect(
            peer,
            isNotEmpty,
            reason: 'No se descubrió la PC. Peers: $peers. '
                'Errores: $errors',
          );

          final discovered = peer.first;
          expect(discovered.name, 'PC E2E');
          expect(discovered.port, server.port);
          expect(discovered.protocolVersion, 1);
          expect(discovered.isCompatible, isTrue);

          final code = await server.openPairing(
            host: discovered.connectHost,
          );
          final pairing = await JScanClient.pair(
            code: code,
            identity: phoneIdentity,
            device: const DeviceInfo(
              id: 'e2ephone',
              name: 'Pixel E2E',
              platform: 'android',
            ),
          );

          final client = await JScanClient.connectPaired(
            server: pairing.server,
            identity: phoneIdentity,
            device: const DeviceInfo(
              id: 'e2ephone',
              name: 'Pixel E2E',
              platform: 'android',
            ),
          );
          expect(client.isEncrypted, isTrue);
          final rtt = await client.ping();
          expect(rtt, lessThan(const Duration(seconds: 2)));
          await client.close();
        } finally {
          await browser.stop();
          await advertiser.stop();
          await server.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}

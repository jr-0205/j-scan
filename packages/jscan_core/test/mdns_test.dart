import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('mDNS de extremo a extremo', () {
    test(
      'la PC se anuncia, el cliente la descubre y recibe un pong',
      () async {
        final errors = <Object>[];
        final server = await LocalServer.start(
          port: 0,
          id: 'e2eserver',
          name: 'PC E2E',
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

          final client = await JScanClient.connect(
            host: discovered.connectHost,
            port: discovered.port,
          );
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

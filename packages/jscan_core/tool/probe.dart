import 'dart:async';
import 'dart:io';

import 'package:jscan_core/jscan_core.dart';

/// Busca PCs J-SCAN con mDNS (o conecta a una IP) y mide el RTT del ping.
///
/// Uso:
///   dart run tool/probe.dart
///   dart run tool/probe.dart --host 192.168.1.20 --port 47821
///   dart run tool/probe.dart --timeout 5
Future<void> main(List<String> args) async {
  final host = _option(args, '--host');
  final port =
      int.tryParse(_option(args, '--port') ?? '') ?? JScanDefaults.port;
  final timeoutSeconds = int.tryParse(_option(args, '--timeout') ?? '') ?? 3;

  if (host != null) {
    await _probe(host, port);
    return;
  }

  stdout.writeln('Buscando PCs J-SCAN en la red local...');
  final browser = MdnsBrowser();
  await browser.start();

  try {
    final peers = await browser.refresh(
      timeout: Duration(seconds: timeoutSeconds),
    );
    if (peers.isEmpty) {
      stderr.writeln('No se encontró ninguna PC con J-SCAN.');
      stderr.writeln(
        'Comprueba que la app de escritorio esté abierta y en la misma red, '
        'o usa --host <ip>.',
      );
      exitCode = 1;
      return;
    }

    stdout.writeln('Encontradas ${peers.length}:');
    for (final peer in peers) {
      stdout.writeln(
        '  • ${peer.name} — ${peer.address}:${peer.port} '
        '(proto ${peer.protocolVersion})',
      );
    }

    var failures = 0;
    for (final peer in peers) {
      if (!peer.isCompatible) {
        stderr.writeln(
          'Saltando ${peer.name}: protocolo ${peer.protocolVersion} '
          'no compatible con ${JScanDefaults.protocolVersion}.',
        );
        continue;
      }
      final ok = await _probe(
        peer.connectHost,
        peer.port,
        displayName: peer.name,
      );
      if (!ok) failures += 1;
    }
    if (failures > 0) exitCode = 1;
  } finally {
    await browser.stop();
  }
}

Future<bool> _probe(String host, int port, {String? displayName}) async {
  final label = displayName ?? '$host:$port';
  stdout.writeln('Conectando con $label...');

  JScanClient? client;
  try {
    client = await JScanClient.connect(
      host: host,
      port: port,
      timeout: const Duration(seconds: 5),
    );
    final server = client.serverInfo;
    stdout.writeln(
      '  hello_ack: ${server?.name ?? '?'} '
      '(${server?.platform ?? '?'}), protocolo ${client.protocolVersion}',
    );

    for (var i = 1; i <= 3; i++) {
      final rtt = await client.ping();
      stdout.writeln('  ping $i: ${rtt.inMilliseconds} ms');
    }

    stdout.writeln('OK: la PC respondió.');
    return true;
  } catch (error) {
    stderr.writeln('Fallo al conectar con $label: $error');
    return false;
  } finally {
    await client?.close();
  }
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

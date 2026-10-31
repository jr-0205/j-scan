import 'dart:async';
import 'dart:io';

import 'package:jscan_core/jscan_core.dart';

/// Busca PCs J-SCAN con mDNS y, con un código de emparejamiento, mide el RTT
/// de un ping cifrado.
///
/// Uso:
///   dart run tool/probe.dart --pair-code "jscan://pair?d=..."
///   dart run tool/probe.dart
///   dart run tool/probe.dart --timeout 5
///
/// El código de emparejamiento se copia desde el QR que muestra la app de la PC
/// (botón «Copiar código»). La primera vez la PC pedirá confirmación.
Future<void> main(List<String> args) async {
  final codeText = _option(args, '--pair-code');
  final timeoutSeconds = int.tryParse(_option(args, '--timeout') ?? '') ?? 3;
  final identity = await _probeIdentity();

  if (codeText != null) {
    final ok = await _pairAndProbe(
      codeText,
      identity,
      const DeviceInfo(
        id: 'jscan-probe',
        name: 'J-SCAN CLI',
        platform: 'cli',
      ),
    );
    if (!ok) exitCode = 1;
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
        'Comprueba que la app de escritorio esté abierta y en la misma red.',
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

    stdout.writeln('');
    stdout.writeln(
      'Sprint 2 exige emparejamiento. Abre «Emparejar dispositivo» en la PC, '
      'copia el código y ejecuta:',
    );
    stdout.writeln(
      '  dart run tool/probe.dart --pair-code "<código>"',
    );
  } finally {
    await browser.stop();
  }
}

Future<bool> _pairAndProbe(
  String codeText,
  LocalIdentity identity,
  DeviceInfo device,
) async {
  final PairingCode code;
  try {
    code = PairingCode.decode(codeText);
  } catch (error) {
    stderr.writeln('Código de emparejamiento inválido: $error');
    return false;
  }

  if (code.isExpired()) {
    stderr.writeln('El código caducó; genera uno nuevo en la PC.');
    return false;
  }

  stdout.writeln(
    'Emparejando con ${code.serverName} (${code.host}:${code.port})...',
  );

  JScanClient? client;
  try {
    final pairing = await JScanClient.pair(
      code: code,
      identity: identity,
      device: device,
    );
    stdout.writeln('  Emparejado. La PC guardó este dispositivo.');

    client = await JScanClient.connectPaired(
      server: pairing.server,
      identity: identity,
      device: device,
    );
    stdout.writeln(
      '  auth_ok: ${client.serverInfo?.name ?? '?'} '
      '(${client.serverInfo?.platform ?? '?'}), cifrado activo',
    );

    for (var i = 1; i <= 3; i++) {
      final rtt = await client.ping();
      stdout.writeln('  ping $i: ${rtt.inMilliseconds} ms');
    }

    stdout.writeln('OK: la PC respondió con mensajes cifrados.');
    return true;
  } catch (error) {
    stderr.writeln('Fallo: $error');
    return false;
  } finally {
    await client?.close();
  }
}

Future<LocalIdentity> _probeIdentity() async {
  final file = File('.dart_tool/jscan_probe_identity.json');
  return LocalIdentityFile(file).loadOrCreate();
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

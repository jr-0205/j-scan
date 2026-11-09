import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';

import '../discovery_controller.dart';
import '../widgets/probe_result_view.dart';
import 'pair_code_dialog.dart';
import 'paired_servers_screen.dart';
import 'qr_scan_screen.dart';
import 'scan_screen.dart';
import 'send_file_screen.dart';
import 'send_text_screen.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key, required this.controller});

  final DiscoveryController controller;

  Future<void> _scanQr(BuildContext context) async {
    final server = await QrScanScreen.open(context, controller: controller);
    if (!context.mounted || server == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${server.name} emparejada. A partir de ahora los mensajes van cifrados.',
        ),
      ),
    );
  }

  Future<void> _pasteCode(BuildContext context) async {
    final server = await PairCodeDialog.show(
      context,
      controller: controller,
    );
    if (!context.mounted || server == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${server.name} emparejada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scanning = controller.status == ScanStatus.scanning;
        final paired = controller.pairedServers;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: <Widget>[
                Icon(Icons.sensors),
                SizedBox(width: 10),
                Text('J-SCAN'),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Escanear documento',
                onPressed: () =>
                    ScanScreen.open(context, discovery: controller),
                icon: const Icon(Icons.document_scanner_outlined),
              ),
              if (paired.isNotEmpty) ...<Widget>[
                IconButton(
                  tooltip: 'Enviar archivos',
                  onPressed: () => SendFileScreen.open(
                    context,
                    controller: controller,
                  ),
                  icon: const Icon(Icons.upload_file),
                ),
                IconButton(
                  tooltip: 'Enviar texto',
                  onPressed: () => SendTextScreen.open(
                    context,
                    controller: controller,
                  ),
                  icon: const Icon(Icons.send_outlined),
                ),
              ],
              IconButton(
                tooltip: 'PCs emparejadas',
                onPressed: () => PairedServersScreen.open(
                  context,
                  controller: controller,
                ),
                icon: Badge(
                  isLabelVisible: paired.isNotEmpty,
                  label: Text('${paired.length}'),
                  child: const Icon(Icons.verified_user_outlined),
                ),
              ),
              IconButton(
                tooltip: 'Buscar PCs',
                onPressed: scanning ? null : () => controller.scan(),
                icon: scanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: controller.scan,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const _IntroCard(),
                const SizedBox(height: 12),
                _StatusBar(controller: controller),
                const SizedBox(height: 12),
                if (!controller.ready)
                  const _PreparingCard()
                else ...<Widget>[
                  _PairingActionsCard(
                    onScan: () => _scanQr(context),
                    onPaste: () => _pasteCode(context),
                  ),
                  const SizedBox(height: 12),
                  _ScanCard(
                    onOpen: () =>
                        ScanScreen.open(context, discovery: controller),
                  ),
                  if (paired.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _SendFilesCard(controller: controller),
                    const SizedBox(height: 12),
                    _SendTextCard(controller: controller),
                    const SizedBox(height: 12),
                    _PairedSummaryCard(
                      controller: controller,
                      onOpen: () => PairedServersScreen.open(
                        context,
                        controller: controller,
                      ),
                    ),
                  ],
                  if (controller.pendingSharedText != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _SharedTextCard(controller: controller),
                  ],
                  if (controller.pendingSharedFiles.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _SharedFilesCard(controller: controller),
                  ],
                  const SizedBox(height: 20),
                  _PeersHeader(count: controller.peers.length),
                  const SizedBox(height: 8),
                  if (controller.peers.isEmpty)
                    _EmptyState(controller: controller)
                  else
                    ...controller.peers.map(
                      (peer) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PeerCard(
                          peer: peer,
                          controller: controller,
                          onPair: () => _scanQr(context),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Sprint 5 · escáner con detección de bordes, corrección de '
                  'perspectiva, varias páginas, rotación, orden y filtros. '
                  'El cifrado y la reanudación del Sprint 4 siguen activos.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.wifi, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Misma red Wi-Fi',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Abre J-SCAN en la PC y conecta el celular a la misma red. '
                    'El descubrimiento usa mDNS y el emparejamiento se hace '
                    'una sola vez por PC.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreparingCard extends StatelessWidget {
  const _PreparingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Preparando la identidad segura…')),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanning = controller.status == ScanStatus.scanning;
    final error = controller.status == ScanStatus.error ||
        controller.errorMessage != null;

    final label = scanning
        ? 'Buscando PCs en la red…'
        : error
            ? controller.errorMessage ?? 'Error de descubrimiento'
            : controller.lastScan == null
                ? 'Aún no se ha buscado'
                : 'Última búsqueda: ${_formatTime(controller.lastScan!)}';

    return Row(
      children: <Widget>[
        if (scanning)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: error ? theme.colorScheme.error : Colors.green,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: error ? theme.colorScheme.error : null,
            ),
          ),
        ),
        Text(
          '${controller.peers.length} PC'
          '${controller.peers.length == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PairingActionsCard extends StatelessWidget {
  const _PairingActionsCard({
    required this.onScan,
    required this.onPaste,
  });

  final VoidCallback onScan;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.qr_code_2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Emparejar con la PC',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'En la PC pulsa «Emparejar dispositivo». Escanea el QR o pega '
              'el código; la PC te pedirá confirmación antes de autorizar '
              'este celular.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Escanear QR'),
                ),
                OutlinedButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Pegar código'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(
          Icons.document_scanner_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Escanear documento'),
        subtitle: const Text(
          'Detecta los bordes, corrige la perspectiva y permite varias páginas '
          'con filtros. No necesita una PC emparejada.',
        ),
        trailing: FilledButton.tonal(
          onPressed: onOpen,
          child: const Text('Abrir'),
        ),
      ),
    );
  }
}

class _PairedSummaryCard extends StatelessWidget {
  const _PairedSummaryCard({
    required this.controller,
    required this.onOpen,
  });

  final DiscoveryController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final servers = controller.pairedServers;
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          Icons.verified_user,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        title: Text(
          '${servers.length} PC'
          '${servers.length == 1 ? '' : 's'} emparejada'
          '${servers.length == 1 ? '' : 's'}',
          style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
        ),
        subtitle: Text(
          servers.map((server) => server.name).join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
        ),
        trailing: TextButton(
          onPressed: onOpen,
          child: const Text('Ver'),
        ),
      ),
    );
  }
}

class _SendTextCard extends StatelessWidget {
  const _SendTextCard({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = controller.pairedServers.first;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(Icons.send, color: theme.colorScheme.primary),
        title: const Text('Texto y portapapeles'),
        subtitle: Text(
          'Envía un mensaje o lo que tengas copiado a ${target.name}.',
        ),
        trailing: FilledButton.tonal(
          onPressed: () => SendTextScreen.open(context, controller: controller),
          child: const Text('Abrir'),
        ),
      ),
    );
  }
}

class _SendFilesCard extends StatelessWidget {
  const _SendFilesCard({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = controller.pairedServers.first;
    final active = controller.activeFileTransfers;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(Icons.upload_file, color: theme.colorScheme.primary),
        title: const Text('Archivos, fotos y videos'),
        subtitle: Text(
          active > 0
              ? '$active transferencia${active == 1 ? '' : 's'} en curso '
                  'hacia $target.name.'
              : 'Envía varios archivos con progreso y reanudación a '
                  '${target.name}.',
        ),
        trailing: FilledButton.tonal(
          onPressed: () => SendFileScreen.open(context, controller: controller),
          child: Text(active > 0 ? 'Ver' : 'Abrir'),
        ),
      ),
    );
  }
}

class _SharedFilesCard extends StatelessWidget {
  const _SharedFilesCard({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = controller.pendingSharedFiles;
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.ios_share,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${paths.length} archivo${paths.length == 1 ? '' : 's'} '
                    'compartido${paths.length == 1 ? '' : 's'} desde otra app',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              paths.take(3).map(_fileName).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: () {
                    final pending = List<String>.of(paths);
                    controller.clearPendingSharedFiles();
                    SendFileScreen.open(
                      context,
                      controller: controller,
                      initialPaths: pending,
                    );
                  },
                  child: const Text('Elegir PC y enviar'),
                ),
                TextButton(
                  onPressed: controller.clearPendingSharedFiles,
                  child: const Text('Descartar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _fileName(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.isEmpty ? path : parts.last;
}

class _SharedTextCard extends StatelessWidget {
  const _SharedTextCard({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = controller.pendingSharedText ?? '';
    final preview = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.ios_share,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Texto compartido desde otra app',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preview.length > 160 ? '${preview.substring(0, 160)}…' : preview,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: () {
                    final pending = controller.pendingSharedText;
                    controller.clearPendingSharedText();
                    SendTextScreen.open(
                      context,
                      controller: controller,
                      initialText: pending,
                    );
                  },
                  child: const Text('Elegir PC y enviar'),
                ),
                TextButton(
                  onPressed: controller.clearPendingSharedText,
                  child: const Text('Descartar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeersHeader extends StatelessWidget {
  const _PeersHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text('PCs en la red', style: theme.textTheme.titleSmall),
        const Spacer(),
        Text(
          '$count encontrada${count == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.desktop_access_disabled,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No se encontró ninguna PC',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Comprueba que la PC tenga J-SCAN abierto, que ambas estén en '
              'la misma red y que el firewall permita UDP 5353 y TCP 47821. '
              'También puedes emparejar pegando el código.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.status == ScanStatus.scanning
                  ? null
                  : () => controller.scan(),
              icon: const Icon(Icons.search),
              label: const Text('Buscar PC'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.peer,
    required this.controller,
    required this.onPair,
  });

  final DiscoveredPeer peer;
  final DiscoveryController controller;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.resultFor(peer);
    final probing = controller.isProbing(peer);
    final paired = controller.serverForPeer(peer);
    final canPair = peer.isCompatible && !probing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: paired != null
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  paired != null ? Icons.lock : Icons.computer,
                  color: paired != null
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              title: Text(peer.name),
              subtitle: Text(
                '${peer.connectHost}:${peer.port} · '
                'protocolo ${peer.protocolVersion}'
                '${paired == null ? ' · sin emparejar' : ' · emparejada'}',
              ),
              trailing: paired == null
                  ? FilledButton(
                      onPressed: canPair ? onPair : null,
                      child: const Text('Emparejar'),
                    )
                  : FilledButton.tonal(
                      onPressed: canPair ? () => controller.probe(peer) : null,
                      child: probing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Conectar'),
                    ),
            ),
            if (!peer.isCompatible)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Text(
                  'Versión incompatible: actualiza J-SCAN en esta PC.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (paired != null && result == null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Text(
                  'Toca «Conectar» para autenticar y medir el ping cifrado.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8),
                child: ProbeResultView(result: result),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

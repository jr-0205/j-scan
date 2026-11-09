import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

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
            title: const JScanBrand(subtitle: 'Android · red local'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Escanear documento',
                onPressed: () =>
                    ScanScreen.open(context, discovery: controller),
                icon: const Icon(Icons.document_scanner_outlined),
              ),
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
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: controller.scan,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: JScanMetrics.pagePadding,
                children: <Widget>[
                  _ConnectionHeader(controller: controller),
                  const SizedBox(height: 14),
                  if (!controller.ready)
                    const _PreparingPanel()
                  else ...<Widget>[
                    _PairingPanel(
                      onScan: () => _scanQr(context),
                      onPaste: () => _pasteCode(context),
                    ),
                    const SizedBox(height: 12),
                    JScanActionTile(
                      icon: Icons.document_scanner_outlined,
                      title: 'Escanear documento',
                      subtitle:
                          'Detecta los bordes, corrige la perspectiva y permite '
                          'varias páginas con filtros. No necesita una PC '
                          'emparejada.',
                      trailingLabel: 'Abrir',
                      tone: JScanTone.info,
                      onTap: () =>
                          ScanScreen.open(context, discovery: controller),
                    ),
                    if (paired.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      JScanSectionLabel(
                        label: 'Envío rápido',
                        trailing: Text(
                          '${paired.length} PC'
                          '${paired.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      JScanActionTile(
                        icon: Icons.send_outlined,
                        title: 'Texto y portapapeles',
                        subtitle: 'Envía un mensaje o lo que tengas copiado a '
                            '${paired.first.name}.',
                        trailingLabel: 'Abrir',
                        onTap: () => SendTextScreen.open(
                          context,
                          controller: controller,
                        ),
                      ),
                      const SizedBox(height: 10),
                      JScanActionTile(
                        icon: Icons.upload_file,
                        title: 'Archivos, fotos y videos',
                        subtitle: controller.activeFileTransfers > 0
                            ? '${controller.activeFileTransfers} '
                                'transferencia'
                                '${controller.activeFileTransfers == 1 ? '' : 's'} '
                                'en curso hacia ${paired.first.name}.'
                            : 'Envía varios archivos con progreso y '
                                'reanudación a ${paired.first.name}.',
                        meta: controller.activeFileTransfers > 0
                            ? '${controller.activeFileTransfers} activa'
                                '${controller.activeFileTransfers == 1 ? '' : 's'}'
                            : null,
                        trailingLabel: controller.activeFileTransfers > 0
                            ? 'Ver'
                            : 'Abrir',
                        onTap: () => SendFileScreen.open(
                          context,
                          controller: controller,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PairedSummaryPanel(
                        controller: controller,
                        onOpen: () => PairedServersScreen.open(
                          context,
                          controller: controller,
                        ),
                      ),
                    ],
                    if (controller.pendingSharedText != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _SharedTextPanel(controller: controller),
                    ],
                    if (controller.pendingSharedFiles.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _SharedFilesPanel(controller: controller),
                    ],
                    const SizedBox(height: 24),
                    _PeersHeader(
                      count: controller.peers.length,
                      scanning: scanning,
                    ),
                    const SizedBox(height: 8),
                    if (controller.peers.isEmpty)
                      _EmptyState(controller: controller)
                    else
                      ...controller.peers.map(
                        (peer) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PeerCard(
                            peer: peer,
                            controller: controller,
                            onPair: () => _scanQr(context),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Escáner con detección de bordes, corrección de perspectiva, '
                    'varias páginas, rotación, orden y filtros. Los envíos van '
                    'cifrados y se reanudan si el Wi-Fi se corta.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: JScanColors.textMuted,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanning = controller.status == ScanStatus.scanning;
    final error = controller.status == ScanStatus.error ||
        controller.errorMessage != null;

    final (JScanTone tone, String label) = scanning
        ? (JScanTone.info, 'Buscando PCs…')
        : error
            ? (JScanTone.danger, 'Revisa la conexión')
            : controller.lastScan == null
                ? (JScanTone.neutral, 'Listo')
                : (JScanTone.success, 'Red revisada');

    final detail = scanning
        ? 'Buscando PCs en la red…'
        : error
            ? controller.errorMessage ?? 'Error de descubrimiento'
            : controller.lastScan == null
                ? 'Aún no se ha buscado'
                : 'Última búsqueda: ${_formatTime(controller.lastScan!)}';

    return JScanPanel(
      padding: const EdgeInsets.all(18),
      accent: scanning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: JScanStatusPill(
                    label: label,
                    tone: tone,
                    busy: scanning,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${controller.peers.length} PC'
                '${controller.peers.length == 1 ? '' : 's'}',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Misma red Wi-Fi',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Abre J-SCAN en la PC y conecta el celular a la misma red. '
            'El descubrimiento usa mDNS y el emparejamiento se hace una sola '
            'vez por PC.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: scanning ? null : () => controller.scan(),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar PCs'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: error ? JScanColors.danger : JScanColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreparingPanel extends StatelessWidget {
  const _PreparingPanel();

  @override
  Widget build(BuildContext context) {
    return JScanPanel(
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Preparando la identidad segura…',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Se generan las claves del dispositivo antes de permitir '
                  'envíos cifrados.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingPanel extends StatelessWidget {
  const _PairingPanel({
    required this.onScan,
    required this.onPaste,
  });

  final VoidCallback onScan;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JScanSection(
      icon: Icons.qr_code_2,
      title: 'Emparejar con la PC',
      subtitle: 'Una sola vez por PC. La PC confirma antes de autorizar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Escanear QR'),
              ),
              OutlinedButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.keyboard, size: 18),
                label: const Text('Pegar código'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PairedSummaryPanel extends StatelessWidget {
  const _PairedSummaryPanel({
    required this.controller,
    required this.onOpen,
  });

  final DiscoveryController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final servers = controller.pairedServers;
    return JScanPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: <Widget>[
          const JScanIconBadge(
            icon: Icons.verified_user_outlined,
            tone: JScanTone.success,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${servers.length} PC'
                  '${servers.length == 1 ? '' : 's'} emparejada'
                  '${servers.length == 1 ? '' : 's'}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  servers.map((server) => server.name).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onOpen,
            child: const Text('Ver'),
          ),
        ],
      ),
    );
  }
}

class _SharedFilesPanel extends StatelessWidget {
  const _SharedFilesPanel({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = controller.pendingSharedFiles;
    return JScanPanel(
      color: JScanTone.info.surface,
      borderColor: JScanTone.info.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const JScanIconBadge(
                icon: Icons.ios_share,
                tone: JScanTone.info,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${paths.length} archivo${paths.length == 1 ? '' : 's'} '
                  'compartido${paths.length == 1 ? '' : 's'} desde otra app',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            paths.take(3).map(_fileName).join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
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
    );
  }
}

String _fileName(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.isEmpty ? path : parts.last;
}

class _SharedTextPanel extends StatelessWidget {
  const _SharedTextPanel({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = controller.pendingSharedText ?? '';
    final preview = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return JScanPanel(
      color: JScanTone.info.surface,
      borderColor: JScanTone.info.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const JScanIconBadge(
                icon: Icons.ios_share,
                tone: JScanTone.info,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Texto compartido desde otra app',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preview.length > 160 ? '${preview.substring(0, 160)}…' : preview,
            style: theme.textTheme.bodyMedium,
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
    );
  }
}

class _PeersHeader extends StatelessWidget {
  const _PeersHeader({required this.count, required this.scanning});

  final int count;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JScanSectionLabel(
      label: 'PCs en la red',
      trailing: Text(
        scanning ? 'Buscando…' : '$count encontrada${count == 1 ? '' : 's'}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: JScanColors.textMuted,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    return JScanEmptyState(
      icon: Icons.desktop_access_disabled,
      title: 'No se encontró ninguna PC',
      message:
          'Comprueba que la PC tenga J-SCAN abierto, que ambas estén en la '
          'misma red y que el firewall permita UDP 5353 y TCP 47821. '
          'También puedes emparejar pegando el código.',
      action: FilledButton.icon(
        onPressed: controller.status == ScanStatus.scanning
            ? null
            : () => controller.scan(),
        icon: const Icon(Icons.search, size: 18),
        label: const Text('Buscar PC'),
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

    return JScanPanel(
      accent: paired != null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              JScanIconBadge(
                icon: paired != null ? Icons.lock_outline : Icons.computer,
                tone: paired != null ? JScanTone.success : JScanTone.neutral,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            peer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        JScanStatusPill(
                          label:
                              paired == null ? 'Sin emparejar' : 'Autorizada',
                          tone: paired == null
                              ? JScanTone.neutral
                              : JScanTone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${peer.connectHost}:${peer.port} · '
                      'protocolo ${peer.protocolVersion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: JScanColors.textMuted,
                        fontFamily: 'Consolas',
                        fontFamilyFallback: const <String>['monospace'],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              if (paired == null)
                FilledButton.icon(
                  onPressed: canPair ? onPair : null,
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Emparejar'),
                )
              else
                OutlinedButton.icon(
                  onPressed: canPair ? () => controller.probe(peer) : null,
                  icon: probing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open, size: 18),
                  label: Text(probing ? 'Conectando…' : 'Conectar'),
                ),
              const Spacer(),
              if (!peer.isCompatible)
                Flexible(
                  child: Text(
                    'Versión incompatible: actualiza J-SCAN en esta PC.',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: JScanColors.danger,
                    ),
                  ),
                ),
            ],
          ),
          if (paired != null && result == null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Toca «Conectar» para autenticar y medir el ping cifrado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: JScanColors.textMuted,
              ),
            ),
          ],
          if (result != null) ...<Widget>[
            const SizedBox(height: 10),
            ProbeResultView(result: result),
          ],
        ],
      ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

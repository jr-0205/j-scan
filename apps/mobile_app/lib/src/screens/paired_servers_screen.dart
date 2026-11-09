import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

import '../discovery_controller.dart';
import '../widgets/probe_result_view.dart';
import 'qr_scan_screen.dart';

/// Lista de PCs autorizadas en este celular.
class PairedServersScreen extends StatelessWidget {
  const PairedServersScreen({super.key, required this.controller});

  final DiscoveryController controller;

  static Future<void> open(
    BuildContext context, {
    required DiscoveryController controller,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => PairedServersScreen(controller: controller),
      ),
    );
  }

  Future<void> _addServer(BuildContext context) async {
    final server = await QrScanScreen.open(context, controller: controller);
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
        final servers = controller.pairedServers;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('PCs emparejadas'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Emparejar otra PC',
                onPressed: () => _addServer(context),
                icon: const Icon(Icons.qr_code_scanner),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: JScanMetrics.pagePadding,
              children: <Widget>[
                if (servers.isEmpty)
                  JScanEmptyState(
                    icon: Icons.phonelink_erase,
                    title: 'Todavía no hay PCs emparejadas',
                    message:
                        'Abre «Emparejar dispositivo» en la PC y escanea el QR '
                        'con este celular. La PC pedirá confirmación.',
                    action: FilledButton.icon(
                      onPressed: () => _addServer(context),
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: const Text('Escanear QR'),
                    ),
                  )
                else ...<Widget>[
                  Text(
                    'Este celular solo puede enviar mensajes a estas PCs. '
                    'La PC también puede revocar el acceso en cualquier momento.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  ...servers.map(
                    (server) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ServerPanel(
                        server: server,
                        controller: controller,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ServerPanel extends StatelessWidget {
  const _ServerPanel({required this.server, required this.controller});

  final PairedServer server;
  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.resultForServer(server);
    final probing = controller.isProbingServer(server);
    final shortId = server.serverId.length > 8
        ? server.serverId.substring(0, 8)
        : server.serverId;

    return JScanPanel(
      accent: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const JScanIconBadge(
                icon: Icons.computer,
                tone: JScanTone.success,
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
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const JScanStatusPill(
                          label: 'Autorizada',
                          tone: JScanTone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'emparejada ${_formatDate(server.pairedAt)}'
                      '${server.lastSeenAt == null ? '' : ' · vista ${_formatDate(server.lastSeenAt!)}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: JScanColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => _confirmRemoval(context),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          JScanCodeBlock(
            value: '${server.host}:${server.port}',
            maxLines: 1,
            trailing: JScanStatusPill(
              label: 'ID $shortId',
              tone: JScanTone.neutral,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed:
                    probing ? null : () => controller.probeServer(server),
                icon: probing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open, size: 18),
                label: Text(probing ? 'Conectando…' : 'Probar conexión'),
              ),
            ],
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 10),
            ProbeResultView(result: result),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemoval(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Olvidar PC'),
        content: Text(
          '¿Quitar ${server.name} de este celular? Para volver a usarla '
          'tendrás que escanear un QR nuevo en la PC.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeServer(server);
    }
  }
}

String _formatDate(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} '
      '${two(time.hour)}:${two(time.minute)}';
}

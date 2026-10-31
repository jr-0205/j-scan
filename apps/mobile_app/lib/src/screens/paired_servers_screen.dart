import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';

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
        return Scaffold(
          appBar: AppBar(
            title: const Text('PCs emparejadas'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Emparejar otra PC',
                onPressed: () => _addServer(context),
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (servers.isEmpty)
                _EmptyServers(onAdd: () => _addServer(context))
              else ...<Widget>[
                Text(
                  'Este celular solo puede enviar mensajes a estas PCs. '
                  'La PC también puede revocar el acceso en cualquier momento.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ...servers.map(
                  (server) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ServerCard(
                      server: server,
                      controller: controller,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.phonelink_erase,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Todavía no hay PCs emparejadas',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Abre «Emparejar dispositivo» en la PC y escanea el QR con este '
              'celular. La PC pedirá confirmación.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear QR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server, required this.controller});

  final PairedServer server;
  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.resultForServer(server);
    final probing = controller.isProbingServer(server);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.computer,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(server.name),
              subtitle: Text(
                '${server.host}:${server.port} · '
                'emparejada ${_formatDate(server.pairedAt)}'
                '${server.lastSeenAt == null ? '' : ' · vista ${_formatDate(server.lastSeenAt!)}'}',
              ),
              trailing: IconButton(
                tooltip: 'Eliminar',
                onPressed: () => _confirmRemoval(context),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
            Row(
              children: <Widget>[
                FilledButton.tonalIcon(
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
                const SizedBox(width: 8),
                Text(
                  'ID ${server.serverId}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ProbeResultView(result: result),
              ),
          ],
        ),
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

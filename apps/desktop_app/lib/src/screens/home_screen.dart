import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jscan_core/jscan_core.dart';

import '../server_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              children: <Widget>[
                Icon(
                  Icons.sensors,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Text('J-SCAN'),
                const SizedBox(width: 12),
                Text(
                  'Servidor local',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  if (controller.status == ServerStatus.error)
                    _ErrorCard(controller: controller),
                  _StatusCard(controller: controller),
                  const SizedBox(height: 16),
                  _DevicesCard(controller: controller),
                  const SizedBox(height: 16),
                  _ActivityCard(controller: controller),
                  const SizedBox(height: 16),
                  const _SprintNote(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.status == ServerStatus.running;
    final starting = controller.status == ServerStatus.starting;
    final color = running
        ? Colors.green
        : starting
            ? Colors.orange
            : theme.colorScheme.error;

    final address = '${controller.addressLabel}:${controller.port}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.circle, size: 12, color: color),
                const SizedBox(width: 8),
                Text(
                  running
                      ? 'Servidor activo'
                      : starting
                          ? 'Iniciando…'
                          : controller.status == ServerStatus.error
                              ? 'Servidor detenido'
                              : 'Detenido',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Chip(
                  avatar: Icon(
                    running ? Icons.wifi_tethering : Icons.wifi_off,
                    size: 16,
                  ),
                  label: Text(running ? 'mDNS activo' : 'mDNS inactivo'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Esta PC', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(controller.displayName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    address,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const <String>['monospace'],
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Copiar dirección',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: address));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Dirección copiada'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ID ${controller.serverId} · protocolo '
              '${JScanDefaults.protocolVersion}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.qr_code_2, size: 56),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Emparejamiento',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'El QR con la clave llegará en el Sprint 2. '
                        'Por ahora el celular puede descubrir esta PC y '
                        'probar la conexión.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicesCard extends StatelessWidget {
  const _DevicesCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final sessions = controller.sessions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.devices),
                const SizedBox(width: 8),
                Text(
                  'Dispositivos conectados',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Badge(label: Text('${sessions.length}')),
              ],
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              Text(
                'Ninguno todavía. Abre J-SCAN en el celular, conéctalo a la '
                'misma red y pulsa “Probar conexión”.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...sessions.map(
                (session) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.smartphone),
                  ),
                  title: Text(session.displayName),
                  subtitle: Text(
                    '${session.device?.platform ?? 'desconocido'} · '
                    'sesión ${session.id}',
                  ),
                  trailing: Text(_formatTime(session.connectedAt)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.recentActivity;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.receipt_long),
                const SizedBox(width: 8),
                Text(
                  'Actividad',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                'Sin actividad por ahora.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _formatTime(entry.time),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: const <String>['monospace'],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(entry.message)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                controller.errorMessage ?? 'Error desconocido',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: controller.retry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SprintNote extends StatelessWidget {
  const _SprintNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Sprint 1 · conexión local. El cifrado y el emparejamiento llegan en el '
      'Sprint 2.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

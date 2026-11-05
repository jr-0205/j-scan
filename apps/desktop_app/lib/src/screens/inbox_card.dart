import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';

import '../server_controller.dart';

/// Bandeja de textos y portapapeles recibidos (Sprint 3).
class InboxCard extends StatelessWidget {
  const InboxCard({super.key, required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = controller.history;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.mark_email_unread_outlined),
                const SizedBox(width: 8),
                Text(
                  'Textos y portapapeles',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Badge(label: Text('${entries.length}')),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: controller.copyToClipboard,
              onChanged: (value) => controller.setCopyToClipboard(value),
              title: const Text('Copiar automáticamente al portapapeles'),
              subtitle: const Text(
                'El último texto recibido queda listo para pegar en Windows.',
              ),
            ),
            const Divider(height: 24),
            if (entries.isEmpty)
              Text(
                'Aún no hay mensajes. Desde el celular abre «Enviar texto» o '
                'comparte un enlace con J-SCAN.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...entries.take(20).map(
                    (entry) => _HistoryTile(
                      controller: controller,
                      entry: entry,
                    ),
                  ),
            if (entries.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => controller.copyEntry(entries.first),
                    icon: const Icon(Icons.content_copy),
                    label: const Text('Copiar último'),
                  ),
                  TextButton.icon(
                    onPressed: controller.clearHistory,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Vaciar historial'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.controller, required this.entry});

  final ServerController controller;
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClipboard = entry.kind == HistoryKind.clipboard;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: isClipboard
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.secondaryContainer,
        child: Icon(
          isClipboard ? Icons.content_paste : Icons.notes,
          color: isClipboard
              ? theme.colorScheme.onTertiaryContainer
              : theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(
        entry.preview(max: 180),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.fromDeviceName ?? 'Dispositivo'} · '
        '${isClipboard ? 'portapapeles' : 'texto'} · '
        '${_formatDate(entry.receivedAt)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Copiar al portapapeles',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await controller.copyEntry(entry);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copiado al portapapeles'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Eliminar del historial',
            icon: const Icon(Icons.close),
            onPressed: () => controller.deleteHistoryEntry(entry),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)} ${two(time.hour)}:${two(time.minute)}';
}

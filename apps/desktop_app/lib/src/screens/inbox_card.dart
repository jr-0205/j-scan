import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

import '../server_controller.dart';

/// Bandeja de textos y portapapeles recibidos (Sprint 3).
class InboxCard extends StatelessWidget {
  const InboxCard({super.key, required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = controller.history;
    return JScanSection(
      icon: Icons.mark_email_unread_outlined,
      title: 'Textos y portapapeles',
      subtitle: 'Lo último que llegó desde el celular, listo para usar.',
      trailing: JScanStatusPill(
        label: '${entries.length}',
        tone: entries.isEmpty ? JScanTone.neutral : JScanTone.info,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: controller.copyToClipboard,
            onChanged: (value) => controller.setCopyToClipboard(value),
            title: const Text('Copiar automáticamente al portapapeles'),
            subtitle: Text(
              'El último texto recibido queda listo para pegar en Windows.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: JScanColors.textMuted,
              ),
            ),
          ),
          const Divider(height: 20),
          if (entries.isEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.inbox_outlined,
                  size: 18,
                  color: JScanColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aún no hay mensajes. Desde el celular abre «Enviar texto» '
                    'o comparte un enlace con J-SCAN.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: JScanColors.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          else
            ...entries.take(20).map(
                  (entry) => _HistoryRow(
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
                  icon: const Icon(Icons.content_copy, size: 17),
                  label: const Text('Copiar último'),
                ),
                TextButton.icon(
                  onPressed: controller.clearHistory,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                  label: const Text('Vaciar historial'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.controller, required this.entry});

  final ServerController controller;
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClipboard = entry.kind == HistoryKind.clipboard;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              JScanIconBadge(
                icon: isClipboard ? Icons.content_paste : Icons.notes,
                tone: isClipboard ? JScanTone.info : JScanTone.neutral,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.preview(max: 180),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.fromDeviceName ?? 'Dispositivo'} · '
                      '${isClipboard ? 'portapapeles' : 'texto'} · '
                      '${_formatDate(entry.receivedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: JScanColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copiar al portapapeles',
                icon: const Icon(Icons.copy, size: 18),
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
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => controller.deleteHistoryEntry(entry),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }
}

String _formatDate(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)} ${two(time.hour)}:${two(time.minute)}';
}

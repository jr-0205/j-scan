import 'package:flutter/material.dart';

import '../tokens.dart';
import 'jscan_panel.dart';

/// Accion principal mostrada como fila de superficie completa.
///
/// Se usa para las tareas de enviar texto/archivos y abrir el escaner, donde
/// una tarjeta con ListTile y boton interior anidaba demasiados niveles.
class JScanActionTile extends StatelessWidget {
  const JScanActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingLabel,
    this.tone = JScanTone.neutral,
    this.meta,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? trailingLabel;
  final JScanTone tone;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return Material(
      color: JScanColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JScanMetrics.radiusPanel),
        side: const BorderSide(color: JScanColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              JScanIconBadge(icon: icon, tone: tone, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: enabled
                                  ? JScanColors.textPrimary
                                  : JScanColors.textMuted,
                            ),
                          ),
                        ),
                        if (meta != null) ...<Widget>[
                          const SizedBox(width: 8),
                          Text(
                            meta!,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? JScanColors.textSecondary
                            : JScanColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingLabel != null) ...<Widget>[
                const SizedBox(width: 10),
                Text(
                  trailingLabel!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: enabled ? JScanColors.action : JScanColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: enabled ? JScanColors.textMuted : JScanColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

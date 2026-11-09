import 'package:flutter/material.dart';

import '../tokens.dart';

/// Indicador compacto de estado con punto de color.
class JScanStatusPill extends StatelessWidget {
  const JScanStatusPill({
    super.key,
    required this.label,
    this.tone = JScanTone.neutral,
    this.icon,
    this.busy = false,
  });

  final String label;
  final JScanTone tone;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (busy)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: tone.color,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 13, color: tone.color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tone.color,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: tone.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de exito, error o informacion. Reemplaza las tarjetas de color
/// plano y mantiene el mensaje legible.
class JScanBanner extends StatelessWidget {
  const JScanBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = JScanTone.neutral,
    this.icon,
    this.action,
  });

  final String message;
  final String? title;
  final JScanTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final IconData resolved = icon ??
        switch (tone) {
          JScanTone.success => Icons.check_circle_outline,
          JScanTone.danger => Icons.error_outline,
          JScanTone.warning => Icons.warning_amber_outlined,
          JScanTone.info => Icons.info_outline,
          JScanTone.neutral => Icons.circle_outlined,
        };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(JScanMetrics.radius),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(resolved, size: 19, color: tone.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tone == JScanTone.neutral
                          ? JScanColors.textPrimary
                          : tone.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: JScanColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(width: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Fila de dato tecnico: etiqueta tenue y valor monoespaciado.
class JScanKeyValue extends StatelessWidget {
  const JScanKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.wrap = false,
  });

  final String label;
  final String value;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: JScanColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: wrap ? null : 2,
              overflow: wrap ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: const <String>[
                  'Cascadia Mono',
                  'Menlo',
                  'monospace',
                ],
                color: JScanColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Marca de J-SCAN para las barras superiores.
class JScanBrand extends StatelessWidget {
  const JScanBrand({
    super.key,
    this.subtitle,
    this.showSubtitle = true,
  });

  final String? subtitle;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: JScanColors.deepBlue.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: JScanColors.action.withValues(alpha: 0.42),
            ),
          ),
          child: const Icon(
            Icons.sensors,
            size: 18,
            color: JScanColors.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'J-SCAN',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  letterSpacing: 0.6,
                ),
              ),
              if (showSubtitle && subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: JScanColors.textMuted,
                    letterSpacing: 0.7,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bloque de codigo o direccion tecnica.
class JScanCodeBlock extends StatelessWidget {
  const JScanCodeBlock({
    super.key,
    required this.value,
    this.maxLines,
    this.trailing,
  });

  final String value;
  final int? maxLines;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: JScanColors.surface,
        borderRadius: BorderRadius.circular(JScanMetrics.radius),
        border: Border.all(color: JScanColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SelectableText(
              value,
              maxLines: maxLines,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: const <String>[
                  'Cascadia Mono',
                  'Menlo',
                  'monospace',
                ],
                color: JScanColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );
  }
}

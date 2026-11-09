import 'package:flutter/material.dart';

import '../tokens.dart';
import 'jscan_panel.dart';

/// Estado vacio con icono, explicacion y una accion principal.
class JScanEmptyState extends StatelessWidget {
  const JScanEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondaryAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondaryAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JScanPanel(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: compact ? 20 : 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: compact ? 48 : 60,
            height: compact ? 48 : 60,
            decoration: BoxDecoration(
              color: JScanColors.surface,
              borderRadius: BorderRadius.circular(compact ? 14 : 18),
              border: Border.all(color: JScanColors.border),
            ),
            child: Icon(
              icon,
              size: compact ? 24 : 28,
              color: JScanColors.textSecondary,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (action != null) ...<Widget>[
            SizedBox(height: compact ? 14 : 20),
            action!,
          ],
          if (secondaryAction != null) ...<Widget>[
            const SizedBox(height: 8),
            secondaryAction!,
          ],
        ],
      ),
    );
  }
}

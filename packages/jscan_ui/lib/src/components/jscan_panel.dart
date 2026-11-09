import 'package:flutter/material.dart';

import '../tokens.dart';

/// Superficie base de J-SCAN: grafito, borde de 1 px y radio consistente.
class JScanPanel extends StatelessWidget {
  const JScanPanel({
    super.key,
    required this.child,
    this.padding = JScanMetrics.panelPadding,
    this.margin,
    this.color,
    this.borderColor,
    this.radius = JScanMetrics.radiusPanel,
    this.accent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? JScanColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ??
              (accent
                  ? JScanColors.action.withValues(alpha: 0.42)
                  : JScanColors.border),
        ),
      ),
      // Material transparente para que ListTile e InkWell pinten sus efectos
      // sobre la superficie del panel en lugar de quedar ocultos por el fondo.
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}

/// Icono contenido en un cuadrado redondeado. Evita iconos sueltos sin
/// jerarquia sobre superficies grandes.
class JScanIconBadge extends StatelessWidget {
  const JScanIconBadge({
    super.key,
    required this.icon,
    this.tone = JScanTone.neutral,
    this.size = 36,
  });

  final IconData icon;
  final JScanTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color =
        tone == JScanTone.neutral ? JScanColors.textSecondary : tone.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: JScanColors.surface,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: tone == JScanTone.neutral ? JScanColors.border : tone.border,
        ),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Panel con cabecera: icono, titulo, descripcion opcional y accion a la
/// derecha. El contenido queda separado por un divisor sutil.
class JScanSection extends StatelessWidget {
  const JScanSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.tone = JScanTone.neutral,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
    this.accent = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? subtitle;
  final Widget? trailing;
  final JScanTone tone;
  final EdgeInsetsGeometry padding;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JScanPanel(
      padding: EdgeInsets.zero,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                JScanIconBadge(icon: icon, tone: tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
          const Divider(),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Etiqueta en mayusculas para separar bloques sin agregar otra tarjeta.
class JScanSectionLabel extends StatelessWidget {
  const JScanSectionLabel({
    super.key,
    required this.label,
    this.trailing,
  });

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              color: JScanColors.textMuted,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

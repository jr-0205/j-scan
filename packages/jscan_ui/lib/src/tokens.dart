import 'package:flutter/material.dart';

/// Paleta base de J-SCAN.
///
/// Superficies grafito, texto neutro y un único azul de accion. Los colores
/// semanticos se usan solo para estados, nunca como decoracion.
abstract final class JScanColors {
  static const Color background = Color(0xFF0A0A0B);
  static const Color surface = Color(0xFF111216);
  static const Color card = Color(0xFF191A1E);
  static const Color elevated = Color(0xFF22242A);
  static const Color border = Color(0xFF30323A);
  static const Color borderSubtle = Color(0xFF23252B);

  static const Color textPrimary = Color(0xFFF2F3F5);
  static const Color textSecondary = Color(0xFFA3A7B0);
  // Un poco más claro que el gris tenue de la guía para mantener contraste
  // AA en textos pequeños sobre las tarjetas grafito.
  static const Color textMuted = Color(0xFF8B919C);

  static const Color deepBlue = Color(0xFF254A7A);
  static const Color action = Color(0xFF4D8DDB);
  static const Color actionHover = Color(0xFF6AA1E4);
  static const Color actionPressed = Color(0xFF3F7BC2);
  static const Color silver = Color(0xFFB5BAC4);

  static const Color success = Color(0xFF5FB98C);
  static const Color warning = Color(0xFFD8A657);
  static const Color danger = Color(0xFFE06C75);
  static const Color info = action;
}

/// Radios, alturas y espaciados compartidos.
abstract final class JScanMetrics {
  static const double radiusSmall = 8;
  static const double radius = 10;
  static const double radiusPanel = 16;

  static const double controlHeight = 44;
  static const double touchTarget = 48;

  static const EdgeInsets panelPadding = EdgeInsets.all(18);
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 16, 16, 32);

  static const double maxContentWidth = 920;
}

/// Tono semantico de un aviso, una etiqueta o un icono.
enum JScanTone { neutral, info, success, warning, danger }

extension JScanToneColors on JScanTone {
  Color get color => switch (this) {
        JScanTone.neutral => JScanColors.textSecondary,
        JScanTone.info => JScanColors.info,
        JScanTone.success => JScanColors.success,
        JScanTone.warning => JScanColors.warning,
        JScanTone.danger => JScanColors.danger,
      };

  /// Fondo tenue derivado del tono sobre la superficie de tarjeta.
  Color get surface => Color.alphaBlend(
        color.withValues(alpha: 0.10),
        JScanColors.card,
      );

  Color get border => color.withValues(alpha: 0.32);
}

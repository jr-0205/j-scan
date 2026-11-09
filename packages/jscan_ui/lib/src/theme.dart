import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Tema oscuro unico de J-SCAN.
///
/// La app usa siempre este tema: no hay variante clara para evitar
/// inconsistencias de contraste entre Android y Windows.
abstract final class JScanTheme {
  static const ColorScheme _scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: JScanColors.action,
    onPrimary: JScanColors.background,
    primaryContainer: JScanColors.deepBlue,
    onPrimaryContainer: JScanColors.textPrimary,
    secondary: JScanColors.silver,
    onSecondary: JScanColors.background,
    secondaryContainer: JScanColors.elevated,
    onSecondaryContainer: JScanColors.textPrimary,
    tertiary: JScanColors.textSecondary,
    onTertiary: JScanColors.background,
    tertiaryContainer: JScanColors.surface,
    onTertiaryContainer: JScanColors.textPrimary,
    error: JScanColors.danger,
    onError: JScanColors.background,
    errorContainer: Color(0xFF2A181B),
    onErrorContainer: Color(0xFFF2C5C9),
    surface: JScanColors.background,
    onSurface: JScanColors.textPrimary,
    onSurfaceVariant: JScanColors.textSecondary,
    outline: JScanColors.border,
    outlineVariant: JScanColors.borderSubtle,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: JScanColors.textPrimary,
    onInverseSurface: JScanColors.background,
    inversePrimary: JScanColors.deepBlue,
    surfaceContainerLowest: JScanColors.background,
    surfaceContainerLow: JScanColors.surface,
    surfaceContainer: JScanColors.surface,
    surfaceContainerHigh: JScanColors.card,
    surfaceContainerHighest: JScanColors.elevated,
  );

  static const TextTheme _text = TextTheme(
    displaySmall: TextStyle(
      fontSize: 32,
      height: 1.12,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.8,
      color: JScanColors.textPrimary,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.6,
      color: JScanColors.textPrimary,
    ),
    headlineSmall: TextStyle(
      fontSize: 21,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: JScanColors.textPrimary,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: JScanColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: JScanColors.textPrimary,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: JScanColors.textPrimary,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: JScanColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontSize: 13.5,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: Color(0xFFC3C7CF),
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: JScanColors.textSecondary,
    ),
    labelLarge: TextStyle(
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: JScanColors.textPrimary,
    ),
    labelMedium: TextStyle(
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: JScanColors.textSecondary,
    ),
    labelSmall: TextStyle(
      fontSize: 10,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      color: JScanColors.textMuted,
    ),
  );

  static String? get _fontFamily {
    if (defaultTargetPlatform == TargetPlatform.windows) return 'Segoe UI';
    if (defaultTargetPlatform == TargetPlatform.macOS) return '.SF Pro Text';
    return null;
  }

  /// Estilo monoespaciado para direcciones, IDs y codigos.
  static TextStyle mono(TextStyle? base) {
    final style = base ?? _text.bodySmall ?? const TextStyle();
    return style.copyWith(
      fontFamily: 'Consolas',
      fontFamilyFallback: const <String>[
        'Cascadia Mono',
        'Menlo',
        'DejaVu Sans Mono',
        'monospace',
      ],
      letterSpacing: 0.2,
    );
  }

  static ThemeData dark() {
    final String? family = _fontFamily;
    final TextTheme text =
        family == null ? _text : _text.apply(fontFamily: family);
    final BorderRadius control = BorderRadius.circular(JScanMetrics.radius);
    final BorderRadius panel = BorderRadius.circular(JScanMetrics.radiusPanel);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _scheme,
      scaffoldBackgroundColor: JScanColors.background,
      canvasColor: JScanColors.background,
      textTheme: text,
      primaryTextTheme: text,
      iconTheme: const IconThemeData(
        color: JScanColors.textSecondary,
        size: 20,
      ),
      focusColor: JScanColors.action.withValues(alpha: 0.18),
      hoverColor: Colors.white.withValues(alpha: 0.04),
      splashColor: Colors.white.withValues(alpha: 0.06),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: JScanColors.action,
        selectionColor: JScanColors.action.withValues(alpha: 0.32),
        selectionHandleColor: JScanColors.action,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: JScanColors.background,
        foregroundColor: JScanColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 60,
        titleTextStyle: text.titleLarge,
        iconTheme: const IconThemeData(
          color: JScanColors.textSecondary,
          size: 21,
        ),
        actionsIconTheme: const IconThemeData(
          color: JScanColors.textSecondary,
          size: 21,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: JScanColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: JScanColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: panel,
          side: const BorderSide(color: JScanColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: JScanColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: JScanColors.textSecondary,
        textColor: JScanColors.textPrimary,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: control),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(0, JScanMetrics.controlHeight),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
          foregroundColor: const WidgetStatePropertyAll<Color>(
            JScanColors.textPrimary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.transparent;
              }
              if (states.contains(WidgetState.pressed)) {
                return JScanColors.elevated;
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return JScanColors.elevated.withValues(alpha: 0.7);
              }
              return Colors.transparent;
            },
          ),
          side: WidgetStateProperty.resolveWith<BorderSide>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.focused)) {
                return const BorderSide(color: JScanColors.action, width: 1.4);
              }
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(color: JScanColors.borderSubtle);
              }
              return const BorderSide(color: JScanColors.border);
            },
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(0, JScanMetrics.controlHeight),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
          foregroundColor: const WidgetStatePropertyAll<Color>(
            JScanColors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return JScanColors.elevated.withValues(alpha: 0.6);
              }
              return Colors.transparent;
            },
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(0, JScanMetrics.controlHeight),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll<Color>(
            JScanColors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return JScanColors.elevated.withValues(alpha: 0.8);
              }
              return Colors.transparent;
            },
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(
              JScanMetrics.touchTarget,
              JScanMetrics.touchTarget,
            ),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: control),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JScanColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: text.bodyMedium?.copyWith(
          color: JScanColors.textSecondary,
        ),
        floatingLabelStyle: text.bodySmall?.copyWith(
          color: JScanColors.action,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: JScanColors.textMuted),
        prefixIconColor: JScanColors.textMuted,
        suffixIconColor: JScanColors.textMuted,
        border: OutlineInputBorder(
          borderRadius: control,
          borderSide: const BorderSide(color: JScanColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: const BorderSide(color: JScanColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: const BorderSide(
            color: JScanColors.action,
            width: 1.4,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: const BorderSide(color: JScanColors.borderSubtle),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: const BorderSide(color: JScanColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: const BorderSide(
            color: JScanColors.danger,
            width: 1.4,
          ),
        ),
        errorStyle: text.bodySmall?.copyWith(color: JScanColors.danger),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: JScanColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: panel,
          side: const BorderSide(color: JScanColors.border),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        barrierColor: Colors.black.withValues(alpha: 0.68),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: JScanColors.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: JScanColors.card,
        modalBarrierColor: Colors.black54,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(JScanMetrics.radiusPanel),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: JScanColors.elevated,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: JScanColors.textPrimary,
        ),
        actionTextColor: JScanColors.action,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: control,
          side: const BorderSide(color: JScanColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: JScanColors.surface,
        selectedColor: JScanColors.deepBlue,
        disabledColor: JScanColors.surface,
        side: const BorderSide(color: JScanColors.border),
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(
          color: JScanColors.textPrimary,
        ),
        checkmarkColor: JScanColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        elevation: 0,
        pressElevation: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: JScanColors.action,
        linearTrackColor: JScanColors.elevated,
        circularTrackColor: JScanColors.elevated,
        linearMinHeight: 4,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: JScanColors.elevated,
          borderRadius: BorderRadius.circular(JScanMetrics.radiusSmall),
          border: Border.all(color: JScanColors.border),
        ),
        textStyle: text.bodySmall?.copyWith(
          color: JScanColors.textPrimary,
        ),
        waitDuration: const Duration(milliseconds: 450),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) {
              return JScanColors.background;
            }
            return JScanColors.textSecondary;
          },
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) {
              return JScanColors.action;
            }
            return JScanColors.elevated;
          },
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          JScanColors.border,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) {
              return JScanColors.action;
            }
            return JScanColors.textMuted;
          },
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) {
              return JScanColors.action;
            }
            return Colors.transparent;
          },
        ),
        checkColor: const WidgetStatePropertyAll<Color>(
          JScanColors.background,
        ),
        side: const BorderSide(color: JScanColors.border, width: 1.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.hovered)) {
              return JScanColors.textMuted;
            }
            return JScanColors.border;
          },
        ),
        trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    );
  }
}

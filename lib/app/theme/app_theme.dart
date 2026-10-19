import 'package:emberwit/app/theme/app_colors.dart';
import 'package:emberwit/core/widgets/action_colors.dart';
import 'package:flutter/material.dart';

/// Builds the light and dark [ThemeData] of the app.
///
/// Colors come from the hand built gray scale schemes in [AppColors]. The
/// primary action is the darkest gray on light and the lightest on dark.
///
/// Fonts are bundled (Noto Sans with Noto Sans Bengali as fallback) because
/// the app must render Bengali correctly on devices without Bengali system
/// fonts and without internet access.
abstract final class AppTheme {
  /// Primary font family, covers Latin script.
  static const String fontFamily = 'NotoSans';

  /// Fallback families, used for glyphs [fontFamily] lacks (Bengali).
  static const List<String> fontFamilyFallback = ['NotoSansBengali'];

  /// Light theme.
  static ThemeData light() => _build(AppColors.light);

  /// Dark theme.
  static ThemeData dark() => _build(AppColors.dark);

  /// Background of filled (primary) buttons for [scheme].
  static Color actionColor(ColorScheme scheme) => scheme.action;

  /// Text and icon color on [actionColor].
  static Color onActionColor(ColorScheme scheme) => scheme.onAction;

  static ThemeData _build(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final action = actionColor(scheme);
    final onAction = onActionColor(scheme);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      visualDensity: VisualDensity.standard,
    );
    final shape12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        // On black, a hairline separates cards from the canvas; on white the
        // tinted fill is enough.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: action,
          foregroundColor: onAction,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: const Size(64, 48),
          shape: shape12,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          minimumSize: const Size(64, 48),
          shape: shape12,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.35),
        selectionHandleColor: scheme.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

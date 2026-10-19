import 'package:flutter/material.dart';

/// Emberwit's palette: a neutral gray scale, from near white (`gray100`) to
/// near black (`gray900`), used as a monochrome system.
///
/// Primitives are named by lightness step. Widgets never use them directly:
/// they read semantic roles from [AppColors.light] and [AppColors.dark]
/// through `Theme.of(context).colorScheme`.
///
/// Light theme: `gray100` canvas, `gray900` text and actions. Dark theme:
/// `gray900` canvas, `gray100` text and actions. Elevation is expressed as
/// steps along the scale. Error colors stay red so failures remain
/// recognisable without a hue system.
///
/// Both schemes are hand built so every text and control pair meets WCAG
/// AA; `test/app/theme/app_theme_contrast_test.dart` checks the ratios.
abstract final class AppColors {
  /// Near white: light canvas, dark theme text and actions.
  static const Color gray100 = Color(0xFFF8F9FA);

  /// Light cards and containers; dark theme accents.
  static const Color gray200 = Color(0xFFE9ECEF);

  /// Light raised containers and hairlines.
  static const Color gray300 = Color(0xFFDEE2E6);

  /// Light highest containers and tracks; dark theme secondary text.
  static const Color gray400 = Color(0xFFCED4DA);

  /// Dark theme control borders.
  static const Color gray500 = Color(0xFFADB5BD);

  /// Light theme control borders.
  static const Color gray600 = Color(0xFF6C757D);

  /// Light theme secondary text; dark theme raised containers.
  static const Color gray700 = Color(0xFF495057);

  /// Dark theme cards.
  static const Color gray800 = Color(0xFF343A40);

  /// Near black: dark canvas, light theme text and actions.
  static const Color gray900 = Color(0xFF212529);

  /// Light theme roles.
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: gray900,
    onPrimary: gray100,
    primaryContainer: gray300,
    onPrimaryContainer: gray900,
    secondary: gray700,
    onSecondary: gray100,
    secondaryContainer: gray200,
    onSecondaryContainer: gray900,
    tertiary: gray800,
    onTertiary: gray100,
    tertiaryContainer: gray300,
    onTertiaryContainer: gray900,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: gray100,
    onSurface: gray900,
    onSurfaceVariant: gray700,
    surfaceDim: gray300,
    surfaceBright: gray100,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: gray100,
    surfaceContainer: gray200,
    surfaceContainerHigh: gray200,
    surfaceContainerHighest: gray300,
    outline: gray600,
    outlineVariant: gray300,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: gray800,
    onInverseSurface: gray100,
    inversePrimary: gray400,
    surfaceTint: Colors.transparent,
  );

  /// Dark theme roles.
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: gray100,
    onPrimary: gray900,
    primaryContainer: gray700,
    onPrimaryContainer: gray100,
    secondary: gray400,
    onSecondary: gray900,
    secondaryContainer: gray700,
    onSecondaryContainer: gray100,
    tertiary: gray300,
    onTertiary: gray900,
    tertiaryContainer: gray700,
    onTertiaryContainer: gray100,
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: gray900,
    onSurface: gray100,
    onSurfaceVariant: gray400,
    surfaceDim: gray900,
    surfaceBright: gray700,
    surfaceContainerLowest: Color(0xFF16191C),
    surfaceContainerLow: gray900,
    surfaceContainer: gray800,
    surfaceContainerHigh: gray800,
    surfaceContainerHighest: gray700,
    outline: gray500,
    outlineVariant: gray700,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: gray200,
    onInverseSurface: gray900,
    inversePrimary: gray800,
    surfaceTint: Colors.transparent,
  );
}

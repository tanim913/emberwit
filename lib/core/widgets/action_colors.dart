import 'package:flutter/material.dart';

/// The app's primary action colors, shared by the theme and by widgets that
/// style their own filled controls: the strongest step of the gray scale
/// against the canvas ([ColorScheme.primary] on [ColorScheme.onPrimary]).
extension ActionColors on ColorScheme {
  /// Background of primary actions.
  Color get action => primary;

  /// Text and icons on [action].
  Color get onAction => onPrimary;
}

/// Monospace text for code: the bundled Noto Sans Mono (same look on every
/// device, no network), with Noto Sans Bengali for Bengali in code.
const TextStyle monospaceText = TextStyle(
  fontFamily: 'NotoSansMono',
  fontFamilyFallback: ['NotoSansBengali', 'NotoSans'],
);

import 'dart:math' as math;

import 'package:emberwit/app/theme/app_colors.dart';
import 'package:emberwit/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2 contrast ratio between two opaque colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const double text = 4.5;
const double control = 3;

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    final s = theme.colorScheme;
    final action = AppTheme.actionColor(s);
    final onAction = AppTheme.onActionColor(s);
    final card = theme.cardTheme.color!;

    group('$name theme meets WCAG AA', () {
      final textPairs = <String, (Color, Color)>{
        'body text on canvas': (s.onSurface, s.surface),
        'body text on cards': (s.onSurface, card),
        'secondary text on canvas': (s.onSurfaceVariant, s.surface),
        'secondary text on cards': (s.onSurfaceVariant, card),
        'secondary text on highest container': (
          s.onSurfaceVariant,
          s.surfaceContainerHighest,
        ),
        'accent text on canvas': (s.primary, s.surface),
        'accent text on cards': (s.primary, card),
        'label on primary action': (onAction, action),
        'on primary': (s.onPrimary, s.primary),
        'on primary container': (s.onPrimaryContainer, s.primaryContainer),
        'on secondary container': (
          s.onSecondaryContainer,
          s.secondaryContainer,
        ),
        'on tertiary (build banner)': (s.onTertiary, s.tertiary),
        'error text on canvas': (s.error, s.surface),
        'error banner text': (s.onErrorContainer, s.errorContainer),
        'snack bar text': (s.onInverseSurface, s.inverseSurface),
      };
      for (final MapEntry(key: label, value: (fg, bg)) in textPairs.entries) {
        test('$label >= $text:1', () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(text));
        });
      }

      final controlPairs = <String, (Color, Color)>{
        'primary action against canvas': (action, s.surface),
        'control borders against canvas': (s.outline, s.surface),
        'notice icons against canvas': (s.tertiary, s.surface),
        'progress bar against its track': (
          s.primary,
          s.surfaceContainerHighest,
        ),
      };
      for (final MapEntry(key: label, value: (fg, bg))
          in controlPairs.entries) {
        test('$label >= $control:1', () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(control));
        });
      }
    });
  }

  test('the palette is the gray scale, light and dark mirrored', () {
    expect(AppColors.light.surface, AppColors.gray100);
    expect(AppColors.light.onSurface, AppColors.gray900);
    expect(AppColors.dark.surface, AppColors.gray900);
    expect(AppColors.dark.onSurface, AppColors.gray100);
    expect(AppTheme.actionColor(AppColors.light), AppColors.gray900);
    expect(AppTheme.actionColor(AppColors.dark), AppColors.gray100);
  });

  test('prints the contrast table', () {
    final buffer = StringBuffer();
    for (final (name, s) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      final action = AppTheme.actionColor(s);
      String ratio(Color a, Color b) => contrast(a, b).toStringAsFixed(1);
      buffer
        ..writeln(name)
        ..writeln('  text/canvas ${ratio(s.onSurface, s.surface)}')
        ..writeln('  accent/canvas ${ratio(s.primary, s.surface)}')
        ..writeln('  button label ${ratio(AppTheme.onActionColor(s), action)}')
        ..writeln('  button/canvas ${ratio(action, s.surface)}');
    }
    // Printed for the change report.
    // ignore: avoid_print
    print(buffer);
  });
}

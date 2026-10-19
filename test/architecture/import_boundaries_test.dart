import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the dependency rules from ARCHITECTURE.md:
///
/// * `core` depends on nothing else in `lib/` (except generated l10n).
/// * `engine` depends only on `core`.
/// * a feature never imports another feature; shared contracts live in core.
/// * nothing below `app` imports `app`.
void main() {
  final imports = <String, List<String>>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart') ||
        entity.path.endsWith('.freezed.dart')) {
      continue;
    }
    final path = entity.path.replaceAll(r'\', '/').substring('lib/'.length);
    imports[path] = RegExp(
      r'''^(?:import|export)\s+'package:emberwit/([^']+)''',
      multiLine: true,
    ).allMatches(entity.readAsStringSync()).map((m) => m.group(1)!).toList();
  }

  String? featureOf(String path) {
    final match = RegExp('^features/([^/]+)/').firstMatch(path);
    return match?.group(1);
  }

  test('scans the source tree', () {
    expect(imports, isNotEmpty);
  });

  test('core imports only core and generated l10n', () {
    for (final MapEntry(key: file, value: targets) in imports.entries) {
      if (!file.startsWith('core/')) continue;
      for (final target in targets) {
        expect(
          target.startsWith('core/') || target.startsWith('l10n/gen/'),
          isTrue,
          reason: '$file imports $target',
        );
      }
    }
  });

  test('engine imports only engine and core', () {
    for (final MapEntry(key: file, value: targets) in imports.entries) {
      if (!file.startsWith('engine/')) continue;
      for (final target in targets) {
        expect(
          target.startsWith('engine/') || target.startsWith('core/'),
          isTrue,
          reason: '$file imports $target',
        );
      }
    }
  });

  test('features never import other features or app', () {
    for (final MapEntry(key: file, value: targets) in imports.entries) {
      final feature = featureOf(file);
      if (feature == null) continue;
      for (final target in targets) {
        final targetFeature = featureOf(target);
        expect(
          targetFeature == null || targetFeature == feature,
          isTrue,
          reason: '$file imports feature "$targetFeature"',
        );
        expect(target.startsWith('app/'), isFalse, reason: '$file -> $target');
      }
    }
  });
}

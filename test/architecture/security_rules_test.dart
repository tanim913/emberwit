import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static checks for the security rules in SECURITY.md. They read source and
/// configuration files, so a regression fails CI before it ships.
void main() {
  List<File> sources(String dir, {String suffix = '.dart'}) => [
    for (final e in Directory(dir).listSync(recursive: true))
      if (e is File &&
          e.path.endsWith(suffix) &&
          !e.path.endsWith('.g.dart') &&
          !e.path.endsWith('.freezed.dart') &&
          !e.path.contains('/l10n/gen/'))
        e,
  ];

  /// Code lines only: doc comments and comments are skipped.
  Iterable<(String, int, String)> codeLines(List<File> files) sync* {
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        yield (file.path, i + 1, line);
      }
    }
  }

  test('no print or debugPrint in app code (use AppLogger)', () {
    final offenders = [
      for (final (path, n, line) in codeLines(sources('lib')))
        if (RegExp(r'(^|[^\w.])(print|debugPrint)\(').hasMatch(line))
          '$path:$n',
    ];
    expect(offenders, isEmpty);
  });

  test('no plain http URLs in app code', () {
    final offenders = [
      for (final (path, n, line) in codeLines(sources('lib')))
        if (line.contains('http://')) '$path:$n',
    ];
    expect(offenders, isEmpty);
  });

  test('log messages never interpolate user content', () {
    // Names that hold chat text, prompts, passphrases or file names.
    final sensitive = RegExp(
      r'logger\.\w+\([^;]*\$\{?\w*\.?(content|text|prompt|passphrase|'
      r'title|fileName|path|query)\b',
      caseSensitive: false,
    );
    final offenders = [
      for (final (path, n, line) in codeLines(sources('lib')))
        if (sensitive.hasMatch(line)) '$path:$n',
    ];
    expect(offenders, isEmpty);
  });

  test('no private keys or secrets are committed in shipped files', () {
    final roots = ['lib', 'assets', 'android/app/src', 'ios/Runner'];
    final secret = RegExp(
      r'PRIVATE KEY|catalog-signing\.key|storePassword\s*=|keyPassword\s*=',
    );
    final offenders = <String>[];
    for (final root in roots) {
      for (final e in Directory(root).listSync(recursive: true)) {
        if (e is! File) continue;
        if (e.path.endsWith('.gguf') ||
            e.path.endsWith('.ttf') ||
            e.path.endsWith('.png')) {
          continue;
        }
        final String text;
        try {
          text = e.readAsStringSync();
        } on FileSystemException {
          continue; // Binary file.
        }
        if (secret.hasMatch(text)) offenders.add(e.path);
      }
    }
    expect(offenders, isEmpty);
  });

  group('Android manifest', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    test('disables backup and cleartext traffic', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('exports only the launcher activity and the system widget', () {
      final exported = RegExp('android:exported="true"')
          .allMatches(manifest)
          .length;
      expect(exported, 2);
      // The widget receiver takes broadcasts from the system only.
      expect(
        manifest,
        contains('android:permission="android.permission.BIND_APPWIDGET"'),
      );
      expect(manifest, isNot(contains('android:debuggable="true"')));
    });

    test('requests only the permissions the app needs', () {
      final permissions = RegExp(r'uses-permission android:name="([\w.]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toSet();
      expect(permissions, {
        'android.permission.INTERNET',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.USE_BIOMETRIC',
        'android.permission.RECORD_AUDIO',
        'com.android.alarm.permission.SET_ALARM',
      });
    });

    test('trusts only system certificates over HTTPS', () {
      final config = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();
      expect(config, contains('cleartextTrafficPermitted="false"'));
      expect(config, isNot(contains('src="user"')));
    });
  });

  test('iOS allows no arbitrary loads', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
  });

  test('release builds use the silent logger', () {
    final logger = File('lib/core/logging/app_logger.dart').readAsStringSync();
    expect(logger, contains('kReleaseMode'));
    expect(logger, contains('SilentAppLogger'));
  });
}

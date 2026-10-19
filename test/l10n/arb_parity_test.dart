import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readArb(String locale) =>
    jsonDecode(File('lib/l10n/arb/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// Placeholder names: `{name}` or the selector of `{name, plural, ...}`.
/// Literal text inside plural branches (`=0{No models}`) is not a
/// placeholder.
Set<String> _placeholders(String message) =>
    RegExp(r'\{([A-Za-z_]\w*)\s*[,}]')
        .allMatches(message)
        .map((m) => m.group(1)!)
        .toSet();

void main() {
  final en = _readArb('en');
  final bn = _readArb('bn');

  test('Bengali has exactly the English keys', () {
    expect(_messageKeys(bn), _messageKeys(en));
  });

  test('every English message has a description', () {
    for (final key in _messageKeys(en)) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      expect(meta?['description'], isNotNull, reason: key);
    }
  });

  test('no message is empty', () {
    for (final arb in [en, bn]) {
      for (final key in _messageKeys(arb)) {
        expect((arb[key] as String).trim(), isNotEmpty, reason: key);
      }
    }
  });

  test('placeholders match between languages', () {
    for (final key in _messageKeys(en)) {
      expect(
        _placeholders(bn[key] as String),
        _placeholders(en[key] as String),
        reason: key,
      );
    }
  });
}

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/l10n/failure_messages.dart';
import 'package:emberwit/core/l10n/runtime_messages.dart';
import 'package:emberwit/core/runtime/runtime_policy.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final failures = <AppFailure>[
    const UnexpectedFailure(),
    const ConfigurationFailure('x'),
    for (final reason in ModelLoadFailureReason.values)
      ModelLoadFailure(reason),
    const NoModelLoadedFailure(),
    const EngineBusyFailure(),
    const ContextOverflowFailure(promptTokens: 3000, contextLength: 2048),
    const GenerationFailure('decode failed'),
    const DeviceProfilingFailure('x'),
    const BenchmarkUnavailableFailure(),
    for (final reason in RuntimeLimitReason.values) RuntimeLimitFailure(reason),
    for (final reason in ArchiveFailureReason.values) ArchiveFailure(reason),
  ];

  for (final locale in AppLocalizations.supportedLocales) {
    test(
      'every failure has a distinct ${locale.languageCode} message',
      () async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final messages = failures.map((f) => describeFailure(l10n, f)).toList();
        expect(messages.every((m) => m.trim().isNotEmpty), isTrue);
        expect(messages.toSet(), hasLength(messages.length));
      },
    );
  }

  for (final locale in AppLocalizations.supportedLocales) {
    test(
      'every runtime concern has a ${locale.languageCode} message',
      () async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final messages = [
          for (final concern in RuntimeConcern.values)
            describeRuntimeConcern(l10n, concern),
        ];
        expect(messages.every((m) => m.trim().isNotEmpty), isTrue);
        expect(messages.toSet(), hasLength(messages.length));
      },
    );
  }

  test('context overflow message includes the numbers', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final message = describeFailure(
      l10n,
      const ContextOverflowFailure(promptTokens: 3000, contextLength: 2048),
    );
    expect(message, contains('3,000'));
    expect(message, contains('2,048'));
  });
}

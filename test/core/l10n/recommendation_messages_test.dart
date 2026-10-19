import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/l10n/recommendation_messages.dart';
import 'package:emberwit/core/recommendation/model_recommendation.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reasons = <RecommendationReason>[
    RunsWell(12.34),
    SlowSpeed(4.2),
    TooSlow(0.9),
    NotEnoughMemory(requiredBytes: 2900000000, budgetBytes: 1800000000),
    BelowMinimumRam(minimumBytes: 6000000000, totalBytes: 4000000000),
    NotEnoughStorage(requiredBytes: 3600000000, freeBytes: 1200000000),
    ContextReduced(from: 4096, to: 2048),
    SpeedEstimatedWithoutBenchmark(),
  ];

  for (final locale in AppLocalizations.supportedLocales) {
    group('${locale.languageCode} messages', () {
      late AppLocalizations l10n;
      setUpAll(() async => l10n = await AppLocalizations.delegate.load(locale));

      test('every reason has a distinct sentence', () {
        final texts = reasons
            .map((r) => describeRecommendationReason(l10n, r))
            .toList();
        expect(texts.every((t) => t.trim().isNotEmpty), isTrue);
        expect(texts.toSet(), hasLength(reasons.length));
      });

      test('labels, tiers and thermal states have names', () {
        for (final values in [
          RecommendationLabel.values.map(
            (l) => recommendationLabelText(l10n, l),
          ),
          DeviceTier.values.map((t) => deviceTierName(l10n, t)),
          DeviceTier.values.map((t) => deviceTierDescription(l10n, t)),
          ThermalState.values.map((t) => thermalStateName(l10n, t)),
        ]) {
          final list = values.toList();
          expect(list.toSet(), hasLength(list.length));
        }
      });
    });
  }

  test('English numbers are formatted and rounded', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      describeRecommendationReason(l10n, const RunsWell(12.34)),
      'Runs smoothly, about 12.3 tokens per second.',
    );
    expect(
      describeRecommendationReason(
        l10n,
        const NotEnoughStorage(
          requiredBytes: 3600000000,
          freeBytes: 1200000000,
        ),
      ),
      contains('3.6 GB'),
    );
  });

  test('Bengali uses Bengali digits', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('bn'));
    final text = describeRecommendationReason(l10n, const RunsWell(12.34));
    expect(text, contains('১২.৩'));
  });

  test('gigabytes are decimal', () {
    expect(gigabytes(1500000000), 1.5);
  });
}

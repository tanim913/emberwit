import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlavorConfig.resolve', () {
    for (final flavor in AppFlavor.values) {
      test('resolves "${flavor.name}" in every build mode', () {
        expect(FlavorConfig.resolve(flavor.name, isRelease: false), Ok(flavor));
        expect(FlavorConfig.resolve(flavor.name, isRelease: true), Ok(flavor));
      });
    }

    test('missing flavor falls back to dev outside release', () {
      expect(
        FlavorConfig.resolve(null, isRelease: false),
        const Ok(AppFlavor.dev),
      );
      expect(
        FlavorConfig.resolve('', isRelease: false),
        const Ok(AppFlavor.dev),
      );
    });

    test('missing flavor is a configuration failure in release', () {
      expect(
        FlavorConfig.resolve(null, isRelease: true).failureOrNull,
        isA<ConfigurationFailure>(),
      );
    });

    test('unknown flavor is always a configuration failure', () {
      for (final release in [true, false]) {
        final result = FlavorConfig.resolve('qa', isRelease: release);
        expect(result.failureOrNull, isA<ConfigurationFailure>());
        expect(
          (result.failureOrNull! as ConfigurationFailure).detail,
          contains('qa'),
        );
      }
    });
  });

  group('FlavorConfig.forFlavor', () {
    test('every flavor uses an HTTPS catalog URL on its own path', () {
      final urls = AppFlavor.values
          .map((f) => FlavorConfig.forFlavor(f).catalogUrl)
          .toList();
      expect(urls.every((u) => u.scheme == 'https'), isTrue);
      expect(urls.toSet(), hasLength(AppFlavor.values.length));
    });

    test('only non production builds show a banner', () {
      expect(FlavorConfig.forFlavor(AppFlavor.dev).showBanner, isTrue);
      expect(FlavorConfig.forFlavor(AppFlavor.staging).showBanner, isTrue);
      expect(FlavorConfig.forFlavor(AppFlavor.prod).showBanner, isFalse);
    });

    test('debug tools are never enabled in production', () {
      expect(FlavorConfig.forFlavor(AppFlavor.dev).enableDebugTools, isTrue);
      expect(
        FlavorConfig.forFlavor(AppFlavor.staging).enableDebugTools,
        isTrue,
      );
      expect(FlavorConfig.forFlavor(AppFlavor.prod).enableDebugTools, isFalse);
    });

    test('app names are distinct and prod uses the plain product name', () {
      expect(FlavorConfig.forFlavor(AppFlavor.prod).appName, 'Emberwit');
      expect(FlavorConfig.forFlavor(AppFlavor.dev).appName, 'Emberwit Dev');
      expect(
        FlavorConfig.forFlavor(AppFlavor.staging).appName,
        'Emberwit Staging',
      );
    });

    test('is a value type', () {
      expect(
        FlavorConfig.forFlavor(AppFlavor.dev),
        FlavorConfig.forFlavor(AppFlavor.dev),
      );
      expect(
        FlavorConfig.forFlavor(AppFlavor.dev).copyWith(showBanner: false),
        isNot(FlavorConfig.forFlavor(AppFlavor.dev)),
      );
    });
  });
}

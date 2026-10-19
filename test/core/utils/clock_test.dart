import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SystemClock returns the current time', () {
    final before = DateTime.now();
    final now = const SystemClock().now();
    expect(now.isBefore(before), isFalse);
  });

  test('FixedClock is frozen until advanced', () {
    final clock = FixedClock(DateTime(2026));
    expect(clock.now(), DateTime(2026));
    clock.advance(const Duration(days: 1));
    expect(clock.now(), DateTime(2026, 1, 2));
  });

  test('core providers have safe defaults, except flavor config', () {
    final container = ProviderContainer.test();
    expect(container.read(clockProvider), isA<SystemClock>());
    expect(container.read(appLoggerProvider), isA<DebugAppLogger>());
    expect(() => container.read(flavorConfigProvider), throwsA(anything));
  });
}

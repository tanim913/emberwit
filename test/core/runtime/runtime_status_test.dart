import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/runtime/runtime_status.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FixedClock clock;
  late ProviderContainer container;

  setUp(() {
    clock = FixedClock(DateTime.utc(2026, 10, 3));
    container = ProviderContainer.test(
      overrides: [clockProvider.overrideWithValue(clock)],
    );
  });

  RuntimeStatus status() => container.read(runtimeStatusProvider.notifier);

  test('starts at full speed', () {
    expect(container.read(runtimeStatusProvider), RuntimeAdvice.normal);
    expect(status().conditions, isNull);
  });

  test('follows the latest conditions', () {
    status().updateConditions(
      const DeviceConditions(thermalState: ThermalState.critical),
    );
    expect(status().advice.concerns, {RuntimeConcern.overheated});
    expect(
      status().conditions,
      const DeviceConditions(thermalState: ThermalState.critical),
    );
    status().updateConditions(const DeviceConditions());
    expect(container.read(runtimeStatusProvider), RuntimeAdvice.normal);
  });

  test('does not notify listeners when nothing changes', () {
    var notifications = 0;
    container.listen(runtimeStatusProvider, (_, _) => notifications++);
    status()
      ..updateConditions(const DeviceConditions(batteryLevel: 90))
      ..updateConditions(const DeviceConditions(batteryLevel: 80));
    expect(notifications, 0);
  });
}

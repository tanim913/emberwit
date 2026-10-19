import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/runtime/runtime_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = RuntimePolicy();
  RuntimeAdvice evaluate(DeviceConditions? c) => policy.evaluate(c);

  group('RuntimePolicy', () {
    test('no reading and normal conditions mean full speed', () {
      expect(evaluate(null), RuntimeAdvice.normal);
      expect(
        evaluate(
          const DeviceConditions(
            thermalState: ThermalState.fair,
            batteryLevel: 80,
            isCharging: false,
          ),
        ),
        RuntimeAdvice.normal,
      );
    });

    test('critical heat stops, serious heat slows down', () {
      final critical = evaluate(
        const DeviceConditions(thermalState: ThermalState.critical),
      );
      expect(critical.concerns, {RuntimeConcern.overheated});
      expect(critical.canGenerate, isFalse);

      final serious = evaluate(
        const DeviceConditions(thermalState: ThermalState.serious),
      );
      expect(serious.concerns, {RuntimeConcern.warm});
      expect(serious.canGenerate, isTrue);
      expect(serious.reduced, isTrue);
    });

    test('battery thresholds apply only when not charging', () {
      expect(
        evaluate(const DeviceConditions(batteryLevel: 5, isCharging: false))
            .concerns,
        {RuntimeConcern.criticalBattery},
      );
      expect(
        evaluate(const DeviceConditions(batteryLevel: 15, isCharging: false))
            .concerns,
        {RuntimeConcern.lowBattery},
      );
      expect(
        evaluate(const DeviceConditions(batteryLevel: 16, isCharging: false)),
        RuntimeAdvice.normal,
      );
      expect(
        evaluate(const DeviceConditions(batteryLevel: 3, isCharging: true)),
        RuntimeAdvice.normal,
      );
      // Unknown charging state: no battery concern.
      expect(
        evaluate(const DeviceConditions(batteryLevel: 3)),
        RuntimeAdvice.normal,
      );
    });

    test('battery saver slows down', () {
      final advice = evaluate(const DeviceConditions(lowPowerMode: true));
      expect(advice.concerns, {RuntimeConcern.batterySaver});
      expect(advice.reduced, isTrue);
    });

    test('concerns combine', () {
      final advice = evaluate(
        const DeviceConditions(
          thermalState: ThermalState.serious,
          batteryLevel: 10,
          isCharging: false,
          lowPowerMode: true,
        ),
      );
      expect(advice.concerns, {
        RuntimeConcern.warm,
        RuntimeConcern.lowBattery,
        RuntimeConcern.batterySaver,
      });
    });
  });

  group('RuntimeAdvice', () {
    test('halves threads when reduced, never below one', () {
      const warm = RuntimeAdvice({RuntimeConcern.warm});
      expect(warm.threadsFor(4), 2);
      expect(warm.threadsFor(3), 1);
      expect(warm.threadsFor(1), 1);
      expect(RuntimeAdvice.normal.threadsFor(4), 4);
      const battery = RuntimeAdvice({RuntimeConcern.criticalBattery});
      expect(battery.reduced, isFalse);
      expect(battery.threadsFor(4), 4);
    });

    test('primary is the most severe concern', () {
      expect(RuntimeAdvice.normal.primary, isNull);
      expect(
        const RuntimeAdvice({
          RuntimeConcern.batterySaver,
          RuntimeConcern.overheated,
          RuntimeConcern.warm,
        }).primary,
        RuntimeConcern.overheated,
      );
      expect(
        const RuntimeAdvice({
          RuntimeConcern.batterySaver,
          RuntimeConcern.lowBattery,
        }).primary,
        RuntimeConcern.lowBattery,
      );
    });

    test('compares by concerns', () {
      expect(
        const RuntimeAdvice({RuntimeConcern.warm, RuntimeConcern.lowBattery}),
        const RuntimeAdvice({RuntimeConcern.lowBattery, RuntimeConcern.warm}),
      );
      expect(
        const RuntimeAdvice({RuntimeConcern.warm}).hashCode,
        const RuntimeAdvice({RuntimeConcern.warm}).hashCode,
      );
      expect(
        const RuntimeAdvice({RuntimeConcern.warm}),
        isNot(RuntimeAdvice.normal),
      );
    });
  });

  test('DeviceConditions compares by value', () {
    const a = DeviceConditions(
      thermalState: ThermalState.fair,
      batteryLevel: 50,
      isCharging: true,
      availableRamBytes: 1000,
    );
    expect(
      a,
      const DeviceConditions(
        thermalState: ThermalState.fair,
        batteryLevel: 50,
        isCharging: true,
        availableRamBytes: 1000,
      ),
    );
    expect(
      a.hashCode,
      const DeviceConditions(
        thermalState: ThermalState.fair,
        batteryLevel: 50,
        isCharging: true,
        availableRamBytes: 1000,
      ).hashCode,
    );
    expect(a, isNot(const DeviceConditions()));
  });
}

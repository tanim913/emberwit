import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/features/device_profiler/data/device_conditions_source_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/device_fixtures.dart';
import '../fakes.dart';

void main() {
  test('reads heat, battery and memory from the device snapshot', () async {
    final snapshot = profile().copyWith(
      thermalState: ThermalState.serious,
      batteryLevel: 12,
      isCharging: false,
      lowPowerMode: true,
    );
    final source = SnapshotDeviceConditionsSource(FakeSnapshotSource(snapshot));
    expect(
      await source.read(),
      DeviceConditions(
        thermalState: ThermalState.serious,
        batteryLevel: 12,
        isCharging: false,
        lowPowerMode: true,
        availableRamBytes: snapshot.availableRamBytes,
      ),
    );
  });

  test('passes platform errors on', () async {
    final source = SnapshotDeviceConditionsSource(
      FakeSnapshotSource(profile(), error: StateError('channel')),
    );
    await expectLater(source.read(), throwsStateError);
  });
}

import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/features/device_profiler/data/device_snapshot_source.dart';

/// [DeviceConditionsSource] reading the same live values as the profiler:
/// thermal state, battery and memory.
final class SnapshotDeviceConditionsSource implements DeviceConditionsSource {
  /// Creates the source.
  const new(this._snapshots);

  final DeviceSnapshotSource _snapshots;

  @override
  Future<DeviceConditions> read() async {
    final snapshot = await _snapshots.snapshot();
    return DeviceConditions(
      thermalState: snapshot.thermalState,
      batteryLevel: snapshot.batteryLevel,
      isCharging: snapshot.isCharging,
      lowPowerMode: snapshot.lowPowerMode,
      availableRamBytes: snapshot.availableRamBytes,
    );
  }
}

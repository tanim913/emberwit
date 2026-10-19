import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:flutter/foundation.dart';

/// Something about the device's current state that limits generation.
///
/// Ordered from most to least severe; the UI shows the most severe one.
enum RuntimeConcern {
  /// Critical heat: generation is stopped until the device cools down.
  overheated,

  /// Battery nearly empty and not charging: generation is stopped.
  criticalBattery,

  /// Serious heat: fewer threads, replies are slower.
  warm,

  /// Battery low and not charging: fewer threads.
  lowBattery,

  /// Battery saver or Low Power Mode is on: fewer threads.
  batterySaver,
}

/// What the app may do right now, decided by [RuntimePolicy].
@immutable
final class RuntimeAdvice {
  /// Creates advice. No concerns means full speed.
  const new([this.concerns = const {}]);

  /// Full speed, no concerns.
  static const RuntimeAdvice normal = RuntimeAdvice();

  /// Active concerns.
  final Set<RuntimeConcern> concerns;

  /// Whether a new reply may start.
  bool get canGenerate =>
      !concerns.contains(RuntimeConcern.overheated) &&
      !concerns.contains(RuntimeConcern.criticalBattery);

  /// Whether inference runs with fewer threads to produce less heat and use
  /// less power.
  bool get reduced =>
      concerns.contains(RuntimeConcern.warm) ||
      concerns.contains(RuntimeConcern.lowBattery) ||
      concerns.contains(RuntimeConcern.batterySaver);

  /// Threads to use instead of [base]: half (at least one) when [reduced].
  int threadsFor(int base) {
    if (!reduced) return base;
    final half = base ~/ 2;
    return half < 1 ? 1 : half;
  }

  /// The most severe concern, or `null`.
  RuntimeConcern? get primary {
    for (final concern in RuntimeConcern.values) {
      if (concerns.contains(concern)) return concern;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is RuntimeAdvice && setEquals(other.concerns, concerns);

  @override
  int get hashCode => Object.hashAllUnordered(concerns);
}

/// Turns [DeviceConditions] into [RuntimeAdvice]. Pure, no I/O.
///
/// * Thermal `critical`: stop. Thermal `serious`: half the threads.
/// * Battery at or below [criticalBatteryPercent] and not charging: stop.
///   At or below [lowBatteryPercent] and not charging: half the threads.
/// * Battery saver: half the threads.
///
/// Memory warnings are handled silently by the runtime supervisor (it frees
/// an idle model, which reloads on the next message), so they are not a
/// concern shown to the user.
final class RuntimePolicy {
  /// Creates the policy.
  const new({this.lowBatteryPercent = 15, this.criticalBatteryPercent = 5});

  /// Battery level that reduces threads.
  final int lowBatteryPercent;

  /// Battery level that stops generation.
  final int criticalBatteryPercent;

  /// Advice for [conditions].
  RuntimeAdvice evaluate(DeviceConditions? conditions) {
    final concerns = <RuntimeConcern>{};
    if (conditions != null) {
      switch (conditions.thermalState) {
        case ThermalState.critical:
          concerns.add(RuntimeConcern.overheated);
        case ThermalState.serious:
          concerns.add(RuntimeConcern.warm);
        case ThermalState.nominal || ThermalState.fair || ThermalState.unknown:
          break;
      }
      final level = conditions.batteryLevel;
      if (level != null && conditions.isCharging == false) {
        if (level <= criticalBatteryPercent) {
          concerns.add(RuntimeConcern.criticalBattery);
        } else if (level <= lowBatteryPercent) {
          concerns.add(RuntimeConcern.lowBattery);
        }
      }
      if (conditions.lowPowerMode) concerns.add(RuntimeConcern.batterySaver);
    }
    return concerns.isEmpty ? RuntimeAdvice.normal : RuntimeAdvice(concerns);
  }
}

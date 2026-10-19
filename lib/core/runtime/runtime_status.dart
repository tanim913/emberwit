import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/runtime/runtime_policy.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:emberwit/core/runtime/runtime_policy.dart';

part 'runtime_status.g.dart';

/// The current [RuntimeAdvice], shared by the chat (threads, whether a reply
/// may start, warnings) and the runtime supervisor that feeds it.
@Riverpod(keepAlive: true)
class RuntimeStatus extends _$RuntimeStatus {
  DeviceConditions? _conditions;

  /// Thresholds in use.
  static const RuntimePolicy policy = RuntimePolicy();

  @override
  RuntimeAdvice build() => RuntimeAdvice.normal;

  /// The current advice, for code outside the provider system.
  RuntimeAdvice get advice => state;

  /// Last reading, `null` before the first.
  DeviceConditions? get conditions => _conditions;

  /// Records a new reading of the device conditions.
  void updateConditions(DeviceConditions conditions) {
    _conditions = conditions;
    _evaluate();
  }

  /// Re-applies the policy to the last reading.
  void refresh() => _evaluate();

  void _evaluate() {
    final advice = policy.evaluate(_conditions);
    if (advice != state) state = advice;
  }
}

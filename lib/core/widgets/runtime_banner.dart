import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/l10n/runtime_messages.dart';
import 'package:emberwit/core/runtime/runtime_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tells the user why replies are slower or paused (heat, battery, memory).
/// Shows nothing when the device is in a normal state.
class RuntimeBanner extends ConsumerWidget {
  /// Creates the banner.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advice = ref.watch(runtimeStatusProvider);
    final concern = advice.primary;
    if (concern == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final blocking = !advice.canGenerate;
    final background = blocking
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = blocking ? scheme.onErrorContainer : scheme.onSurface;
    final icon = switch (concern) {
      RuntimeConcern.overheated ||
      RuntimeConcern.warm => Icons.thermostat_rounded,
      RuntimeConcern.criticalBattery ||
      RuntimeConcern.lowBattery ||
      RuntimeConcern.batterySaver => Icons.battery_alert_rounded,
    };
    return Padding(
      key: const Key('runtime-banner'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    describeRuntimeConcern(context.l10n, concern),
                    style: TextStyle(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

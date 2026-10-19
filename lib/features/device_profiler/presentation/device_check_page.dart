import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:emberwit/core/l10n/failure_messages.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/l10n/recommendation_messages.dart';
import 'package:emberwit/core/widgets/error_banner.dart';
import 'package:emberwit/features/device_profiler/presentation/device_check_controller.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows what this phone can do: performance class, speed test and details.
class DeviceCheckPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(deviceCheckControllerProvider);
    final controller = ref.read(deviceCheckControllerProvider.notifier);
    final profile = state.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deviceCheckTitle),
        actions: [
          IconButton(
            tooltip: l10n.deviceRefresh,
            onPressed: state.refreshing || state.benchmarking
                ? null
                : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: profile == null
            ? Center(
                child: state.failure == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: ErrorBanner(
                          describeFailure(l10n, state.failure!),
                        ),
                      ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TierCard(profile: profile, tier: state.tier!),
                  if (!profile.isPhysicalDevice)
                    _Notice(Icons.info_outline_rounded, l10n.deviceEmulator),
                  if (profile.lowPowerMode)
                    _Notice(Icons.battery_saver_rounded, l10n.deviceLowPower),
                  const SizedBox(height: 12),
                  _BenchmarkCard(state: state, onRun: controller.runBenchmark),
                  if (state.failure != null) ...[
                    const SizedBox(height: 12),
                    ErrorBanner(describeFailure(l10n, state.failure!)),
                  ],
                  const SizedBox(height: 12),
                  _DetailsCard(profile),
                ],
              ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const new({required this.profile, required this.tier});

  final DeviceProfile profile;
  final DeviceTier tier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deviceTierHeading, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              deviceTierName(l10n, tier),
              key: const Key('device-tier'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(deviceTierDescription(l10n, tier)),
            const SizedBox(height: 4),
            Text(l10n.deviceContextLength(defaultContextLength(tier))),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const new(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.tertiary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _BenchmarkCard extends StatelessWidget {
  const new({required this.state, required this.onRun});

  final DeviceCheckState state;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final result = state.profile?.benchmark;
    final stage = state.benchmarkStage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.benchmarkSection, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.benchmarkDescription, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (stage != null) ...[
              LinearProgressIndicator(value: state.benchmarkProgress),
              const SizedBox(height: 8),
              Text(_stageText(l10n, stage)),
            ] else if (result == null)
              Text(l10n.benchmarkNotRun)
            else ...[
              Text(
                l10n.benchmarkSpeed(result.tokensPerSecond),
                key: const Key('benchmark-speed'),
                style: theme.textTheme.titleSmall,
              ),
              Text(l10n.benchmarkFirstToken(result.timeToFirstTokenMs)),
              Text(l10n.benchmarkLoadTime(result.loadTimeMs)),
              Text(l10n.benchmarkMeasuredOn(result.measuredAt.toLocal())),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('run-benchmark'),
              onPressed: stage == null ? onRun : null,
              icon: const Icon(Icons.speed_rounded),
              label: Text(
                result == null ? l10n.benchmarkRun : l10n.benchmarkRerun,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _stageText(AppLocalizations l10n, BenchmarkStage stage) =>
      switch (stage) {
        BenchmarkStage.preparing => l10n.benchmarkStagePreparing,
        BenchmarkStage.loading => l10n.benchmarkStageLoading,
        BenchmarkStage.running => l10n.benchmarkStageRunning,
      };
}

class _DetailsCard extends StatelessWidget {
  const new(this.profile);

  final DeviceProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = profile;
    final os = switch (p.platform) {
      DevicePlatform.android => 'Android ${p.osVersion}',
      DevicePlatform.ios => 'iOS ${p.osVersion}',
      DevicePlatform.other => p.osVersion,
    };
    final battery = p.batteryLevel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(
              l10n.deviceDetailsSection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              l10n.deviceMemory(
                gigabytes(p.availableRamBytes),
                gigabytes(p.totalRamBytes),
              ),
            ),
            Text(
              l10n.deviceStorage(
                gigabytes(p.freeStorageBytes),
                gigabytes(p.totalStorageBytes),
              ),
            ),
            Text(
              l10n.deviceProcessor(
                p.cpuArchitecture,
                p.cpuCores,
                p.performanceCores,
              ),
            ),
            Text(
              p.cpuFeatures.isEmpty
                  ? l10n.deviceCpuFeaturesNone
                  : l10n.deviceCpuFeatures(p.cpuFeatures.join(', ')),
            ),
            Text(
              p.gpuBackends.isEmpty
                  ? l10n.deviceGpuNone
                  : l10n.deviceGpu(p.gpuBackends.map(_gpuName).join(', ')),
            ),
            Text(l10n.deviceSystem('${p.manufacturer} ${p.deviceModel}', os)),
            Text(l10n.deviceThermal(thermalStateName(l10n, p.thermalState))),
            Text(
              battery == null
                  ? l10n.deviceBatteryUnknown
                  : (p.isCharging ?? false)
                  ? l10n.deviceBatteryCharging(battery)
                  : l10n.deviceBattery(battery),
            ),
          ],
        ),
      ),
    );
  }

  static String _gpuName(String backend) => switch (backend) {
    'metal' => 'Metal',
    'vulkan' => 'Vulkan',
    _ => backend,
  };
}

import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:emberwit/core/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/device_fixtures.dart';

/// The target device matrix, simulated. Benchmark speeds are assumptions for
/// the bundled 92 MB model (see docs/DEVICE_MATRIX.md) until real devices
/// are measured in Phase 6.
final matrix = <String, DeviceProfile>{
  'Low end Android, 4 GB': profile(
    totalRamBytes: (3.7 * gib).round(),
    benchmark: benchmarkAt(30),
    cpuFeatures: const [],
  ),
  'Mid range Android, 6 GB': profile(
    totalRamBytes: (5.6 * gib).round(),
    benchmark: benchmarkAt(70),
  ),
  'Flagship Android, 12 GB': profile(
    totalRamBytes: (11.2 * gib).round(),
    benchmark: benchmarkAt(300),
    cpuFeatures: const ['dotprod', 'i8mm', 'fp16'],
  ),
  'Older iPhone (iPhone 11, 4 GB)': profile(
    platform: DevicePlatform.ios,
    totalRamBytes: (3.8 * gib).round(),
    benchmark: benchmarkAt(90),
  ),
  'Recent iPhone (15 Pro, 8 GB)': profile(
    platform: DevicePlatform.ios,
    totalRamBytes: (7.5 * gib).round(),
    benchmark: benchmarkAt(350),
  ),
};

Map<String, RecommendationLabel> labelsFor(DeviceProfile device) => {
  for (final r in const RecommendationEngine().recommendAll(seedModels, device))
    r.modelId: r.label,
};

void main() {
  test('tiers of the target devices', () {
    const classifier = DeviceTierClassifier();
    expect(matrix.values.map(classifier.classify).toList(), [
      DeviceTier.low,
      DeviceTier.mid,
      DeviceTier.flagship,
      DeviceTier.low,
      DeviceTier.high,
    ]);
  });

  test('low end Android gets small models only', () {
    final labels = labelsFor(matrix['Low end Android, 4 GB']!);
    for (final big in ['qwen3-4b', 'gemma3-4b', 'llama3.2-3b', 'phi-4-mini']) {
      expect(labels[big], RecommendationLabel.notSupported, reason: big);
    }
    expect(labels['qwen3-0.6b'], isNot(RecommendationLabel.notSupported));
  });

  test('mid range Android can run up to 3B', () {
    final labels = labelsFor(matrix['Mid range Android, 6 GB']!);
    expect(labels['qwen3-0.6b'], RecommendationLabel.recommended);
    expect(labels['llama3.2-3b'], isNot(RecommendationLabel.notSupported));
  });

  test('flagship Android runs every seed model, 4B at a good speed', () {
    final labels = labelsFor(matrix['Flagship Android, 12 GB']!);
    expect(
      labels.values.every((l) => l != RecommendationLabel.notSupported),
      isTrue,
    );
    expect(labels['qwen3-4b'], RecommendationLabel.recommended);
  });

  test('older iPhone gets the 50% budget but not 4B models', () {
    final labels = labelsFor(matrix['Older iPhone (iPhone 11, 4 GB)']!);
    expect(labels['qwen3-4b'], RecommendationLabel.notSupported);
    expect(labels['qwen3-0.6b'], RecommendationLabel.recommended);
  });

  test('recent iPhone runs 4B models', () {
    final labels = labelsFor(matrix['Recent iPhone (15 Pro, 8 GB)']!);
    expect(labels['qwen3-4b'], isNot(RecommendationLabel.notSupported));
  });

  test('prints the matrix for the phase report', () {
    const engine = RecommendationEngine();
    final buffer = StringBuffer();
    for (final MapEntry(key: name, value: device) in matrix.entries) {
      buffer.writeln(
        '$name -> ${const DeviceTierClassifier().classify(device).name}',
      );
      for (final r in engine.recommendAll(seedModels, device)) {
        buffer.writeln(
          '  ${r.modelId.padRight(12)} ${r.label.name.padRight(13)} '
          '${r.estimatedTokensPerSecond.toStringAsFixed(1).padLeft(5)} tok/s '
          'ctx ${r.contextLength}',
        );
      }
    }
    // Printed for the phase report.
    // ignore: avoid_print
    print(buffer);
  });
}

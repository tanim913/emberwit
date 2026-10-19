import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/recommendation/model_spec.dart';

const int mib = 1024 * 1024;
const int gib = 1024 * mib;

/// Seed catalog models (Q4_K_M) with sizes and KV cache per token computed
/// from their published architectures: 2 * layers * kv_heads * head_dim * 2.
const qwen3Small = ModelSpec(
  id: 'qwen3-0.6b',
  parameterCount: 600000000,
  fileSizeBytes: 484 * mib,
  kvCacheBytesPerToken: 2 * 28 * 8 * 128 * 2,
);
const qwen3Medium = ModelSpec(
  id: 'qwen3-1.7b',
  parameterCount: 1700000000,
  fileSizeBytes: 1282 * mib,
  kvCacheBytesPerToken: 2 * 28 * 8 * 128 * 2,
);
const qwen3Large = ModelSpec(
  id: 'qwen3-4b',
  parameterCount: 4000000000,
  fileSizeBytes: 2497 * mib,
  kvCacheBytesPerToken: 2 * 36 * 8 * 128 * 2,
);
const gemma3Small = ModelSpec(
  id: 'gemma3-1b',
  parameterCount: 1000000000,
  fileSizeBytes: 806 * mib,
  kvCacheBytesPerToken: 2 * 26 * 1 * 256 * 2,
);
const gemma3Large = ModelSpec(
  id: 'gemma3-4b',
  parameterCount: 3900000000,
  fileSizeBytes: 2489 * mib,
  kvCacheBytesPerToken: 2 * 34 * 4 * 256 * 2,
);
const llama32Small = ModelSpec(
  id: 'llama3.2-1b',
  parameterCount: 1240000000,
  fileSizeBytes: 808 * mib,
  kvCacheBytesPerToken: 2 * 16 * 8 * 64 * 2,
);
const llama32Large = ModelSpec(
  id: 'llama3.2-3b',
  parameterCount: 3200000000,
  fileSizeBytes: 2019 * mib,
  kvCacheBytesPerToken: 2 * 28 * 8 * 128 * 2,
);
const phi4Mini = ModelSpec(
  id: 'phi-4-mini',
  parameterCount: 3800000000,
  fileSizeBytes: 2491 * mib,
  kvCacheBytesPerToken: 2 * 32 * 8 * 128 * 2,
);

const List<ModelSpec> seedModels = [
  qwen3Small,
  qwen3Medium,
  qwen3Large,
  gemma3Small,
  gemma3Large,
  llama32Small,
  llama32Large,
  phi4Mini,
];

/// Benchmark on the bundled 92 MB model at [tokensPerSecond].
BenchmarkResult benchmarkAt(double tokensPerSecond) => BenchmarkResult(
  modelName: 'SmolLM2-135M-Instruct-Q4_0',
  modelSizeBytes: 91893088,
  tokensPerSecond: tokensPerSecond,
  promptTokensPerSecond: tokensPerSecond * 4,
  timeToFirstTokenMs: 300,
  loadTimeMs: 500,
  generatedTokens: 64,
  threads: 4,
  measuredAt: DateTime.utc(2026, 9, 24, 12),
);

DeviceProfile profile({
  DevicePlatform platform = DevicePlatform.android,
  int totalRamBytes = 8 * gib,
  int freeStorageBytes = 32 * gib,
  BenchmarkResult? benchmark,
  int performanceCores = 4,
  List<String> cpuFeatures = const ['dotprod', 'fp16'],
}) => DeviceProfile(
  platform: platform,
  osVersion: platform == DevicePlatform.ios ? '17.5' : '14',
  deviceModel: 'Test',
  manufacturer: 'Test',
  isPhysicalDevice: true,
  totalRamBytes: totalRamBytes,
  availableRamBytes: totalRamBytes ~/ 2,
  freeStorageBytes: freeStorageBytes,
  totalStorageBytes: 128 * gib,
  cpuArchitecture: platform == DevicePlatform.ios ? 'arm64' : 'arm64-v8a',
  cpuCores: 8,
  performanceCores: performanceCores,
  cpuFeatures: cpuFeatures,
  gpuBackends: platform == DevicePlatform.ios ? const ['metal'] : const [],
  thermalState: ThermalState.nominal,
  benchmark: benchmark,
  profiledAt: DateTime.utc(2026, 9, 24),
);

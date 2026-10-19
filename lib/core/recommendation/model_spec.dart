import 'package:flutter/foundation.dart';

/// The facts about a model that the recommendation engine needs. The model
/// catalog converts its entries to this type.
@immutable
final class ModelSpec {
  /// Creates a spec.
  const new({
    required this.id,
    required this.parameterCount,
    required this.fileSizeBytes,
    this.recommendedContextLength = 4096,
    this.minRamBytes = 0,
    this.kvCacheBytesPerToken,
    this.isInstalled = false,
  });

  /// Catalog id.
  final String id;

  /// Number of parameters.
  final int parameterCount;

  /// Size of the GGUF file in bytes.
  final int fileSizeBytes;

  /// Largest context the catalog suggests for this model.
  final int recommendedContextLength;

  /// Minimum total device RAM the catalog requires, 0 for none.
  final int minRamBytes;

  /// KV cache size per token of context (f16 keys and values, all layers).
  /// Computed from the GGUF metadata when the catalog is built:
  /// `2 * layers * kv_heads * head_dim * 2 bytes`. `null` falls back to a
  /// conservative estimate from [parameterCount].
  final int? kvCacheBytesPerToken;

  /// Whether the model is already downloaded (storage rule does not apply).
  final bool isInstalled;
}

const int _kib = 1024;

/// KV cache bytes per token for [spec], exact when the catalog provides it.
///
/// The fallback deliberately overestimates for most architectures: real
/// values range from 26 KiB (Gemma 3 1B, one KV head) to 144 KiB (Qwen3 4B).
int kvCacheBytesPerToken(ModelSpec spec) {
  final exact = spec.kvCacheBytesPerToken;
  if (exact != null) return exact;
  final billions = spec.parameterCount / 1e9;
  if (billions < 1.5) return 112 * _kib;
  if (billions < 5) return 160 * _kib;
  if (billions < 10) return 256 * _kib;
  return 384 * _kib;
}

import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/engine/llama/cancel_flag.dart';
import 'package:emberwit/engine/llama/llama_inference_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GenerationStats _stats({
  int prompt = 10,
  int generated = 11,
  int ttftMs = 500,
  int totalMs = 1500,
}) => GenerationStats(
  promptTokens: prompt,
  generatedTokens: generated,
  timeToFirstToken: Duration(milliseconds: ttftMs),
  totalDuration: Duration(milliseconds: totalMs),
  stopReason: StopReason.maxTokens,
);

void main() {
  group('GenerationStats', () {
    test('computes decode and prompt speed', () {
      final stats = _stats();
      // 10 tokens after the first, in one second.
      expect(stats.tokensPerSecond, closeTo(10, 0.001));
      expect(stats.promptTokensPerSecond, closeTo(20, 0.001));
      expect(stats.totalTokens, 21);
    });

    test('reports zero speed when there is nothing to measure', () {
      expect(_stats(generated: 1).tokensPerSecond, 0);
      expect(_stats(ttftMs: 1500).tokensPerSecond, 0);
      expect(_stats(prompt: 0).promptTokensPerSecond, 0);
      expect(_stats(ttftMs: 0).promptTokensPerSecond, 0);
    });
  });

  test('requests and settings are value types', () {
    const load = LoadModelRequest(path: '/m.gguf');
    expect(load, const LoadModelRequest(path: '/m.gguf'));
    expect(load.hashCode, const LoadModelRequest(path: '/m.gguf').hashCode);
    expect(load, isNot(const LoadModelRequest(path: '/m.gguf', threads: 2)));

    const sampling = SamplingSettings(seed: 1);
    expect(sampling, const SamplingSettings(seed: 1));
    expect(sampling.hashCode, const SamplingSettings(seed: 1).hashCode);
    expect(sampling, isNot(const SamplingSettings()));

    const turn = ChatTurn(role: ChatRole.user, content: 'hi');
    expect(turn, const ChatTurn(role: ChatRole.user, content: 'hi'));
    expect(
      turn.hashCode,
      const ChatTurn(role: ChatRole.user, content: 'hi').hashCode,
    );

    expect(const RawPrompt('a'), const RawPrompt('a'));
    expect(const RawPrompt('a').hashCode, const RawPrompt('a').hashCode);
    expect(const ChatPrompt([turn]), const ChatPrompt([turn]));
    expect(
      const ChatPrompt([turn]).hashCode,
      const ChatPrompt([turn]).hashCode,
    );
    expect(const ChatPrompt([turn]), isNot(const RawPrompt('a')));
  });

  test(
    'inferenceEngineProvider builds a llama engine and disposes it',
    () async {
      final container = ProviderContainer.test(
        overrides: [
          appLoggerProvider.overrideWithValue(const SilentAppLogger()),
        ],
      );
      final engine = container.read(inferenceEngineProvider);
      expect(engine, isA<LlamaInferenceEngine>());
      expect(engine.state, EngineState.idle);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(
        (await engine
                .generate(const GenerationRequest(prompt: RawPrompt('x')))
                .single)
            as GenerationFailed,
        isA<GenerationFailed>(),
      );
    },
  );

  test('cancel flags set and clear', () {
    final native = NativeCancelFlag.allocate();
    addTearDown(native.free);
    final view = NativeCancelFlag.fromAddress(native.address);
    expect(view.isSet, isFalse);
    native.set();
    expect(view.isSet, isTrue);
    view.clear();
    expect(native.isSet, isFalse);

    final memory = MemoryCancelFlag()..set();
    expect(memory.isSet, isTrue);
    memory.clear();
    expect(memory.isSet, isFalse);
  });
}

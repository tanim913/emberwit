@Tags(['native'])
library;

import 'dart:io';

import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/engine/llama/llama_inference_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_ffi/llama_ffi.dart';

/// Host build of the native libraries (packages/llama_ffi/tool/build_host.sh).
final String? _libDir = Platform.environment['LLAMA_FFI_LIB_DIR'];
const String _model = 'packages/llama_ffi/test/fixtures/stories260K.gguf';

String? get _skip {
  if (_libDir == null) return 'LLAMA_FFI_LIB_DIR not set';
  if (!File(_model).existsSync()) return 'test model missing';
  return null;
}

/// End to end: the real llama.cpp runtime inside the real worker isolate.
void main() {
  group('LlamaInferenceEngine with llama.cpp', skip: _skip, () {
    late LlamaInferenceEngine engine;

    setUpAll(() {
      final dir = _libDir!;
      engine = LlamaInferenceEngine(
        runtimeFactory: () => FfiLlamaRuntime(libraryDirectory: dir),
        processorCount: 2,
      );
    });

    tearDownAll(() => engine.dispose());

    test('loads the model with progress', () async {
      final events = await engine
          .loadModel(
            LoadModelRequest(
              path: File(_model).absolute.path,
              contextLength: 256,
            ),
          )
          .toList();
      final loaded = events.last as ModelLoaded;
      expect(events.whereType<ModelLoadProgress>().last.fraction, 1.0);
      expect(loaded.info.architecture, 'llama');
      expect(loaded.info.devices, contains('CPU'));
    });

    test('generates text greedily and reports speed', () async {
      final events = await engine
          .generate(
            const GenerationRequest(
              prompt: RawPrompt('Once upon a time'),
              sampling: SamplingSettings(temperature: 0),
              maxTokens: 24,
            ),
          )
          .toList();
      final text = events.whereType<TokenGenerated>().map((e) => e.text).join();
      final stats = (events.last as GenerationCompleted).stats;
      expect(text.trim(), isNotEmpty);
      expect(stats.generatedTokens, greaterThan(0));
      expect(stats.tokensPerSecond, greaterThan(0));
      // Benchmark line for the test report.
      // ignore: avoid_print
      print(
        'stories260K: ${stats.promptTokens} prompt tokens, '
        '${stats.generatedTokens} generated, '
        'TTFT ${stats.timeToFirstToken.inMilliseconds} ms, '
        '${stats.tokensPerSecond.toStringAsFixed(1)} tok/s',
      );
    });

    test('unloads', () async {
      expect((await engine.unloadModel()).isOk, isTrue);
      expect(engine.state, EngineState.idle);
    });
  });
}

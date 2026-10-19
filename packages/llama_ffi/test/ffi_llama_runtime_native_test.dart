@Tags(['native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llama_ffi/llama_ffi.dart';

import 'native_test_support.dart';

void main() {
  late FfiLlamaRuntime runtime;

  const modelParams = LlamaModelParams();
  const contextParams = LlamaContextParams(contextLength: 128, threads: 2);

  setUpAll(() {
    if (nativeSkipReason != null) return;
    runtime = FfiLlamaRuntime(libraryDirectory: nativeLibDir);
  });

  tearDownAll(() {
    if (nativeSkipReason != null) return;
    runtime.dispose();
  });

  group('FfiLlamaRuntime', skip: nativeSkipReason, () {
    test('reports a CPU device', () {
      expect(runtime.devices.map((d) => d.type), contains(LlamaDeviceType.cpu));
    });

    test('rejects missing and non GGUF files', () {
      expect(
        () => runtime.load(
          'test/fixtures/missing.gguf',
          modelParams: modelParams,
          contextParams: contextParams,
        ),
        throwsA(
          isA<LlamaException>().having(
            (e) => e.code,
            'code',
            LlamaErrorCode.fileNotFound,
          ),
        ),
      );
      final notGguf = File('${Directory.systemTemp.path}/not_a_model.gguf')
        ..writeAsStringSync('hello, this is not a model');
      addTearDown(notGguf.deleteSync);
      expect(
        () => runtime.load(
          notGguf.path,
          modelParams: modelParams,
          contextParams: contextParams,
        ),
        throwsA(
          isA<LlamaException>().having(
            (e) => e.code,
            'code',
            LlamaErrorCode.invalidFormat,
          ),
        ),
      );
      expect(runtime.isLoaded, isFalse);
    });

    test('fails every model operation before a model is loaded', () {
      expect(() => runtime.tokenize('x'), throwsA(isA<LlamaException>()));
      expect(() => runtime.metadata, throwsA(isA<LlamaException>()));
      expect(() => runtime.setThreads(1), throwsA(isA<LlamaException>()));
    });

    test('can cancel loading through the progress callback', () {
      expect(
        () => runtime.load(
          testModelPath,
          modelParams: modelParams,
          contextParams: contextParams,
          onProgress: (_) => false,
        ),
        throwsA(
          isA<LlamaException>().having(
            (e) => e.code,
            'code',
            LlamaErrorCode.loadCancelled,
          ),
        ),
      );
      expect(runtime.isLoaded, isFalse);
    });

    test('loads, reports progress and reads metadata', () {
      final progress = <double>[];
      final meta = runtime.load(
        testModelPath,
        modelParams: modelParams,
        contextParams: contextParams,
        onProgress: (p) {
          progress.add(p);
          return true;
        },
      );
      expect(runtime.isLoaded, isTrue);
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      expect(meta.architecture, 'llama');
      // llama.cpp pads the context to a multiple of 256.
      expect(meta.contextLength, greaterThanOrEqualTo(128));
      expect(meta.parameterCount, greaterThan(0));
      expect(meta.sizeBytes, greaterThan(0));
      expect(meta.description, isNotEmpty);
      expect(runtime.metadata, same(meta));
    });

    test('tokenizes and detokenizes round trip', () {
      final tokens = runtime.tokenize('Once upon a time', addSpecial: false);
      expect(tokens, isNotEmpty);
      final bytes = tokens.expand(runtime.tokenBytes).toList();
      expect(utf8.decode(bytes).trim(), 'Once upon a time');
      final withBos = runtime.tokenize('Once upon a time');
      expect(withBos.length, tokens.length + 1);
    });

    test('generates tokens greedily and deterministically', () {
      List<int> run() {
        runtime
          ..clearContext()
          ..configureSampler(const LlamaSamplerParams(temperature: 0))
          ..decode(runtime.tokenize('Once upon a time'));
        final out = <int>[];
        for (var i = 0; i < 12; i++) {
          final token = runtime.sample();
          if (runtime.isEndOfGeneration(token)) break;
          out.add(token);
          runtime.decode([token]);
        }
        return out;
      }

      final first = run();
      expect(first, isNotEmpty);
      expect(run(), first);
      expect(runtime.usedContext, greaterThan(first.length));
      // Fewer threads (heat or battery throttling) give the same output.
      runtime.setThreads(1);
      expect(run(), first);
      expect(() => runtime.setThreads(0), throwsArgumentError);
    });

    test('samples with temperature and a fixed seed', () {
      runtime
        ..clearContext()
        ..configureSampler(const LlamaSamplerParams(seed: 42, temperature: 1))
        ..decode(runtime.tokenize('The dog'));
      expect(runtime.sample(), isNonNegative);
    });

    test('reports a full context and rejects oversized batches', () {
      runtime.clearContext();
      final tokens = runtime.tokenize('one two three four five six seven');
      var failed = false;
      try {
        for (var i = 0; i < 200; i++) {
          runtime.decode(tokens);
        }
      } on LlamaException catch (e) {
        failed = e.code == LlamaErrorCode.contextFull;
      }
      expect(failed, isTrue);
      expect(
        () => runtime.decode(List.filled(600, tokens.first)),
        throwsArgumentError,
      );
    });

    test('applies an explicit chat template', () {
      final prompt = runtime.applyChatTemplate(const [
        LlamaChatMessage(role: 'system', content: 'Be brief.'),
        LlamaChatMessage(role: 'user', content: 'Hi'),
      ], template: 'chatml');
      expect(prompt, contains('<|im_start|>user\nHi<|im_end|>'));
      expect(prompt, endsWith('<|im_start|>assistant\n'));
    });

    test('fails without an embedded or known template', () {
      expect(
        () => runtime.applyChatTemplate(const [
          LlamaChatMessage(role: 'user', content: 'Hi'),
        ], template: 'no-such-template'),
        throwsA(isA<LlamaException>()),
      );
    });

    test('unloads and can be disposed twice', () {
      runtime.unload();
      expect(runtime.isLoaded, isFalse);
      runtime.unload();
    });
  });
}

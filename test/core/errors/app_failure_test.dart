import 'package:emberwit/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFailure', () {
    test('UnexpectedFailure has a stable code and hides cause details', () {
      final failure = UnexpectedFailure(
        cause: const FormatException('secret user text'),
        stackTrace: StackTrace.current,
      );
      expect(failure.code, 'unexpected');
      expect(
        failure.toString(),
        'AppFailure(unexpected, cause: FormatException)',
      );
      expect(failure.toString(), isNot(contains('secret')));
      expect(const UnexpectedFailure().toString(), 'AppFailure(unexpected)');
    });

    test('ConfigurationFailure compares by detail', () {
      const a = ConfigurationFailure('x');
      expect(a.code, 'configuration');
      expect(a, const ConfigurationFailure('x'));
      expect(a, isNot(const ConfigurationFailure('y')));
      expect(a.hashCode, const ConfigurationFailure('x').hashCode);
      expect(a.toString(), 'AppFailure(configuration, x)');
    });

    test('runtime and archive failures carry their reason in the code', () {
      const hot = RuntimeLimitFailure(RuntimeLimitReason.overheated);
      expect(hot.code, 'runtime.overheated');
      expect(hot, const RuntimeLimitFailure(RuntimeLimitReason.overheated));
      expect(
        hot,
        isNot(const RuntimeLimitFailure(RuntimeLimitReason.batteryCritical)),
      );
      expect(
        hot.hashCode,
        const RuntimeLimitFailure(RuntimeLimitReason.overheated).hashCode,
      );
      const wrong = ArchiveFailure(ArchiveFailureReason.wrongPassphrase);
      expect(wrong.code, 'archive.wrongPassphrase');
      expect(wrong, const ArchiveFailure(ArchiveFailureReason.wrongPassphrase));
      expect(
        wrong,
        isNot(const ArchiveFailure(ArchiveFailureReason.notAnArchive)),
      );
      expect(
        wrong.hashCode,
        const ArchiveFailure(ArchiveFailureReason.wrongPassphrase).hashCode,
      );
    });

    test('switch over the sealed hierarchy is exhaustive', () {
      String label(AppFailure f) => switch (f) {
        UnexpectedFailure() => 'u',
        ConfigurationFailure() => 'c',
        ModelLoadFailure() => 'm',
        NoModelLoadedFailure() => 'n',
        EngineBusyFailure() => 'b',
        ContextOverflowFailure() => 'o',
        GenerationFailure() => 'g',
        DeviceProfilingFailure() => 'd',
        BenchmarkUnavailableFailure() => 'x',
        CatalogFailure() => 'cat',
        DownloadFailure() => 'dl',
        ImportFailure() => 'imp',
        ModelNotFoundFailure() => 'nf',
        RuntimeLimitFailure() => 'rt',
        ArchiveFailure() => 'ar',
      };
      expect(label(const UnexpectedFailure()), 'u');
      expect(label(const ConfigurationFailure('x')), 'c');
      expect(label(const EngineBusyFailure()), 'b');
    });

    test('engine failures have stable codes and value equality', () {
      const load = ModelLoadFailure(ModelLoadFailureReason.insufficientMemory);
      expect(load.code, 'model_load.insufficientMemory');
      expect(
        load,
        const ModelLoadFailure(ModelLoadFailureReason.insufficientMemory),
      );
      expect(
        load,
        isNot(const ModelLoadFailure(ModelLoadFailureReason.cancelled)),
      );
      expect(load.hashCode, isNot(0));

      expect(const NoModelLoadedFailure().code, 'no_model_loaded');
      expect(const NoModelLoadedFailure(), const NoModelLoadedFailure());
      expect(
        const NoModelLoadedFailure().hashCode,
        const NoModelLoadedFailure().hashCode,
      );
      expect(const EngineBusyFailure().code, 'engine_busy');
      expect(const EngineBusyFailure(), const EngineBusyFailure());
      expect(
        const EngineBusyFailure().hashCode,
        const EngineBusyFailure().hashCode,
      );

      const overflow = ContextOverflowFailure(
        promptTokens: 10,
        contextLength: 8,
      );
      expect(overflow.code, 'context_overflow');
      expect(
        overflow,
        const ContextOverflowFailure(promptTokens: 10, contextLength: 8),
      );
      expect(
        overflow.hashCode,
        const ContextOverflowFailure(
          promptTokens: 10,
          contextLength: 8,
        ).hashCode,
      );

      const profiling = DeviceProfilingFailure('snapshot');
      expect(profiling.code, 'device_profiling');
      expect(profiling, const DeviceProfilingFailure('snapshot'));
      expect(
        profiling.hashCode,
        const DeviceProfilingFailure('snapshot').hashCode,
      );
      expect(const BenchmarkUnavailableFailure().code, 'benchmark_unavailable');
      expect(
        const BenchmarkUnavailableFailure(),
        const BenchmarkUnavailableFailure(),
      );
      expect(
        const BenchmarkUnavailableFailure().hashCode,
        const BenchmarkUnavailableFailure().hashCode,
      );

      const generation = GenerationFailure('decode failed');
      expect(generation.code, 'generation');
      expect(generation, const GenerationFailure('decode failed'));
      expect(
        generation.hashCode,
        const GenerationFailure('decode failed').hashCode,
      );
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_debug_controller.freezed.dart';
part 'engine_debug_controller.g.dart';

/// Folder the debug screen scans for GGUF files: `<app support>/models`.
///
/// On Android this is `/data/user/0/<app id>/files/models`, which
/// `tool/push_debug_model.sh` fills. The model manager feature takes over
/// model storage in a later phase.
@riverpod
Future<Directory> debugModelsDirectory(Ref ref) async {
  final support = ref.watch(appSupportDirectoryProvider);
  return Directory('${support.path}${Platform.pathSeparator}models')
    ..createSync(recursive: true);
}

/// State of the engine debug screen.
@freezed
abstract class EngineDebugState with _$EngineDebugState {
  /// Creates the state.
  const factory({
    /// GGUF files found in the models folder.
    @Default(<String>[]) List<String> models,

    /// Model chosen for loading.
    String? selectedModel,

    /// Folder that was scanned, shown when it is empty.
    String? modelsDirectory,

    /// Engine state.
    @Default(EngineState.idle) EngineState engineState,

    /// Load progress from 0 to 1 while loading.
    double? loadProgress,

    /// The loaded model.
    ModelInfo? model,

    /// How long the model took to load.
    Duration? loadDuration,

    /// Text generated so far.
    @Default('') String output,

    /// Stats of the last finished generation.
    GenerationStats? stats,

    /// Last error, shown until the next action.
    AppFailure? failure,

    /// Format the prompt with the model's chat template.
    @Default(true) bool useChatTemplate,

    /// Output length limit.
    @Default(128) int maxTokens,

    /// Sampling temperature.
    @Default(0.7) double temperature,
  }) = _EngineDebugState;
}

/// Drives the engine debug screen: pick a model, load it, prompt it.
@riverpod
class EngineDebugController extends _$EngineDebugController {
  StreamSubscription<ModelLoadEvent>? _load;
  StreamSubscription<GenerationEvent>? _generation;

  InferenceEngine get _engine => ref.read(inferenceEngineProvider);

  @override
  EngineDebugState build() {
    final engine = ref.watch(inferenceEngineProvider);
    final states = engine.stateChanges.listen(
      (s) => state = state.copyWith(engineState: s),
    );
    ref.onDispose(() {
      unawaited(states.cancel());
      unawaited(_load?.cancel());
      unawaited(_generation?.cancel());
    });
    unawaited(refreshModels());
    unawaited(_restoreLoadedModel(engine));
    return EngineDebugState(engineState: engine.state);
  }

  Future<void> _restoreLoadedModel(InferenceEngine engine) async {
    final stats = await engine.getStats();
    if (!ref.mounted || stats.model == null) return;
    state = state.copyWith(
      model: stats.model,
      loadDuration: stats.loadDuration,
      selectedModel: state.selectedModel ?? stats.model!.path,
    );
  }

  /// Rescans the models folder.
  Future<void> refreshModels() async {
    final dir = await ref.read(debugModelsDirectoryProvider.future);
    final models =
        dir
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => p.toLowerCase().endsWith('.gguf'))
            .toList()
          ..sort();
    if (!ref.mounted) return;
    final selected = models.contains(state.selectedModel)
        ? state.selectedModel
        : (models.isEmpty ? null : models.first);
    state = state.copyWith(
      models: models,
      modelsDirectory: dir.path,
      selectedModel: selected,
    );
  }

  /// Chooses the model to load.
  void select(String? path) => state = state.copyWith(selectedModel: path);

  /// Loads the selected model.
  void load() {
    final path = state.selectedModel;
    if (path == null) return;
    state = state.copyWith(
      loadProgress: 0,
      failure: null,
      model: null,
      loadDuration: null,
      stats: null,
      output: '',
    );
    unawaited(_load?.cancel());
    _load = _engine.loadModel(LoadModelRequest(path: path)).listen((event) {
      state = switch (event) {
        ModelLoadProgress(:final fraction) => state.copyWith(
          loadProgress: fraction,
        ),
        ModelLoaded(:final info, :final duration) => state.copyWith(
          loadProgress: null,
          model: info,
          loadDuration: duration,
        ),
        ModelLoadFailed(:final failure) => state.copyWith(
          loadProgress: null,
          failure: failure,
        ),
      };
    });
  }

  /// Frees the loaded model.
  Future<void> unload() async {
    final result = await _engine.unloadModel();
    if (!ref.mounted) return;
    state = state.copyWith(
      model: null,
      loadDuration: null,
      failure: result.failureOrNull,
    );
  }

  /// Generates a reply to [prompt].
  void generate(String prompt) {
    if (prompt.trim().isEmpty) return;
    state = state.copyWith(output: '', stats: null, failure: null);
    final request = GenerationRequest(
      prompt: state.useChatTemplate
          ? ChatPrompt([ChatTurn(role: ChatRole.user, content: prompt)])
          : RawPrompt(prompt),
      maxTokens: state.maxTokens,
      sampling: SamplingSettings(temperature: state.temperature),
    );
    unawaited(_generation?.cancel());
    _generation = _engine.generate(request).listen((event) {
      state = switch (event) {
        TokenGenerated(:final text) => state.copyWith(
          output: state.output + text,
        ),
        GenerationCompleted(:final stats) => state.copyWith(stats: stats),
        GenerationFailed(:final failure) => state.copyWith(failure: failure),
      };
    });
  }

  /// Stops the running generation or load.
  Future<void> stop() => _engine.cancel();

  /// Toggles chat template formatting.
  void setUseChatTemplate({required bool value}) =>
      state = state.copyWith(useChatTemplate: value);

  /// Sets the output length limit.
  void setMaxTokens(int value) => state = state.copyWith(maxTokens: value);

  /// Sets the sampling temperature.
  void setTemperature(double value) =>
      state = state.copyWith(temperature: value);
}

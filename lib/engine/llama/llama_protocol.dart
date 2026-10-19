import 'dart:isolate';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/engine/engine_models.dart';
import 'package:llama_ffi/llama_ffi.dart';

/// Everything the worker isolate needs to start.
final class WorkerBootstrap {
  /// Creates the bootstrap message.
  const new({
    required this.events,
    required this.runtimeFactory,
    required this.cancelFlagAddress,
  });

  /// Where the worker sends [WorkerEvent]s.
  final SendPort events;

  /// Creates the runtime inside the worker. Must be a top level function or
  /// a closure over sendable values.
  final LlamaRuntime Function() runtimeFactory;

  /// Address of the shared native cancel flag.
  final int cancelFlagAddress;
}

/// A request from the engine to the worker. Every command carries an [id]
/// that its resulting events repeat.
sealed class WorkerCommand {
  const new(this.id);

  /// Correlation id.
  final int id;
}

/// Load a model with fully resolved parameters.
final class LoadCommand extends WorkerCommand {
  /// Creates the command.
  const new(
    super.id, {
    required this.request,
    required this.threads,
    required this.gpuLayers,
  });

  /// What to load.
  final LoadModelRequest request;

  /// CPU threads to use.
  final int threads;

  /// GPU layers to offload.
  final int gpuLayers;
}

/// Generate text.
final class GenerateCommand extends WorkerCommand {
  /// Creates the command.
  const new(super.id, this.request);

  /// What to generate.
  final GenerationRequest request;
}

/// Count the tokens of a text.
final class CountTokensCommand extends WorkerCommand {
  /// Creates the command.
  const new(super.id, this.text);

  /// Text to tokenize.
  final String text;
}

/// Free the loaded model.
final class UnloadCommand extends WorkerCommand {
  /// Creates the command.
  const new(super.id);
}

/// Free everything and stop the worker.
final class ShutdownCommand extends WorkerCommand {
  /// Creates the command.
  const new(super.id);
}

/// A message from the worker to the engine.
sealed class WorkerEvent {
  const new();
}

/// The worker is running and accepts commands on [commands].
final class WorkerReady extends WorkerEvent {
  /// Creates the event.
  const new(this.commands);

  /// Port for [WorkerCommand]s.
  final SendPort commands;
}

/// An event answering the command with [id].
sealed class CommandEvent extends WorkerEvent {
  const new(this.id);

  /// Id of the command this answers.
  final int id;
}

/// Load progress, 0 to 1.
final class LoadProgressEvent extends CommandEvent {
  /// Creates the event.
  const new(super.id, this.fraction);

  /// Portion loaded.
  final double fraction;
}

/// The model finished loading.
final class LoadedEvent extends CommandEvent {
  /// Creates the event.
  const new(super.id, this.info, this.duration);

  /// The loaded model.
  final ModelInfo info;

  /// Load time.
  final Duration duration;
}

/// A piece of generated text.
final class TokenEvent extends CommandEvent {
  /// Creates the event.
  const new(super.id, this.text);

  /// Text to append.
  final String text;
}

/// Generation finished.
final class GenerationDoneEvent extends CommandEvent {
  /// Creates the event.
  const new(super.id, this.stats);

  /// Measurements.
  final GenerationStats stats;
}

/// Result of a [CountTokensCommand].
final class TokenCountEvent extends CommandEvent {
  /// Creates the event.
  const new(super.id, this.count);

  /// Number of tokens.
  final int count;
}

/// A command without a result payload finished.
final class DoneEvent extends CommandEvent {
  /// Creates the event.
  const new(super.id);
}

/// The command failed.
final class FailedEvent extends CommandEvent {
  /// Creates the event.
  const new(super.id, this.failure);

  /// What went wrong.
  final AppFailure failure;
}

import 'dart:async';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/core/runtime/runtime_policy.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/chat_repository.dart';
import 'package:emberwit/features/chat/domain/chat_template.dart';
import 'package:emberwit/features/chat/domain/context_window.dart';
import 'package:emberwit/features/chat/domain/device_actions.dart';
import 'package:emberwit/features/chat/domain/device_command.dart';
import 'package:emberwit/features/chat/domain/reply_language.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Progress of a reply.
@immutable
sealed class ReplyEvent {
  const new();
}

/// The model is loading ([fraction] 0 to 1).
final class ReplyLoadingModel extends ReplyEvent {
  /// Creates the event.
  const new(this.fraction);

  /// Load progress.
  final double fraction;
}

/// Generation started. [droppedMessages] older messages did not fit.
final class ReplyStarted extends ReplyEvent {
  /// Creates the event.
  const new(this.message, this.droppedMessages);

  /// The assistant message being written (empty content).
  final ChatMessage message;

  /// Older messages left out of the context.
  final int droppedMessages;
}

/// More text arrived. [content] is the full reply so far.
final class ReplyText extends ReplyEvent {
  /// Creates the event.
  const new(this.content);

  /// Reply so far.
  final String content;
}

/// The reply is finished (or stopped) and saved.
final class ReplyFinished extends ReplyEvent {
  /// Creates the event.
  const new(this.message);

  /// The saved assistant message.
  final ChatMessage message;
}

/// The reply could not be produced.
final class ReplyFailed extends ReplyEvent {
  /// Creates the event.
  const new(this.failure);

  /// What went wrong.
  final AppFailure failure;
}

RuntimeAdvice _fullSpeed() => RuntimeAdvice.normal;

/// Title given to conversations before their first message.
const int _titleLength = 48;

/// Answers messages in a conversation with the on-device model.
///
/// For each message: saves it, picks and loads the conversation's model
/// (with its context length), keeps as much history as fits in the context
/// ([ContextWindowPlanner]), formats it with the model family's
/// [ChatTemplate], streams the reply and saves it with its stats. Nothing
/// leaves the device.
///
/// Short commands (set an alarm or timer, flashlight, open an app) are run
/// with [DeviceActions] instead and answered with a confirmation, without
/// the model.
final class ChatResponder {
  /// Creates the responder.
  new({
    required this._engine,
    required this._models,
    required this._repository,
    required this._threads,
    this._advice = _fullSpeed,
    this._actions,
    this.busyWait = const Duration(seconds: 30),
    this._planner = const ContextWindowPlanner(),
    this._clock = const SystemClock(),
    this._uuid = const Uuid(),
  });

  final InferenceEngine _engine;
  final ModelLibrary _models;
  final ChatRepository _repository;
  final int Function() _threads;
  final RuntimeAdvice Function() _advice;
  final DeviceActions? _actions;

  /// Longest wait for earlier work to stop before a new reply.
  final Duration busyWait;
  final ContextWindowPlanner _planner;
  final Clock _clock;
  final Uuid _uuid;

  /// Model that will answer in [conversation]: its chosen model if still
  /// installed, otherwise the most recently installed one.
  InstalledModel? modelFor(Conversation conversation) {
    final installed = _models.state.installed;
    final chosen = conversation.settings.modelId;
    if (chosen != null) {
      final model = _models.state.installedModel(chosen);
      if (model != null) return model;
    }
    return installed.isEmpty ? null : installed.first;
  }

  /// Sends [text] as the user in [conversation] and streams the reply.
  ///
  /// [untitled] is the placeholder title; a conversation still carrying it
  /// is renamed after its first message.
  Stream<ReplyEvent> send({
    required Conversation conversation,
    required String text,
    String? untitled,
  }) async* {
    final content = text.trim();
    if (content.isEmpty) return;
    await _repository.saveMessage(
      ChatMessage(
        id: _uuid.v4(),
        conversationId: conversation.id,
        role: MessageRole.user,
        content: content,
        createdAt: _clock.now(),
      ),
    );
    if (untitled != null && conversation.title == untitled) {
      final firstLine = content.split('\n').first.trim();
      await _repository.rename(
        conversation.id,
        firstLine.length > _titleLength
            ? '${firstLine.substring(0, _titleLength)}…'
            : firstLine,
      );
    }
    final done = await _runCommand(conversation, content);
    if (done != null) {
      yield ReplyFinished(done);
      return;
    }
    yield* _reply(conversation);
  }

  /// Runs [text] as a phone action (alarm, timer, flashlight, opening an
  /// app) when it is one, and saves the confirmation as the reply. Returns
  /// `null` when it is not, so the model answers.
  Future<ChatMessage?> _runCommand(
    Conversation conversation,
    String text,
  ) async {
    final actions = _actions;
    if (actions == null || !actions.supported) return null;
    final command = DeviceCommand.parse(text, now: _clock.now());
    if (command == null) return null;
    final said = await runDeviceCommand(
      command,
      actions,
      ReplyLanguage.detect(text) ?? ReplyLanguage.english,
    );
    if (said == null) return null;
    final reply = ChatMessage(
      id: _uuid.v4(),
      conversationId: conversation.id,
      role: MessageRole.assistant,
      content: said,
      createdAt: _clock.now(),
    );
    await _repository.saveMessage(reply);
    return reply;
  }

  /// Stops the reply being generated. It is saved as stopped.
  Future<void> stop() => _engine.cancel();

  /// Stops a load or reply still running (one a closed chat left behind)
  /// and waits until the engine is free. False when it never frees.
  Future<bool> _engineFree() async {
    bool busy() =>
        _engine.state == EngineState.loading ||
        _engine.state == EngineState.generating;
    if (!busy()) return true;
    final free = _engine.stateChanges
        .firstWhere(
          (s) => s != EngineState.loading && s != EngineState.generating,
        )
        .then((_) => true)
        .timeout(busyWait, onTimeout: () => !busy());
    await _engine.cancel();
    if (!busy()) {
      free.ignore();
      return true;
    }
    return await free;
  }

  /// With [retry], a model that disappears between loading and generating
  /// (the OS asked for memory at that moment) is loaded again once instead
  /// of failing the reply.
  Stream<ReplyEvent> _reply(
    Conversation conversation, {
    bool retry = true,
  }) async* {
    final settings = conversation.settings;
    final model = modelFor(conversation);
    if (model == null) {
      yield const ReplyFailed(NoModelLoadedFailure());
      return;
    }
    // Heat and battery limits: refuse when critical, slow down when not.
    final advice = _advice();
    if (!advice.canGenerate) {
      yield ReplyFailed(
        RuntimeLimitFailure(
          advice.concerns.contains(RuntimeConcern.overheated)
              ? RuntimeLimitReason.overheated
              : RuntimeLimitReason.batteryCritical,
        ),
      );
      return;
    }

    // A reply left running by a chat the user moved away from is still
    // stopping: wait for it instead of failing as busy.
    if (!await _engineFree()) {
      yield const ReplyFailed(EngineBusyFailure());
      return;
    }

    // Load the model unless it is already loaded with this context.
    final path = _models.pathOf(model);
    var info = (await _engine.getStats()).model;
    if (info == null ||
        info.path != path ||
        info.contextLength < settings.contextLength) {
      ModelLoadFailed? loadFailed;
      await for (final event in _engine.loadModel(
        LoadModelRequest(
          path: path,
          contextLength: settings.contextLength,
          threads: _threads(),
        ),
      )) {
        switch (event) {
          case ModelLoadProgress(:final fraction):
            yield ReplyLoadingModel(fraction);
          case ModelLoaded():
            info = event.info;
          case ModelLoadFailed():
            loadFailed = event;
        }
      }
      if (loadFailed != null) {
        yield ReplyFailed(loadFailed.failure);
        return;
      }
    }

    final template =
        ChatTemplate.byId(model.catalogEntry?.chatTemplate) ??
        ChatTemplate.detect(info?.chatTemplate);
    final history = [
      for (final m in await _repository.messages(conversation.id))
        if (m.status != MessageStatus.failed &&
            m.status != MessageStatus.streaming &&
            (m.role == MessageRole.user || m.content.trim().isNotEmpty))
          (
            role: m.role,
            content: m.role == MessageRole.assistant
                ? stripThinking(m.content)
                : m.content,
          ),
    ];

    // Answer in the language of the newest message, whatever the app's
    // language or the earlier messages are.
    final language = ReplyLanguage.forConversation([
      for (final turn in history)
        if (turn.role == MessageRole.user) turn.content,
    ]);
    final system =
        language?.appendTo(settings.systemPrompt) ?? settings.systemPrompt;

    final planned = await _planner.plan(
      turns: history,
      contextLength: info?.contextLength ?? settings.contextLength,
      maxTokens: settings.maxTokens,
      build: (turns) => template.format(system: system, turns: turns).text,
      count: _engine.countTokens,
    );
    final ContextPlan plan;
    switch (planned) {
      case Err(:final failure):
        if (retry && failure is NoModelLoadedFailure) {
          yield* _reply(conversation, retry: false);
          return;
        }
        yield ReplyFailed(failure);
        return;
      case Ok(:final value):
        plan = value;
    }
    final prompt = template.format(system: system, turns: plan.turns);

    var reply = ChatMessage(
      id: _uuid.v4(),
      conversationId: conversation.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: _clock.now(),
      status: MessageStatus.streaming,
      modelId: model.id,
      droppedMessages: plan.droppedMessages,
    );
    await _repository.saveMessage(reply);
    yield ReplyStarted(reply, plan.droppedMessages);

    final buffer = StringBuffer();
    await for (final event in _engine.generate(
      GenerationRequest(
        prompt: RawPrompt(prompt.text),
        sampling: SamplingSettings(
          temperature: settings.temperature,
          topP: settings.topP,
        ),
        maxTokens: plan.maxTokens,
        stopSequences: prompt.stopSequences,
        threads: advice.reduced
            ? advice.threadsFor(info?.threads ?? _threads())
            : null,
      ),
    )) {
      switch (event) {
        case TokenGenerated(:final text):
          buffer.write(text);
          yield ReplyText(buffer.toString());
        case GenerationCompleted(:final stats):
          reply = reply.copyWith(
            content: buffer.toString().trimRight(),
            status: stats.stopReason == StopReason.cancelled
                ? MessageStatus.stopped
                : MessageStatus.complete,
            stats: MessageStats(
              promptTokens: stats.promptTokens,
              generatedTokens: stats.generatedTokens,
              timeToFirstTokenMs: stats.timeToFirstToken.inMilliseconds,
              tokensPerSecond: stats.tokensPerSecond,
            ),
          );
          await _repository.saveMessage(reply);
          yield ReplyFinished(reply);
        case GenerationFailed(:final failure)
            when retry && failure is NoModelLoadedFailure && buffer.isEmpty:
          await _repository.deleteMessage(reply.id);
          yield* _reply(conversation, retry: false);
          return;
        case GenerationFailed(:final failure):
          reply = reply.copyWith(
            content: buffer.toString().trimRight(),
            status: MessageStatus.failed,
          );
          await _repository.saveMessage(reply);
          yield ReplyFailed(failure);
      }
    }
  }
}

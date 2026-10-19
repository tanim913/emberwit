import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/chat_template.dart';
import 'package:flutter/foundation.dart';

/// Counts the tokens of a formatted prompt with the model's tokenizer.
typedef TokenCounter = Future<Result<int>> Function(String text);

/// The history that fits in the context window.
@immutable
final class ContextPlan {
  /// Creates a plan.
  const new({
    required this.turns,
    required this.droppedMessages,
    required this.promptTokens,
    required this.maxTokens,
  });

  /// Turns sent to the model, oldest first, ending with the new message.
  final List<PromptTurn> turns;

  /// Older messages left out.
  final int droppedMessages;

  /// Tokens in the formatted prompt.
  final int promptTokens;

  /// Reply budget: the requested maximum, or what is left of the context.
  final int maxTokens;
}

/// Fits a conversation into the model's context window.
///
/// The system prompt and the newest user message are always kept. Older
/// messages are dropped from the start, a user and assistant pair at a time,
/// until the formatted prompt plus a reply budget fits. The reply budget is
/// the conversation's max tokens, but never more than half the context, so
/// a long max tokens setting does not starve the history.
final class ContextWindowPlanner {
  /// Creates a planner.
  const new({this.minimumReplyTokens = 64});

  /// Smallest reply budget worth generating.
  final int minimumReplyTokens;

  /// Plans the prompt for [turns] (history plus the new user message last).
  ///
  /// [build] formats a list of turns into the prompt text (it may use a
  /// [ChatTemplate] or the model's own template). Fails with
  /// [ContextOverflowFailure] when the system prompt and newest message
  /// alone do not fit.
  Future<Result<ContextPlan>> plan({
    required List<PromptTurn> turns,
    required int contextLength,
    required int maxTokens,
    required String Function(List<PromptTurn> turns) build,
    required TokenCounter count,
  }) async {
    assert(turns.isNotEmpty, 'the new user message must be included');
    final reserve = maxTokens.clamp(minimumReplyTokens, contextLength ~/ 2);
    final budget = contextLength - reserve;
    var start = 0;
    while (true) {
      final kept = turns.sublist(start);
      final counted = await count(build(kept));
      final int tokens;
      switch (counted) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          tokens = value;
      }
      if (tokens <= budget) {
        return Ok(
          ContextPlan(
            turns: kept,
            droppedMessages: start,
            promptTokens: tokens,
            maxTokens: (contextLength - tokens).clamp(
              minimumReplyTokens,
              maxTokens,
            ),
          ),
        );
      }
      if (kept.length == 1) {
        return Err(
          ContextOverflowFailure(
            promptTokens: tokens,
            contextLength: contextLength,
          ),
        );
      }
      // Drop the oldest message; if that leaves an assistant message first,
      // drop it too so the history starts with the user.
      start++;
      while (start < turns.length - 1 &&
          turns[start].role == MessageRole.assistant) {
        start++;
      }
    }
  }
}

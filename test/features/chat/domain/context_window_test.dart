import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/chat_template.dart';
import 'package:emberwit/features/chat/domain/context_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// 10 turns of 100 "tokens" each: u, a, u, a, ...
final List<PromptTurn> _turns = [
  for (var i = 0; i < 10; i++)
    (role: i.isEven ? MessageRole.user : MessageRole.assistant, content: 'm$i'),
];

/// Each turn costs 100 tokens, plus 50 for the system prompt.
String _build(List<PromptTurn> turns) =>
    'S${turns.map((t) => t.content).join(',')}';

Future<Result<int>> _count(String text) async {
  final turns = text.substring(1).isEmpty
      ? 0
      : text.substring(1).split(',').length;
  return Ok(50 + 100 * turns);
}

void main() {
  const planner = ContextWindowPlanner();

  test('keeps everything when it fits', () async {
    final plan = (await planner.plan(
      turns: _turns,
      contextLength: 4096,
      maxTokens: 512,
      build: _build,
      count: _count,
    )).valueOrNull!;
    expect(plan.turns, _turns);
    expect(plan.droppedMessages, 0);
    expect(plan.promptTokens, 1050);
    expect(plan.maxTokens, 512);
  });

  test('drops the oldest turns and keeps the newest message', () async {
    // Budget: 1024 - 256 reserved = 768 -> at most 7 turns (750 tokens).
    final plan = (await planner.plan(
      turns: [..._turns, (role: MessageRole.user, content: 'new')],
      contextLength: 1024,
      maxTokens: 256,
      build: _build,
      count: _count,
    )).valueOrNull!;
    expect(plan.turns.last.content, 'new');
    expect(plan.turns.first.role, MessageRole.user, reason: 'starts with user');
    expect(plan.promptTokens, lessThanOrEqualTo(768));
    expect(plan.droppedMessages, 11 - plan.turns.length);
    expect(plan.droppedMessages, greaterThan(0));
  });

  test('never reserves more than half the context for the reply', () async {
    final plan = (await planner.plan(
      turns: _turns.sublist(0, 3),
      contextLength: 1024,
      maxTokens: 4000,
      build: _build,
      count: _count,
    )).valueOrNull!;
    expect(plan.droppedMessages, 0);
    expect(plan.maxTokens, 1024 - 350);
  });

  test('fails when the newest message alone is too long', () async {
    final result = await planner.plan(
      turns: const [(role: MessageRole.user, content: 'huge')],
      contextLength: 256,
      maxTokens: 128,
      build: _build,
      count: (text) async => const Ok(5000),
    );
    expect(
      result.failureOrNull,
      const ContextOverflowFailure(promptTokens: 5000, contextLength: 256),
    );
  });

  test('passes tokenizer failures through', () async {
    final result = await planner.plan(
      turns: _turns,
      contextLength: 1024,
      maxTokens: 128,
      build: _build,
      count: (text) async => const Err(NoModelLoadedFailure()),
    );
    expect(result.failureOrNull, const NoModelLoadedFailure());
  });

  test('works with a real template', () async {
    final plan = (await planner.plan(
      turns: _turns,
      contextLength: 8192,
      maxTokens: 256,
      build: (t) => ChatTemplate.chatml.format(system: 'sys', turns: t).text,
      count: (text) async => Ok(text.length ~/ 4),
    )).valueOrNull!;
    expect(plan.droppedMessages, 0);
  });
}

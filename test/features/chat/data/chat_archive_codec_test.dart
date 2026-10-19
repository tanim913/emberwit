import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/chat/data/chat_archive_codec.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cheap key derivation so tests run fast. The real parameters are covered
/// by one test below.
const _fast = ArchiveKdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

final _conversation = Conversation(
  id: 'c1',
  title: 'আজকের আবহাওয়া',
  createdAt: DateTime.utc(2026, 10, 1, 9),
  updatedAt: DateTime.utc(2026, 10, 1, 10),
  pinned: true,
  preview: 'Sunny',
  settings: const ConversationSettings(
    modelId: 'qwen3-q4',
    temperature: 0.4,
    topP: 0.9,
    contextLength: 4096,
    maxTokens: 256,
    systemPrompt: 'Be brief.',
  ),
);

final _messages = [
  ChatMessage(
    id: 'm1',
    conversationId: 'c1',
    role: MessageRole.user,
    content: 'আজ আবহাওয়া কেমন?',
    createdAt: DateTime.utc(2026, 10, 1, 9, 1),
  ),
  ChatMessage(
    id: 'm2',
    conversationId: 'c1',
    role: MessageRole.assistant,
    content: 'Sunny **and** warm.',
    createdAt: DateTime.utc(2026, 10, 1, 9, 2),
    modelId: 'qwen3-q4',
    droppedMessages: 1,
    stats: const MessageStats(
      promptTokens: 40,
      generatedTokens: 12,
      timeToFirstTokenMs: 300,
      tokensPerSecond: 9.5,
    ),
  ),
  ChatMessage(
    id: 'm3',
    conversationId: 'c1',
    role: MessageRole.assistant,
    content: 'Partial',
    createdAt: DateTime.utc(2026, 10, 1, 9, 3),
    status: MessageStatus.streaming,
  ),
];

ChatArchiveCodec _codec([ArchiveKdfParams kdf = _fast]) =>
    ChatArchiveCodec(kdf: kdf, random: Random(1));

Future<Uint8List> _export([String passphrase = 'correct horse']) async =>
    (await _codec().encode([
      (conversation: _conversation, messages: _messages),
    ], passphrase)).valueOrNull!;

Uint8List _edit(Uint8List bytes, void Function(Map<String, dynamic>) change) {
  final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  change(json);
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

AppFailure? _failure(Result<Object?> result) => switch (result) {
  Err(:final failure) => failure,
  Ok() => null,
};

void main() {
  test('round trips conversations, settings, messages and stats', () async {
    final bytes = await _export();
    final result = await _codec().decode(bytes, 'correct horse');
    final archived = result.valueOrNull!.single;
    expect(archived.conversation.id, 'c1');
    expect(archived.conversation.title, 'আজকের আবহাওয়া');
    expect(archived.conversation.pinned, isTrue);
    expect(archived.conversation.settings, _conversation.settings);
    expect(archived.conversation.createdAt.toUtc(), _conversation.createdAt);
    expect(archived.messages, hasLength(3));
    expect(archived.messages[0].content, 'আজ আবহাওয়া কেমন?');
    expect(archived.messages[1].stats, _messages[1].stats);
    expect(archived.messages[1].droppedMessages, 1);
    // A reply that was still streaming is restored as stopped.
    expect(archived.messages[2].status, MessageStatus.stopped);
  });

  test('reveals nothing readable without the passphrase', () async {
    final text = utf8.decode(await _export());
    expect(text, isNot(contains('আবহাওয়া')));
    expect(text, isNot(contains('Sunny')));
    expect(text, isNot(contains('qwen3')));
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json['format'], ChatArchiveCodec.format);
    expect(json['cipher'], 'aes-256-gcm');
    expect((json['kdf'] as Map<String, dynamic>)['name'], 'argon2id');
  });

  test('every export uses a fresh salt and nonce', () async {
    final codec = ChatArchiveCodec(kdf: _fast);
    Future<Map<String, dynamic>> once() async => jsonDecode(
      utf8.decode((await codec.encode(const [], 'passphrase')).valueOrNull!),
    ) as Map<String, dynamic>;
    final a = await once();
    final b = await once();
    expect(a['nonce'], isNot(b['nonce']));
    expect(
      (a['kdf'] as Map<String, dynamic>)['salt'],
      isNot((b['kdf'] as Map<String, dynamic>)['salt']),
    );
  });

  test('rejects short passphrases', () async {
    final result = await _codec().encode(const [], 'short');
    expect(
      _failure(result),
      const ArchiveFailure(ArchiveFailureReason.weakPassphrase),
    );
  });

  test('a wrong passphrase fails without revealing anything', () async {
    final result = await _codec().decode(await _export(), 'wrong horse');
    expect(
      _failure(result),
      const ArchiveFailure(ArchiveFailureReason.wrongPassphrase),
    );
  });

  test('tampering with the ciphertext or header is detected', () async {
    final bytes = await _export();
    final flipped = _edit(bytes, (json) {
      final data = base64.decode(json['ciphertext'] as String);
      data[0] ^= 1;
      json['ciphertext'] = base64.encode(data);
    });
    expect(
      _failure(await _codec().decode(flipped, 'correct horse')),
      const ArchiveFailure(ArchiveFailureReason.wrongPassphrase),
    );
    // Lowering the work factor in the header breaks authentication too.
    final weakened = _edit(bytes, (json) {
      (json['kdf'] as Map<String, dynamic>)['iterations'] = 2;
    });
    expect(
      _failure(await _codec().decode(weakened, 'correct horse')),
      const ArchiveFailure(ArchiveFailureReason.wrongPassphrase),
    );
  });

  test('refuses files that are not exports', () async {
    for (final bytes in [
      Uint8List.fromList(utf8.encode('not json')),
      Uint8List.fromList(utf8.encode('[]')),
      Uint8List.fromList(utf8.encode('{"format":"something.else"}')),
      Uint8List(0),
    ]) {
      expect(
        _failure(await _codec().decode(bytes, 'correct horse')),
        const ArchiveFailure(ArchiveFailureReason.notAnArchive),
      );
    }
  });

  test('refuses absurd key derivation costs before deriving', () async {
    final greedy = _edit(await _export(), (json) {
      (json['kdf'] as Map<String, dynamic>)['memoryKiB'] = 4 * 1024 * 1024;
    });
    expect(
      _failure(await _codec().decode(greedy, 'correct horse')),
      const ArchiveFailure(ArchiveFailureReason.notAnArchive),
    );
  });

  test('reports exports from a newer app version', () async {
    final newer = _edit(await _export(), (json) {
      json['format'] = 'emberwit.chat-export.v2';
    });
    expect(
      _failure(await _codec().decode(newer, 'correct horse')),
      const ArchiveFailure(ArchiveFailureReason.unsupportedVersion),
    );
  });

  test('the standard parameters are OWASP Argon2id minimums', () async {
    const p = ArchiveKdfParams.standard;
    expect(p.memoryKiB, 19456);
    expect(p.iterations, 2);
    expect(p.parallelism, 1);
    expect(p.isAcceptable, isTrue);
    final codec = ChatArchiveCodec();
    final bytes = (await codec.encode(const [], 'passphrase')).valueOrNull!;
    expect((await codec.decode(bytes, 'passphrase')).valueOrNull, isEmpty);
  });
}

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/features/chat/data/chat_archive_codec.dart';
import 'package:emberwit/features/chat/data/chat_archive_impl.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';
import 'package:emberwit/features/chat/data/chat_repository_impl.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/chat_db.dart';

void main() {
  late ChatDatabase source;
  late ChatDatabase target;
  late ChatRepositoryImpl sourceRepo;
  late ChatRepositoryImpl targetRepo;
  final codec = ChatArchiveCodec(
    kdf: const ArchiveKdfParams(memoryKiB: 64, iterations: 1, parallelism: 1),
  );

  setUp(() {
    source = memoryChatDatabase();
    target = memoryChatDatabase();
    final clock = FixedClock(DateTime.utc(2026, 10, 3));
    sourceRepo = ChatRepositoryImpl(source, clock: clock);
    targetRepo = ChatRepositoryImpl(target, clock: clock);
  });
  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<Conversation> chatWith(String title, List<String> texts) async {
    final c = await sourceRepo.createConversation(title: title);
    var i = 0;
    for (final text in texts) {
      await sourceRepo.saveMessage(
        ChatMessage(
          id: '${c.id}-${i++}',
          conversationId: c.id,
          role: i.isOdd ? MessageRole.user : MessageRole.assistant,
          content: text,
          createdAt: DateTime.utc(2026, 10, 3, 9, i),
        ),
      );
    }
    return c;
  }

  test('exports and imports every conversation into another phone', () async {
    final first = await chatWith('One', ['Hi', 'Hello!']);
    await chatWith('দুই', ['কেমন আছেন?']);
    final archive = ChatArchiveImpl(sourceRepo, codec: codec);
    expect(await archive.conversationCount(), 2);

    final bytes = (await archive.export('passphrase')).valueOrNull!;
    final restored = ChatArchiveImpl(targetRepo, codec: codec);
    expect((await restored.import(bytes, 'passphrase')).valueOrNull, 2);
    expect(await restored.conversationCount(), 2);
    final messages = await targetRepo.messages(first.id);
    expect(messages.map((m) => m.content), ['Hi', 'Hello!']);
    final titles = (await targetRepo.allConversations()).map((c) => c.title);
    expect(titles, containsAll(<String>['One', 'দুই']));

    // Importing the same file again adds nothing and changes nothing.
    expect((await restored.import(bytes, 'passphrase')).valueOrNull, 0);
    expect(await targetRepo.messages(first.id), hasLength(2));
  });

  test('a wrong passphrase imports nothing', () async {
    await chatWith('One', ['Hi']);
    final bytes = (await ChatArchiveImpl(
      sourceRepo,
      codec: codec,
    ).export('passphrase')).valueOrNull!;
    final result = await ChatArchiveImpl(
      targetRepo,
      codec: codec,
    ).import(bytes, 'not the passphrase');
    expect(
      (result as Err).failure,
      const ArchiveFailure(ArchiveFailureReason.wrongPassphrase),
    );
    expect(await targetRepo.conversationCount(), 0);
  });

  test('deleteAll removes every conversation', () async {
    await chatWith('One', ['Hi']);
    final archive = ChatArchiveImpl(sourceRepo, codec: codec);
    await archive.deleteAll();
    expect(await archive.conversationCount(), 0);
  });
}

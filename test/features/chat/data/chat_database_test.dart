import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryKeys implements DatabaseKeyStore {
  new([String? key]) : key = key ?? generateDatabaseKey();

  String key;
  int reads = 0;

  @override
  Future<String> readOrCreate() async {
    reads++;
    return key;
  }
}

Future<void> _insertConversation(ChatDatabase db, String title) => db
    .into(db.conversations)
    .insert(
      ConversationsCompanion.insert(
        id: 'c1',
        title: title,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        systemPrompt: 'sys',
        temperature: 0.7,
        topP: 0.9,
        contextLength: 2048,
        maxTokens: 256,
      ),
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('chatdb'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the SQLite build is SQLCipher', () async {
    final db = ChatDatabase(
      NativeDatabase.memory(
        setup: (raw) => applyEncryptionKey(raw, generateDatabaseKey()),
      ),
    );
    final version = await db.customSelect('PRAGMA cipher_version').getSingle();
    expect(version.data.values.single, isA<String>());
    await db.close();
  });

  test('stores data encrypted at rest', () async {
    final file = File('${dir.path}/chat.db');
    final keys = _MemoryKeys();
    final db = ChatDatabase(openEncryptedDatabase(file, keys));
    await _insertConversation(db, 'a very secret conversation title');
    await db.close();

    final raw = file.readAsBytesSync();
    expect(raw.length, greaterThan(1000));
    // Plain SQLite files start with this header; SQLCipher files are noise.
    expect(
      ascii.decode(raw.sublist(0, 15), allowInvalid: true),
      isNot('SQLite format 3'),
    );
    expect(
      latin1.decode(raw).contains('very secret'),
      isFalse,
      reason: 'titles must not appear in the file',
    );

    final reopened = ChatDatabase(openEncryptedDatabase(file, keys));
    final rows = await reopened.select(reopened.conversations).get();
    expect(rows.single.title, 'a very secret conversation title');
    await reopened.close();
  });

  test('a wrong key cannot read the file; it is moved aside', () async {
    final file = File('${dir.path}/chat.db');
    final first = ChatDatabase(openEncryptedDatabase(file, _MemoryKeys()));
    await _insertConversation(first, 'secret');
    await first.close();

    final other = ChatDatabase(openEncryptedDatabase(file, _MemoryKeys()));
    expect(await other.select(other.conversations).get(), isEmpty);
    await other.close();
    final moved = dir
        .listSync()
        .where((e) => e.path.contains('.unreadable-'))
        .toList();
    expect(moved, hasLength(1), reason: 'the old file is kept, not deleted');
  });

  test('deleting a conversation deletes its messages', () async {
    final db = ChatDatabase(
      NativeDatabase.memory(
        setup: (raw) => applyEncryptionKey(raw, generateDatabaseKey()),
      ),
    );
    await _insertConversation(db, 't');
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'm1',
            conversationId: 'c1',
            role: 'user',
            content: 'hi',
            status: 'complete',
            createdAt: DateTime.utc(2026),
          ),
        );
    await (db.delete(db.conversations)..where((c) => c.id.equals('c1'))).go();
    expect(await db.select(db.messages).get(), isEmpty);
    await db.close();
  });

  test('keys are 256-bit hex from a secure random source', () {
    final key = generateDatabaseKey(Random(1));
    expect(isValidDatabaseKey(key), isTrue);
    expect(key, hasLength(64));
    expect(generateDatabaseKey(), isNot(generateDatabaseKey()));
    expect(isValidDatabaseKey('abc'), isFalse);
    expect(isValidDatabaseKey('G' * 64), isFalse);
  });
}

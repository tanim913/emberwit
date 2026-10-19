import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

part 'chat_database.g.dart';

/// Conversations.
@DataClassName('ConversationRow')
class Conversations extends Table {
  /// UUID.
  TextColumn get id => text()();

  /// Title.
  TextColumn get title => text()();

  /// Pinned to the top.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// Creation time.
  DateTimeColumn get createdAt => dateTime()();

  /// Last change.
  DateTimeColumn get updatedAt => dateTime()();

  /// Start of the last message.
  TextColumn get preview => text().withDefault(const Constant(''))();

  /// Settings: model.
  TextColumn get modelId => text().nullable()();

  /// Settings: system prompt.
  TextColumn get systemPrompt => text()();

  /// Settings: temperature.
  RealColumn get temperature => real()();

  /// Settings: top p.
  RealColumn get topP => real()();

  /// Settings: context length.
  IntColumn get contextLength => integer()();

  /// Settings: max reply tokens.
  IntColumn get maxTokens => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Messages.
@DataClassName('MessageRow')
@TableIndex(
  name: 'messages_by_conversation',
  columns: {#conversationId, #createdAt},
)
class Messages extends Table {
  /// UUID.
  TextColumn get id => text()();

  /// Owning conversation; messages are deleted with it.
  TextColumn get conversationId =>
      text().references(Conversations, #id, onDelete: KeyAction.cascade)();

  /// `user` or `assistant`.
  TextColumn get role => text()();

  /// Message text.
  TextColumn get content => text()();

  /// `complete`, `streaming`, `stopped` or `failed`.
  TextColumn get status => text()();

  /// Creation time.
  DateTimeColumn get createdAt => dateTime()();

  /// Model that wrote an assistant message.
  TextColumn get modelId => text().nullable()();

  /// Stats: prompt tokens.
  IntColumn get promptTokens => integer().nullable()();

  /// Stats: generated tokens.
  IntColumn get generatedTokens => integer().nullable()();

  /// Stats: time to first token.
  IntColumn get timeToFirstTokenMs => integer().nullable()();

  /// Stats: speed.
  RealColumn get tokensPerSecond => real().nullable()();

  /// Messages left out of the context for this reply.
  IntColumn get droppedMessages => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The encrypted chat database.
@DriftDatabase(tables: [Conversations, Messages])
class ChatDatabase extends _$ChatDatabase {
  /// Opens the database on the query executor [e].
  new(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Where the database encryption key lives.
abstract interface class DatabaseKeyStore {
  /// The key (64 hex characters), created on first use.
  Future<String> readOrCreate();
}

/// [DatabaseKeyStore] in the platform keystore: Android Keystore backed
/// storage and the iOS Keychain (this device only, never synced or backed
/// up). The key never touches files, logs or preferences.
final class SecureDatabaseKeyStore implements DatabaseKeyStore {
  /// Creates the store.
  const new([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _keyName = 'chat_db_key_v1';

  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  @override
  Future<String> readOrCreate() async {
    final existing = await _storage.read(key: _keyName, iOptions: _ios);
    if (existing != null && isValidDatabaseKey(existing)) return existing;
    final key = generateDatabaseKey();
    await _storage.write(key: _keyName, value: key, iOptions: _ios);
    return key;
  }
}

/// A new random 256-bit key from the platform's secure random generator.
String generateDatabaseKey([Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(
    32,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Whether [key] is 64 hex characters.
bool isValidDatabaseKey(String key) => RegExp(r'^[0-9a-f]{64}$').hasMatch(key);

/// Opens (or creates) the SQLCipher encrypted database at [file] with the
/// key from [keys]. The database runs in its own background isolate.
///
/// The raw key is passed as `x'...'`, so SQLCipher uses it directly without
/// a password derivation step. Opening fails loudly if the SQLite build is
/// not SQLCipher, rather than silently writing plain text.
///
/// If the file cannot be decrypted (for example the key was lost when the
/// app's keystore was reset), it is moved aside, never deleted, and a new
/// database is started.
QueryExecutor openEncryptedDatabase(File file, DatabaseKeyStore keys) =>
    LazyDatabase(() async {
      final key = await keys.readOrCreate();
      await file.parent.create(recursive: true);
      if (file.existsSync() && !await _canDecrypt(file, key)) {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        await file.rename('${file.path}.unreadable-$stamp');
      }
      return NativeDatabase.createInBackground(
        file,
        setup: (db) => applyEncryptionKey(db, key),
      );
    });

/// Unlocks a raw sqlite3 database with [key] and checks SQLCipher is active.
void applyEncryptionKey(Database db, String key) {
  db.execute("PRAGMA key = \"x'$key'\"");
  if (db.select('PRAGMA cipher_version').isEmpty) {
    throw StateError('SQLCipher is not available; refusing to store chats');
  }
}

Future<bool> _canDecrypt(File file, String key) async {
  final probe = NativeDatabase(
    file,
    setup: (db) => applyEncryptionKey(db, key),
  );
  final database = ChatDatabase(probe);
  try {
    await database.customSelect('SELECT count(*) FROM sqlite_master').get();
    return true;
  } on Object {
    return false;
  } finally {
    await database.close();
  }
}

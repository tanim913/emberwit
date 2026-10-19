import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';

/// An encrypted in-memory chat database for tests.
///
/// Needs SQLCipher: on Linux set LD_LIBRARY_PATH to a libsqlcipher build
/// (tool/build_host_sqlcipher.sh) or install libsqlcipher-dev.
ChatDatabase memoryChatDatabase() {
  // Tests open one database per test; drift's multiple database warning is
  // meant for apps.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return _open();
}

ChatDatabase _open() => ChatDatabase(
  NativeDatabase.memory(
    setup: (db) => applyEncryptionKey(db, generateDatabaseKey()),
  ),
);

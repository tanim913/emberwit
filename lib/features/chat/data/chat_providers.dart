import 'dart:io';

import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/runtime/runtime_status.dart';
import 'package:emberwit/core/utils/backup_exclusion.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/engine/llama/llama_inference_engine.dart';
import 'package:emberwit/features/chat/data/chat_archive_impl.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';
import 'package:emberwit/features/chat/data/chat_repository_impl.dart';
import 'package:emberwit/features/chat/data/platform_device_actions.dart';
import 'package:emberwit/features/chat/data/platform_voice_input.dart';
import 'package:emberwit/features/chat/domain/chat_repository.dart';
import 'package:emberwit/features/chat/domain/chat_responder.dart';
import 'package:emberwit/features/chat/domain/device_actions.dart';
import 'package:emberwit/features/chat/domain/voice_input.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_providers.g.dart';

/// Where the database encryption key is kept. Overridden in tests.
@Riverpod(keepAlive: true)
DatabaseKeyStore databaseKeyStore(Ref ref) => const SecureDatabaseKeyStore();

/// The encrypted chat database, opened lazily in a background isolate.
@Riverpod(keepAlive: true)
ChatDatabase chatDatabase(Ref ref) {
  final directory = Directory(
    '${ref.watch(appSupportDirectoryProvider).path}/chat',
  )..createSync(recursive: true);
  // Chats must never leave the device, including through iCloud backup.
  const BackupExclusion().exclude(directory).ignore();
  final database = ChatDatabase(
    openEncryptedDatabase(
      File('${directory.path}/chat.db'),
      ref.watch(databaseKeyStoreProvider),
    ),
  );
  ref.onDispose(database.close);
  return database;
}

/// Conversation storage.
@Riverpod(keepAlive: true)
ChatRepository chatRepository(Ref ref) => ChatRepositoryImpl(
  ref.watch(chatDatabaseProvider),
  clock: ref.watch(clockProvider),
);

/// Produces replies.
@Riverpod(keepAlive: true)
ChatResponder chatResponder(Ref ref) {
  final profiles = ref.watch(deviceProfileRepositoryProvider);
  var threads = defaultThreadCount(Platform.numberOfProcessors);
  profiles.cachedProfile().then((p) {
    if (p != null) threads = p.recommendedThreads;
  }).ignore();
  return ChatResponder(
    engine: ref.watch(inferenceEngineProvider),
    models: ref.watch(modelLibraryProvider),
    repository: ref.watch(chatRepositoryProvider),
    threads: () => threads,
    advice: () => ref.read(runtimeStatusProvider),
    actions: ref.watch(deviceActionsProvider),
    clock: ref.watch(clockProvider),
  );
}

/// Bulk chat operations for settings. `featureBindings()` exposes it as the
/// shared `chatArchiveProvider`.
@Riverpod(keepAlive: true)
ChatArchiveImpl chatArchiveImpl(Ref ref) =>
    ChatArchiveImpl(ref.watch(chatRepositoryProvider));

/// Voice typing with the phone's offline recognizer. Overridden in tests.
@Riverpod(keepAlive: true)
VoiceInput voiceInput(Ref ref) => PlatformVoiceInput();

/// Phone actions run from chat commands. Overridden in tests.
@Riverpod(keepAlive: true)
DeviceActions deviceActions(Ref ref) => PlatformDeviceActions();

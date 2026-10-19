import 'dart:typed_data';

import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/settings/data/settings_providers.dart';
import 'package:emberwit/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_runtime.dart';
import '../../helpers/preferences.dart';
import '../chat/domain/chat_responder_test.dart' show installed;
import '../model_manager/fakes.dart';
import 'fakes.dart';

void main() {
  late FakeChatArchive archive;
  late FakeArchiveFiles files;
  late FakeModelLibrary library;
  late FakeAuthenticator auth;
  late ProviderContainer container;

  setUp(() async {
    archive = FakeChatArchive();
    files = FakeArchiveFiles();
    library = FakeModelLibrary(
      LibraryState(installed: [installed('a'), installed('b')]),
    );
    auth = FakeAuthenticator();
    container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await inMemoryPreferences({PreferenceKeys.defaultModelId: 'a'}),
        ),
        chatArchiveProvider.overrideWithValue(archive),
        archiveFilesProvider.overrideWithValue(files),
        modelLibraryProvider.overrideWithValue(library),
        authenticatorProvider.overrideWithValue(auth),
      ],
    );
  });

  SettingsController controller() =>
      container.read(settingsControllerProvider.notifier);

  test('export encrypts and saves a dated file', () async {
    final outcome = await controller().exportChats(
      'long passphrase',
      DateTime(2026, 10, 3),
    );
    expect(outcome, isA<SettingsDone>());
    expect(files.saved.keys, ['emberwit-chats-2026-10-03.json']);
    expect(container.read(settingsControllerProvider), isFalse);
  });

  test('export reports failures and cancelled saves', () async {
    final weak = await controller().exportChats('short', DateTime(2026));
    expect(
      (weak as SettingsFailed).failure,
      const ArchiveFailure(ArchiveFailureReason.weakPassphrase),
    );
    files.cancelSave = true;
    expect(
      await controller().exportChats('long passphrase', DateTime(2026)),
      isA<SettingsCancelled>(),
    );
  });

  test('import adds conversations or reports a wrong passphrase', () async {
    final bytes = Uint8List.fromList('long passphrase'.codeUnits);
    files.toOpen = bytes;
    expect(await controller().pickImport(), bytes);
    final ok = await controller().importChats(bytes, 'long passphrase');
    expect((ok as SettingsDone).count, 2);
    final wrong = await controller().importChats(bytes, 'other passphrase');
    expect(
      (wrong as SettingsFailed).failure,
      const ArchiveFailure(ArchiveFailureReason.wrongPassphrase),
    );
  });

  test('deletes all chats', () async {
    await controller().deleteAllChats();
    expect(archive.calls, ['deleteAll']);
  });

  test('deletes all models and forgets the default model', () async {
    final outcome = await controller().deleteAllModels();
    expect((outcome as SettingsDone).count, 2);
    expect(library.calls, ['delete:a', 'delete:b']);
    expect(container.read(defaultModelIdProvider), isNull);
  });

  test('stops at the first model that cannot be deleted', () async {
    library.nextFailure = const ModelNotFoundFailure('a');
    final outcome = await controller().deleteAllModels();
    expect(outcome, isA<SettingsFailed>());
    expect(library.calls, ['delete:a']);
  });

  test('turning the app lock on needs a screen lock and the owner', () async {
    auth.available = false;
    final unavailable = await controller().setAppLock(
      enabled: true,
      reason: 'r',
    );
    expect(
      (unavailable as SettingsAuthFailed).result,
      AuthenticationResult.unavailable,
    );
    expect(container.read(appLockEnabledProvider), isFalse);

    auth
      ..available = true
      ..result = AuthenticationResult.failed;
    expect(
      await controller().setAppLock(enabled: true, reason: 'r'),
      isA<SettingsAuthFailed>(),
    );
    expect(container.read(appLockEnabledProvider), isFalse);

    auth.result = AuthenticationResult.success;
    expect(
      await controller().setAppLock(enabled: true, reason: 'r'),
      isA<SettingsDone>(),
    );
    expect(container.read(appLockEnabledProvider), isTrue);

    // Turning it off also needs the owner.
    expect(
      await controller().setAppLock(enabled: false, reason: 'r'),
      isA<SettingsDone>(),
    );
    expect(container.read(appLockEnabledProvider), isFalse);
    expect(auth.prompts, hasLength(3));
  });

  test('export file names are zero padded', () {
    expect(
      exportFileName(DateTime(2027, 1, 5)),
      'emberwit-chats-2027-01-05.json',
    );
  });
}

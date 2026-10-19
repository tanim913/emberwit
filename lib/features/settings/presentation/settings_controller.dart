import 'dart:typed_data';

import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/settings/data/settings_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// Outcome of a settings action, shown as a message.
sealed class SettingsOutcome {
  const new();
}

/// The action finished.
final class SettingsDone extends SettingsOutcome {
  /// Creates the outcome. [count] is the number of items affected.
  const new([this.count = 0]);

  /// Items affected (conversations imported, models deleted).
  final int count;
}

/// The user cancelled a file dialog.
final class SettingsCancelled extends SettingsOutcome {
  /// Creates the outcome.
  const new();
}

/// The action failed.
final class SettingsFailed extends SettingsOutcome {
  /// Creates the outcome.
  const new(this.failure);

  /// What went wrong.
  final AppFailure failure;
}

/// Changing the app lock needs authentication that did not succeed.
final class SettingsAuthFailed extends SettingsOutcome {
  /// Creates the outcome.
  const new(this.result);

  /// What the authenticator reported.
  final AuthenticationResult result;
}

/// Runs the longer settings actions and reports whether one is running.
@riverpod
class SettingsController extends _$SettingsController {
  @override
  bool build() => false;

  Future<T> _busy<T>(Future<T> Function() action) async {
    state = true;
    try {
      return await action();
    } finally {
      if (ref.mounted) state = false;
    }
  }

  /// Encrypts every conversation with [passphrase] and lets the user save
  /// the file.
  Future<SettingsOutcome> exportChats(String passphrase, DateTime now) =>
      _busy(() async {
        final result = await ref.read(chatArchiveProvider).export(passphrase);
        switch (result) {
          case Err(:final failure):
            return SettingsFailed(failure);
          case Ok(:final value):
            final saved = await ref
                .read(archiveFilesProvider)
                .save(exportFileName(now), value);
            return saved ? const SettingsDone() : const SettingsCancelled();
        }
      });

  /// Picks an export file. `null` when the user cancels.
  Future<Uint8List?> pickImport() => ref.read(archiveFilesProvider).open();

  /// Adds the conversations of [bytes] using [passphrase].
  Future<SettingsOutcome> importChats(Uint8List bytes, String passphrase) =>
      _busy(() async {
        final result = await ref
            .read(chatArchiveProvider)
            .import(bytes, passphrase);
        return switch (result) {
          Ok(:final value) => SettingsDone(value),
          Err(:final failure) => SettingsFailed(failure),
        };
      });

  /// Deletes every conversation.
  Future<SettingsOutcome> deleteAllChats() => _busy(() async {
    await ref.read(chatArchiveProvider).deleteAll();
    return const SettingsDone();
  });

  /// Deletes every installed model file.
  Future<SettingsOutcome> deleteAllModels() => _busy(() async {
    final library = ref.read(modelLibraryProvider);
    await library.initialize();
    var deleted = 0;
    for (final model in [...library.state.installed]) {
      final result = await library.delete(model.id);
      if (result case Err(:final failure)) return SettingsFailed(failure);
      deleted++;
    }
    await ref.read(defaultModelIdProvider.notifier).set(null);
    return SettingsDone(deleted);
  });

  /// Turns the app lock on or off after the user authenticates.
  Future<SettingsOutcome> setAppLock({
    required bool enabled,
    required String reason,
  }) async {
    final auth = ref.read(authenticatorProvider);
    if (enabled && !await auth.isAvailable()) {
      return const SettingsAuthFailed(AuthenticationResult.unavailable);
    }
    final result = await auth.authenticate(reason);
    if (result != AuthenticationResult.success) {
      return SettingsAuthFailed(result);
    }
    await ref.read(appLockEnabledProvider.notifier).set(enabled: enabled);
    return const SettingsDone();
  }
}

/// File name of an export made at [now], for example
/// `emberwit-chats-2026-10-03.json`.
String exportFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'emberwit-chats-${now.year}-${two(now.month)}-${two(now.day)}.json';
}

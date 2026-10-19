import 'dart:async';

import 'package:emberwit/core/constants/app_constants.dart';
import 'package:emberwit/core/l10n/failure_messages.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/l10n/recommendation_messages.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:emberwit/core/preferences/app_preferences.dart';
import 'package:emberwit/core/preferences/download_preferences.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/settings/data/settings_providers.dart';
import 'package:emberwit/features/settings/presentation/passphrase_dialog.dart';
import 'package:emberwit/features/settings/presentation/settings_controller.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Installed models, kept up to date, for the default model choice and the
/// storage summary.
final StreamProvider<List<InstalledModel>> _installedModelsProvider =
    StreamProvider.autoDispose((ref) async* {
      final library = ref.watch(modelLibraryProvider);
      await library.initialize();
      yield library.state.installed;
      yield* library.changes.map((s) => s.installed);
    });

/// Settings: appearance, chats, models, privacy, device and about.
class SettingsPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final preferences = ref.watch(appPreferencesProvider);
    final busy = ref.watch(settingsControllerProvider);
    final models = ref.watch(_installedModelsProvider).value ?? const [];
    final defaultModelId = ref.watch(defaultModelIdProvider);
    final debugTools = ref.watch(flavorConfigProvider).enableDebugTools;
    String? defaultModelName;
    for (final m in models) {
      if (m.id == defaultModelId) defaultModelName = m.displayName;
    }
    final usedBytes = models.fold(0, (sum, m) => sum + m.sizeBytes);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: busy,
          child: ListView(
            key: const Key('settings-list'),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Section(l10n.settingsAppearance),
              ListTile(
                key: const Key('settings-theme'),
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(l10n.settingsTheme),
                subtitle: Text(_themeName(l10n, preferences.themeMode)),
                onTap: () => _chooseTheme(context, ref, preferences.themeMode),
              ),
              ListTile(
                key: const Key('settings-language'),
                leading: const Icon(Icons.translate_rounded),
                title: Text(l10n.settingsLanguage),
                subtitle: Text(
                  _languageName(l10n, preferences.locale?.languageCode),
                ),
                onTap: () => _chooseLanguage(
                  context,
                  ref,
                  preferences.locale?.languageCode,
                ),
              ),
              _Section(l10n.settingsChats),
              ListTile(
                key: const Key('settings-default-model'),
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(l10n.settingsDefaultModel),
                subtitle: Text(
                  defaultModelName ?? l10n.settingsDefaultModelNewest,
                ),
                enabled: models.isNotEmpty,
                onTap: () =>
                    _chooseDefaultModel(context, ref, models, defaultModelId),
              ),
              ListTile(
                key: const Key('settings-export'),
                leading: const Icon(Icons.upload_file_rounded),
                title: Text(l10n.settingsExport),
                subtitle: Text(l10n.settingsExportHint),
                onTap: () => _export(context, ref),
              ),
              ListTile(
                key: const Key('settings-import'),
                leading: const Icon(Icons.download_for_offline_outlined),
                title: Text(l10n.settingsImport),
                subtitle: Text(l10n.settingsImportHint),
                onTap: () => _import(context, ref),
              ),
              ListTile(
                key: const Key('settings-clear-chats'),
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(l10n.settingsClearChats),
                onTap: () => _clearChats(context, ref),
              ),
              _Section(l10n.settingsModels),
              SwitchListTile(
                key: const Key('settings-wifi-only'),
                secondary: const Icon(Icons.wifi_rounded),
                title: Text(l10n.modelsWifiOnly),
                subtitle: Text(l10n.modelsWifiOnlyHint),
                value: ref.watch(wifiOnlyDownloadsProvider),
                onChanged: (value) => ref
                    .read(wifiOnlyDownloadsProvider.notifier)
                    .set(wifiOnly: value),
              ),
              ListTile(
                key: const Key('settings-manage-models'),
                leading: const Icon(Icons.download_rounded),
                title: Text(l10n.modelsTitle),
                subtitle: Text(
                  l10n.settingsModelsUsage(models.length, gigabytes(usedBytes)),
                ),
                onTap: () => context.push(AppRoutes.models),
              ),
              ListTile(
                key: const Key('settings-delete-models'),
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(l10n.settingsDeleteModels),
                enabled: models.isNotEmpty,
                onTap: () => _deleteModels(context, ref, usedBytes),
              ),
              _Section(l10n.settingsPrivacy),
              SwitchListTile(
                key: const Key('settings-app-lock'),
                secondary: const Icon(Icons.lock_outline_rounded),
                title: Text(l10n.settingsAppLock),
                subtitle: Text(l10n.settingsAppLockHint),
                value: ref.watch(appLockEnabledProvider),
                onChanged: (value) => _setAppLock(context, ref, value),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l10n.settingsPrivacySummaryTitle),
                subtitle: Text(l10n.settingsPrivacySummary),
                isThreeLine: true,
              ),
              _Section(l10n.settingsDevice),
              ListTile(
                key: const Key('settings-device-check'),
                leading: const Icon(Icons.speed_rounded),
                title: Text(l10n.settingsRerunBenchmark),
                subtitle: Text(l10n.settingsRerunBenchmarkHint),
                onTap: () => context.push(AppRoutes.deviceCheck),
              ),
              if (debugTools)
                ListTile(
                  key: const Key('open-engine-debug'),
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text(l10n.debugEngineOpen),
                  onTap: () => context.push(AppRoutes.engineDebug),
                ),
              _Section(l10n.settingsAbout),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text(AppConstants.appName),
                subtitle: Text(
                  l10n.settingsVersion(
                    ref.watch(appVersionProvider).value ?? '…',
                  ),
                ),
              ),
              ListTile(
                key: const Key('settings-model-licenses'),
                leading: const Icon(Icons.gavel_rounded),
                title: Text(l10n.settingsModelLicenses),
                onTap: () => context.push(AppRoutes.modelLicenses),
              ),
              ListTile(
                key: const Key('settings-licenses'),
                leading: const Icon(Icons.description_outlined),
                title: Text(l10n.settingsOpenSourceLicenses),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: ref.read(appVersionProvider).value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _themeName(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
  ThemeMode.system => l10n.settingsFollowSystem,
  ThemeMode.light => l10n.settingsThemeLight,
  ThemeMode.dark => l10n.settingsThemeDark,
};

String _languageName(AppLocalizations l10n, String? code) => switch (code) {
  'en' => 'English',
  'bn' => 'বাংলা',
  _ => l10n.settingsFollowSystem,
};

Future<T?> _choose<T>(
  BuildContext context, {
  required String title,
  required List<(T?, String)> options,
  required T? current,
}) => showDialog<T>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title),
    children: [
      RadioGroup<T?>(
        groupValue: current,
        onChanged: (value) => Navigator.pop(context, value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, label) in options)
              RadioListTile<T?>(
                key: Key('option-$label'),
                value: value,
                title: Text(label),
              ),
          ],
        ),
      ),
    ],
  ),
);

Future<void> _chooseTheme(
  BuildContext context,
  WidgetRef ref,
  ThemeMode current,
) async {
  final l10n = context.l10n;
  final mode = await _choose<ThemeMode>(
    context,
    title: l10n.settingsTheme,
    current: current,
    options: [
      for (final mode in ThemeMode.values) (mode, _themeName(l10n, mode)),
    ],
  );
  if (mode != null) {
    await ref.read(appPreferencesProvider.notifier).setThemeMode(mode);
  }
}

/// Sentinel for "follow the system" in the language dialog (a `null`
/// result means the dialog was dismissed).
const String _system = 'system';

Future<void> _chooseLanguage(
  BuildContext context,
  WidgetRef ref,
  String? current,
) async {
  final l10n = context.l10n;
  final code = await _choose<String>(
    context,
    title: l10n.settingsLanguage,
    current: current ?? _system,
    options: [
      (_system, l10n.settingsFollowSystem),
      ('en', 'English'),
      ('bn', 'বাংলা'),
    ],
  );
  if (code == null) return;
  await ref
      .read(appPreferencesProvider.notifier)
      .setLocale(code == _system ? null : Locale(code));
}

Future<void> _chooseDefaultModel(
  BuildContext context,
  WidgetRef ref,
  List<InstalledModel> models,
  String? current,
) async {
  final l10n = context.l10n;
  const newest = '';
  final id = await _choose<String>(
    context,
    title: l10n.settingsDefaultModel,
    current: current ?? newest,
    options: [
      (newest, l10n.settingsDefaultModelNewest),
      for (final m in models) (m.id, m.displayName),
    ],
  );
  if (id == null) return;
  await ref.read(defaultModelIdProvider.notifier).set(id == newest ? null : id);
}

void _show(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String? _describe(AppLocalizations l10n, SettingsOutcome outcome) =>
    switch (outcome) {
      SettingsFailed(:final failure) => describeFailure(l10n, failure),
      SettingsAuthFailed(:final result) => switch (result) {
        AuthenticationResult.unavailable => l10n.lockUnavailable,
        AuthenticationResult.lockedOut => l10n.lockLockedOut,
        AuthenticationResult.failed ||
        AuthenticationResult.success => l10n.lockFailed,
      },
      SettingsCancelled() || SettingsDone() => null,
    };

Future<void> _export(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final passphrase = await showPassphraseDialog(
    context,
    title: l10n.settingsExport,
    body: l10n.settingsExportBody,
    confirm: true,
  );
  if (passphrase == null || !context.mounted) return;
  final outcome = await ref
      .read(settingsControllerProvider.notifier)
      .exportChats(passphrase, ref.read(clockProvider).now());
  if (!context.mounted) return;
  final message = outcome is SettingsDone
      ? l10n.settingsExportDone
      : _describe(l10n, outcome);
  if (message != null) _show(context, message);
}

Future<void> _import(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final controller = ref.read(settingsControllerProvider.notifier);
  final bytes = await controller.pickImport();
  if (bytes == null || !context.mounted) return;
  final passphrase = await showPassphraseDialog(
    context,
    title: l10n.settingsImport,
    body: l10n.settingsImportBody,
    confirm: false,
  );
  if (passphrase == null || !context.mounted) return;
  final outcome = await controller.importChats(bytes, passphrase);
  if (!context.mounted) return;
  final message = switch (outcome) {
    SettingsDone(:final count) => l10n.settingsImportDone(count),
    _ => _describe(l10n, outcome),
  };
  if (message != null) _show(context, message);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  required Key key,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: key,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<void> _clearChats(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  if (!await _confirm(
    context,
    title: l10n.settingsClearChatsTitle,
    body: l10n.settingsClearChatsBody,
    action: l10n.settingsClearChatsAction,
    key: const Key('confirm-clear-chats'),
  )) {
    return;
  }
  await ref.read(settingsControllerProvider.notifier).deleteAllChats();
  if (context.mounted) _show(context, l10n.settingsClearChatsDone);
}

Future<void> _deleteModels(
  BuildContext context,
  WidgetRef ref,
  int usedBytes,
) async {
  final l10n = context.l10n;
  if (!await _confirm(
    context,
    title: l10n.settingsDeleteModelsTitle,
    body: l10n.settingsDeleteModelsBody(gigabytes(usedBytes)),
    action: l10n.modelsDelete,
    key: const Key('confirm-delete-models'),
  )) {
    return;
  }
  final outcome = await ref
      .read(settingsControllerProvider.notifier)
      .deleteAllModels();
  if (!context.mounted) return;
  final message = switch (outcome) {
    SettingsDone(:final count) => l10n.settingsDeleteModelsDone(count),
    _ => _describe(l10n, outcome),
  };
  if (message != null) _show(context, message);
}

Future<void> _setAppLock(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  final l10n = context.l10n;
  final outcome = await ref
      .read(settingsControllerProvider.notifier)
      .setAppLock(
        enabled: enabled,
        reason: l10n.lockReason(AppConstants.appName),
      );
  if (!context.mounted) return;
  final message = _describe(l10n, outcome);
  if (message != null) _show(context, message);
}

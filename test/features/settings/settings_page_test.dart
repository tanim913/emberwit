import 'dart:typed_data';

import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/app_preferences.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/features/settings/data/settings_providers.dart';
import 'package:emberwit/features/settings/presentation/model_licenses_page.dart';
import 'package:emberwit/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/catalog_fixtures.dart';
import '../../helpers/fake_runtime.dart';
import '../../helpers/test_app.dart';
import '../chat/domain/chat_responder_test.dart' show installed;
import '../model_manager/fakes.dart';
import 'fakes.dart';

class _Setup {
  final archive = FakeChatArchive();
  final files = FakeArchiveFiles();
  final auth = FakeAuthenticator();
  final library = FakeModelLibrary(
    LibraryState(installed: [installed('qwen3-q4'), installed('gemma-q4')]),
  );
}

Future<_Setup> _pump(WidgetTester tester, {Widget? page}) async {
  tester.view
    ..physicalSize = const Size(1080, 7000)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final setup = _Setup();
  await tester.pumpScreen(
    page ?? const SettingsPage(),
    overrides: [
      chatArchiveProvider.overrideWithValue(setup.archive),
      archiveFilesProvider.overrideWithValue(setup.files),
      modelLibraryProvider.overrideWithValue(setup.library),
      appVersionProvider.overrideWith((ref) async => '0.1.0 (1)'),
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(
          CatalogSnapshot(
            catalog: ModelCatalog(
              schemaVersion: 1,
              catalogVersion: 1,
              generatedAt: DateTime.utc(2026),
              models: [
                entry(id: 'qwen3-q4'),
                entry(id: 'gemma-q4', agreement: true),
              ],
            ),
            source: CatalogSource.bundled,
            loadedAt: DateTime.utc(2026),
          ),
        ),
      ),
    ],
  );
  return setup;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('shows every section and the version', (tester) async {
    await _pump(tester);
    for (final title in [
      'Appearance',
      'Chats',
      'Models and downloads',
      'Privacy and security',
      'Device',
      'About',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Version 0.1.0 (1)'), findsOneWidget);
    expect(find.text('2 models, 0.0 GB'), findsOneWidget);
  });

  testWidgets('changes the theme and language', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('settings-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('option-Dark')));
    await tester.pumpAndSettle();
    expect(
      _container(tester).read(appPreferencesProvider).themeMode,
      ThemeMode.dark,
    );

    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('option-বাংলা')));
    await tester.pumpAndSettle();
    expect(
      _container(tester).read(appPreferencesProvider).locale,
      const Locale('bn'),
    );
  });

  testWidgets('chooses the default model', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('settings-default-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('option-gemma-q4')));
    await tester.pumpAndSettle();
    expect(_container(tester).read(defaultModelIdProvider), 'gemma-q4');
    expect(find.text('gemma-q4'), findsOneWidget);
  });

  testWidgets('exports with a confirmed passphrase', (tester) async {
    final setup = await _pump(tester);
    await tester.tap(find.byKey(const Key('settings-export')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('passphrase')), 'short');
    await tester.tap(find.byKey(const Key('passphrase-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('passphrase')),
      'long passphrase',
    );
    await tester.enterText(
      find.byKey(const Key('passphrase-confirm')),
      'different one',
    );
    await tester.tap(find.byKey(const Key('passphrase-submit')));
    await tester.pumpAndSettle();
    expect(find.text('The passphrases do not match.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('passphrase-confirm')),
      'long passphrase',
    );
    await tester.tap(find.byKey(const Key('passphrase-submit')));
    await tester.pumpAndSettle();
    expect(setup.files.saved, hasLength(1));
    expect(find.text('Chats exported.'), findsOneWidget);
  });

  testWidgets('imports and reports how many chats were added', (tester) async {
    final setup = await _pump(tester);
    setup.files.toOpen = Uint8List.fromList('long passphrase'.codeUnits);
    await tester.tap(find.byKey(const Key('settings-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('passphrase')),
      'wrong passphrase',
    );
    await tester.tap(find.byKey(const Key('passphrase-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('Wrong passphrase, or the file was changed.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('passphrase')),
      'long passphrase',
    );
    await tester.tap(find.byKey(const Key('passphrase-submit')));
    await tester.pumpAndSettle();
    expect(find.text('2 chats added.'), findsOneWidget);
  });

  testWidgets('cancelling the file picker does nothing', (tester) async {
    final setup = await _pump(tester);
    await tester.tap(find.byKey(const Key('settings-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('passphrase')), findsNothing);
    expect(setup.archive.calls, isEmpty);
  });

  testWidgets('deletes all chats after confirmation', (tester) async {
    final setup = await _pump(tester);
    await tester.tap(find.byKey(const Key('settings-clear-chats')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(setup.archive.calls, isEmpty);

    await tester.tap(find.byKey(const Key('settings-clear-chats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-chats')));
    await tester.pumpAndSettle();
    expect(setup.archive.calls, ['deleteAll']);
    expect(find.text('All chats deleted.'), findsOneWidget);
  });

  testWidgets('deletes all models after confirmation', (tester) async {
    final setup = await _pump(tester);
    await tester.tap(find.byKey(const Key('settings-delete-models')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-models')));
    await tester.pumpAndSettle();
    expect(setup.library.calls, ['delete:qwen3-q4', 'delete:gemma-q4']);
    expect(find.text('2 models deleted.'), findsOneWidget);
  });

  testWidgets('turns the app lock on after authenticating', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('settings-app-lock')));
    await tester.pumpAndSettle();
    expect(_container(tester).read(appLockEnabledProvider), isTrue);
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings-app-lock')),
    );
    expect(tile.value, isTrue);
  });

  testWidgets('model licenses list catalog and installed models', (
    tester,
  ) async {
    await _pump(tester, page: const ModelLicensesPage());
    expect(find.byKey(const Key('license-qwen3-q4')), findsOneWidget);
    expect(
      find.text('Has use restrictions you accept when downloading.'),
      findsOneWidget,
    );
  });
}

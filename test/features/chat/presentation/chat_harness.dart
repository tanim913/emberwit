import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';
import 'package:emberwit/features/chat/data/chat_providers.dart';
import 'package:emberwit/features/chat/data/chat_repository_impl.dart';
import 'package:emberwit/features/chat/domain/chat_responder.dart';
import 'package:emberwit/features/chat/presentation/chat_page.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fixtures/device_fixtures.dart';
import '../../../helpers/chat_db.dart';
import '../../../helpers/fake_device_actions.dart';
import '../../../helpers/fake_inference_engine.dart';
import '../../../helpers/fake_voice_input.dart';
import '../../../helpers/preferences.dart';
import '../../../helpers/test_app.dart';
import '../../device_profiler/fakes.dart';
import '../../model_manager/fakes.dart';
import '../domain/chat_responder_test.dart' show installed;

/// Everything a chat screen test needs, with a real encrypted database.
class ChatHarness {
  new({
    FakeInferenceEngine? engine,
    LibraryState library = const LibraryState(),
    FakeVoiceInput? voice,
  }) : voice = voice ?? FakeVoiceInput(available: false),
       engine = engine ?? FakeInferenceEngine(tokens: ['Hi', ' there']),
       library = FakeModelLibrary(
         library.installed.isEmpty
             ? LibraryState(installed: [installed('qwen3-q4')])
             : library,
       ) {
    repository = ChatRepositoryImpl(db);
  }

  final ChatDatabase db = memoryChatDatabase();
  late final ChatRepositoryImpl repository;
  final FakeInferenceEngine engine;
  final FakeModelLibrary library;
  final FakeVoiceInput voice;

  /// Phone actions; none run unless a test turns them on.
  final FakeDeviceActions actions = FakeDeviceActions(supported: false);

  SharedPreferencesWithCache? _preferences;

  List<Override> get overrides => [
    ...baseOverrides(preferences: _preferences),
    chatDatabaseProvider.overrideWithValue(db),
    chatRepositoryProvider.overrideWithValue(repository),
    inferenceEngineProvider.overrideWithValue(engine),
    modelLibraryProvider.overrideWithValue(library),
    voiceInputProvider.overrideWithValue(voice),
    deviceActionsProvider.overrideWithValue(actions),
    chatResponderProvider.overrideWithValue(
      ChatResponder(
        engine: engine,
        models: library,
        repository: repository,
        threads: () => 2,
      ),
    ),
    deviceProfileRepositoryProvider.overrideWithValue(
      FakeDeviceProfileRepository(cached: profile()),
    ),
  ];

  /// Pumps [home] inside the app theme and localizations, with a router
  /// that knows the chat routes.
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(1080, 2340),
    Map<String, Object> values = const {},
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    _preferences ??= await tester.runAsync(() => inMemoryPreferences(values));
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        GoRoute(
          path: '/chats/:id',
          builder: (_, state) =>
              ChatPage(conversationId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/models', builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );
    await settle(tester);
  }

  /// Lets database streams and async work finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Unmounts the widget tree and lets drift's stream cleanup timers run.
  /// The in-memory database needs no closing; closing it from `runAsync`
  /// would wait on timers that live in the test's fake zone.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }
}

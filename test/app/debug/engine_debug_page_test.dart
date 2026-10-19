import 'dart:io';

import 'package:emberwit/app/debug/engine_debug_controller.dart';
import 'package:emberwit/app/debug/engine_debug_page.dart';
import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_inference_engine.dart';
import '../../helpers/test_app.dart';

void main() {
  late Directory models;

  setUp(() {
    models = Directory.systemTemp.createTempSync('models');
  });

  tearDown(() => models.deleteSync(recursive: true));

  Future<FakeInferenceEngine> pumpPage(
    WidgetTester tester, {
    FakeInferenceEngine? engine,
    Locale locale = const Locale('en'),
  }) async {
    final fake = engine ?? FakeInferenceEngine();
    tester.view
      ..physicalSize = const Size(1080, 4000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...baseOverrides(),
          inferenceEngineProvider.overrideWithValue(fake),
          debugModelsDirectoryProvider.overrideWith((ref) async => models),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const EngineDebugPage(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('explains where to put models when none exist', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('No models found in'), findsOneWidget);
    expect(find.textContaining('push_debug_model.sh'), findsOneWidget);
  });

  testWidgets('loads a model, generates and shows stats', (tester) async {
    File('${models.path}/tiny.gguf').writeAsBytesSync([0]);
    final engine = await pumpPage(tester);
    expect(find.text('tiny.gguf'), findsOneWidget);

    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    expect(find.text('fake 1M Q4'), findsOneWidget);
    expect(find.text('Loaded in 120 ms'), findsOneWidget);

    await tester.tap(find.byKey(const Key('debug-generate')));
    await tester.pumpAndSettle();
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('Time to first token: 40 ms'), findsOneWidget);
    expect(find.text('Stopped: end of text'), findsOneWidget);
    expect(engine.requests.single.prompt, isA<ChatPrompt>());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('debug-generate')));
    await tester.pumpAndSettle();
    expect(engine.requests.last.prompt, isA<RawPrompt>());

    await tester.tap(find.text('Unload'));
    await tester.pumpAndSettle();
    expect(find.text('fake 1M Q4'), findsNothing);
  });

  testWidgets('shows a friendly, localized load error', (tester) async {
    File('${models.path}/broken.gguf').writeAsBytesSync([0]);
    await pumpPage(
      tester,
      locale: const Locale('bn'),
      engine: FakeInferenceEngine(
        loadFailure: const ModelLoadFailure(
          ModelLoadFailureReason.insufficientMemory,
        ),
      ),
    );
    await tester.tap(find.text('লোড করুন'));
    await tester.pumpAndSettle();
    expect(find.textContaining('যথেষ্ট মেমরি নেই'), findsOneWidget);
  });

  test('stopReasonLabel covers every reason', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final labels = StopReason.values.map((r) => stopReasonLabel(l10n, r));
    expect(labels.toSet(), hasLength(StopReason.values.length));
  });
}

import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/features/device_profiler/presentation/device_check_page.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/device_fixtures.dart';
import '../../../helpers/test_app.dart';
import '../fakes.dart';

DeviceProfile _device({BenchmarkResult? benchmark}) =>
    profile(
      benchmark: benchmark,
      cpuFeatures: const ['dotprod', 'fp16', 'i8mm'],
    ).copyWith(
      deviceModel: 'Pixel 8',
      manufacturer: 'Google',
      batteryLevel: 81,
      isCharging: true,
    );

Future<FakeDeviceProfileRepository> _pump(
  WidgetTester tester,
  FakeDeviceProfileRepository repository, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 2600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...baseOverrides(),
        deviceProfileRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const DeviceCheckPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('shows tier, details and an unrun speed test', (tester) async {
    await _pump(tester, FakeDeviceProfileRepository(refreshed: _device()));
    expect(find.text('High end'), findsOneWidget);
    expect(find.text('Conversation memory: 4,096 tokens'), findsOneWidget);
    expect(find.text('Memory: 4.3 GB free of 8.6 GB'), findsOneWidget);
    expect(find.text('AI instructions: dotprod, fp16, i8mm'), findsOneWidget);
    expect(find.text('Battery: 81%, charging'), findsOneWidget);
    expect(find.text('System: Google Pixel 8, Android 14'), findsOneWidget);
    expect(find.textContaining('Not run yet'), findsOneWidget);
    expect(find.text('Run speed test'), findsOneWidget);
  });

  testWidgets('runs the speed test and shows the result', (tester) async {
    final repository = FakeDeviceProfileRepository(
      refreshed: _device(),
      benchmarkEvents: [
        const BenchmarkProgress(BenchmarkStage.loading, 0.2),
        BenchmarkFinished(_device(benchmark: benchmarkAt(42.5))),
      ],
    );
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('run-benchmark')));
    await tester.pumpAndSettle();
    expect(repository.benchmarkRuns, 1);
    expect(find.text('Speed: 42.5 tokens per second'), findsOneWidget);
    expect(find.text('First reply after 300 ms'), findsOneWidget);
    expect(find.text('Run again'), findsOneWidget);
  });

  testWidgets('a slow benchmark lowers the tier', (tester) async {
    await _pump(
      tester,
      FakeDeviceProfileRepository(
        refreshed: _device(benchmark: benchmarkAt(5)),
      ),
    );
    expect(find.text('Entry level'), findsOneWidget);
  });

  testWidgets('shows benchmark failures', (tester) async {
    await _pump(
      tester,
      FakeDeviceProfileRepository(
        refreshed: _device(),
        benchmarkEvents: const [BenchmarkFailed(BenchmarkUnavailableFailure())],
      ),
    );
    await tester.tap(find.byKey(const Key('run-benchmark')));
    await tester.pumpAndSettle();
    expect(find.textContaining('not included'), findsOneWidget);
  });

  testWidgets('shows a profiling failure when nothing is known', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeDeviceProfileRepository(
        refreshFailure: const DeviceProfilingFailure('x'),
      ),
    );
    expect(find.textContaining('Could not read'), findsOneWidget);
  });

  testWidgets('keeps the cached profile when a refresh fails', (tester) async {
    await _pump(
      tester,
      FakeDeviceProfileRepository(
        cached: _device(),
        refreshFailure: const DeviceProfilingFailure('x'),
      ),
    );
    expect(find.text('High end'), findsOneWidget);
    expect(find.textContaining('Could not read'), findsOneWidget);
  });

  testWidgets('warns about emulators and battery saver', (tester) async {
    await _pump(
      tester,
      FakeDeviceProfileRepository(
        refreshed: _device().copyWith(
          isPhysicalDevice: false,
          lowPowerMode: true,
        ),
      ),
    );
    expect(find.textContaining('emulator'), findsOneWidget);
    expect(find.textContaining('Battery saver'), findsOneWidget);
  });

  testWidgets('refresh button rereads the device', (tester) async {
    final repository = FakeDeviceProfileRepository(refreshed: _device());
    await _pump(tester, repository);
    repository.refreshed = _device().copyWith(
      batteryLevel: 12,
      isCharging: false,
    );
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Battery: 12%'), findsOneWidget);
  });

  group('goldens', () {
    for (final locale in const [Locale('en'), Locale('bn')]) {
      for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
        testWidgets(
          'device check ${locale.languageCode} ${mode.name}',
          tags: ['golden'],
          (tester) async {
            await _pump(
              tester,
              FakeDeviceProfileRepository(
                refreshed: _device(benchmark: benchmarkAt(42.5)),
              ),
              locale: locale,
              themeMode: mode,
            );
            await expectLater(
              find.byType(DeviceCheckPage),
              matchesGoldenFile(
                '../../../goldens/goldens/'
                'device_check_${locale.languageCode}_${mode.name}.png',
              ),
            );
          },
        );
      }
    }
  });
}

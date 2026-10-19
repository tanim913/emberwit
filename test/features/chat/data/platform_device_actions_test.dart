import 'package:emberwit/features/chat/data/platform_device_actions.dart';
import 'package:emberwit/features/chat/domain/device_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/device_actions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final actions = PlatformDeviceActions(channel: channel, supported: true);

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends alarms, timers and apps and reads outcomes', () async {
    answer(
      (call) => switch (call.method) {
        'setAlarm' => 'done',
        'setTimer' => 'unavailable',
        'openApp' => 'busy',
        _ => 'weird',
      },
    );
    expect(await actions.setAlarm(hour: 7, minute: 30), ActionOutcome.done);
    expect(await actions.setAlarm(), ActionOutcome.done);
    expect(
      await actions.setTimer(const Duration(minutes: 2)),
      ActionOutcome.unavailable,
    );
    expect(
      await actions.openApp(
        const InstalledApp(label: 'YouTube', packageName: 'com.yt'),
      ),
      ActionOutcome.busy,
    );
    expect(calls.map((c) => c.arguments), [
      {'hour': 7, 'minute': 30},
      {'minute': 0},
      {'seconds': 120},
      {'package': 'com.yt'},
    ]);
  });

  test('reads the flashlight state and the app list', () async {
    answer(
      (call) => switch (call.method) {
        'setTorch' => {'outcome': 'done', 'on': true},
        'installedApps' => [
          {'label': 'YouTube', 'package': 'com.yt'},
          {'label': null, 'package': 'broken'},
        ],
        _ => null,
      },
    );
    expect(await actions.setTorch(), (ActionOutcome.done, true));
    final apps = await actions.installedApps();
    expect(apps.single.label, 'YouTube');
    expect(apps.single.packageName, 'com.yt');
  });

  test('errors and missing hosts become outcomes', () async {
    answer((_) => throw PlatformException(code: 'x'));
    expect(await actions.setAlarm(hour: 1), ActionOutcome.failed);
    expect(await actions.setTorch(on: true), (ActionOutcome.failed, false));
    expect(await actions.installedApps(), isEmpty);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await actions.setTimer(Duration.zero), ActionOutcome.unavailable);
    expect(await actions.setTorch(), (ActionOutcome.unavailable, false));
    expect(await actions.installedApps(), isEmpty);
  });

  test('only Android runs actions by default', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(PlatformDeviceActions().supported, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(PlatformDeviceActions().supported, isTrue);
  });
}

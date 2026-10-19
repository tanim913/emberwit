import 'package:emberwit/features/chat/domain/device_actions.dart';
import 'package:emberwit/features/chat/domain/device_command.dart';
import 'package:emberwit/features/chat/domain/reply_language.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_device_actions.dart';

const _apps = [
  InstalledApp(label: 'YouTube', packageName: 'com.google.android.youtube'),
  InstalledApp(label: 'YouTube Music', packageName: 'com.google.music'),
  InstalledApp(label: 'Maps', packageName: 'com.google.maps'),
  InstalledApp(label: 'Google', packageName: 'com.google.search'),
  InstalledApp(label: 'WhatsApp', packageName: 'com.whatsapp'),
  InstalledApp(label: 'bKash', packageName: 'com.bkash'),
  InstalledApp(label: 'Camera', packageName: 'com.camera'),
];

void main() {
  const en = ReplyLanguage.english;
  const bn = ReplyLanguage.bengali;

  group('matchApp', () {
    InstalledApp? match(String name) => matchApp(name, _apps);

    test('exact, then prefix, then word, then all label words', () {
      expect(match('youtube')!.label, 'YouTube');
      expect(match('youtube music')!.label, 'YouTube Music');
      expect(match('whats')!.label, 'WhatsApp');
      expect(match('music')!.label, 'YouTube Music');
      expect(match('google maps')!.label, 'Maps');
      expect(match('bkash')!.label, 'bKash');
    });

    test('no app, no match', () {
      expect(match('the door'), isNull);
      expect(match(''), isNull);
    });
  });

  group('runDeviceCommand', () {
    late FakeDeviceActions actions;
    setUp(() => actions = FakeDeviceActions(apps: _apps));

    Future<String?> run(DeviceCommand c, [ReplyLanguage l = en]) =>
        runDeviceCommand(c, actions, l);

    test('alarms confirm the time in the message language', () async {
      expect(
        await run(const SetAlarm(hour: 7, minute: 5)),
        'Alarm set for 7:05 AM.',
      );
      expect(
        await run(const SetAlarm(hour: 19, minute: 30), bn),
        'সন্ধ্যা ৭:৩০-এ অ্যালার্ম দেওয়া হয়েছে।',
      );
      expect(await run(const SetAlarm(hour: 0)), 'Alarm set for 12:00 AM.');
      expect(await run(const SetAlarm()), contains('clock app'));
      expect(actions.log, [
        'alarm 7:5',
        'alarm 19:30',
        'alarm 0:0',
        'alarm null:0',
      ]);
    });

    test('timers', () async {
      expect(
        await run(const SetTimer(Duration(hours: 1, minutes: 30))),
        'Timer set for 1 hour 30 minutes.',
      );
      expect(
        await run(const SetTimer(Duration(minutes: 10)), bn),
        'টাইমার চালু হয়েছে: ১০ মিনিট।',
      );
    });

    test('flashlight on, toggle, off', () async {
      expect(await run(const SwitchTorch(on: true)), 'Flashlight on.');
      expect(await run(const SwitchTorch(), bn), 'টর্চ নেভানো হয়েছে।');
      expect(await run(const SwitchTorch()), 'Flashlight on.');
    });

    test('opens the installed app, or lets the model answer', () async {
      expect(await run(const OpenApp('youtube')), 'Opening YouTube.');
      expect(await run(const OpenApp('whatsapp'), bn), 'WhatsApp খোলা হচ্ছে।');
      expect(await run(const OpenApp('the door')), isNull);
      expect(actions.log, [
        'open com.google.android.youtube',
        'open com.whatsapp',
      ]);
    });

    test('explains failures', () async {
      actions.outcome = ActionOutcome.unavailable;
      expect(await run(const SetAlarm(hour: 7)), contains('no clock app'));
      expect(
        await run(const SwitchTorch(on: true)),
        'This phone has no flashlight.',
      );
      expect(await run(const SwitchTorch(on: true), bn), 'এই ফোনে টর্চ নেই।');
      actions.outcome = ActionOutcome.busy;
      expect(await run(const SwitchTorch(on: true)), contains('camera'));
      actions.outcome = ActionOutcome.failed;
      expect(await run(const OpenApp('camera')), "Couldn't open Camera.");
      expect(
        await run(const SetTimer(Duration(minutes: 1))),
        "That didn't work.",
      );
    });
  });
}

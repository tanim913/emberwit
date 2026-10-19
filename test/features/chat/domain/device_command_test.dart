import 'package:emberwit/features/chat/domain/device_command.dart';
import 'package:flutter_test/flutter_test.dart';

const String _longStory =
    'Write a story about a girl who opens a mysterious door in the old '
    'castle and finds a talking flashlight inside';

void main() {
  // 21:10 on a weekday.
  final now = DateTime(2026, 10, 19, 21, 10);
  DeviceCommand? parse(String text) => DeviceCommand.parse(text, now: now);

  group('alarms', () {
    for (final (text, hour, minute) in [
      ('Set an alarm for 7am', 7, 0),
      ('set alarm 6:30 pm', 18, 30),
      ('Wake me up at 5.45 a.m.', 5, 45),
      ('alarm at 22:15', 22, 15),
      ('Set an alarm for 7', 7, 0), // next 7 after 21:10 is 7:00
      ('Set an alarm for 11', 23, 0), // next 11 is 23:00
      ('alarm for 12 tonight', 0, 0),
      ('alarm at 10 at night', 22, 0),
      ('alarm 6 in the evening', 18, 0),
      ('Set an alarm in 30 minutes', 21, 40),
      ('alarm for 2 hours', 23, 10),
      ('সকাল ৭টায় অ্যালার্ম দাও', 7, 0),
      ('সকাল ৭টা ৩০ মিনিটে এলার্ম দাও', 7, 30),
      ('সাড়ে ৬টায় অ্যালার্ম', 6, 30), // next 6:30 after 21:10
      ('বিকেল সোয়া ৪টায় অ্যালার্ম দাও', 16, 15),
      ('রাত পৌনে ১১টায় অ্যালার্ম', 22, 45),
      ('৩০ মিনিট পরে অ্যালার্ম দাও', 21, 40),
      ('sokal 7 tay alarm dao', 7, 0),
      ('rat 10 tay alarm set koro', 22, 0),
      ('sare 8 tay alarm dio', 8, 30),
    ]) {
      test(text, () {
        expect(parse(text), SetAlarm(hour: hour, minute: minute));
      });
    }

    test('without a time the clock app asks', () {
      expect(parse('set an alarm'), const SetAlarm());
      expect(parse('অ্যালার্ম দাও'), const SetAlarm());
    });

    test('precomposed and decomposed Bengali letters both work', () {
      expect(parse('সাড়ে ৬টায় অ্যালার্ম'), parse('সাড়ে ৬টায় অ্যালার্ম'));
    });
  });

  group('timers', () {
    for (final (text, length) in [
      ('set a timer for 10 minutes', const Duration(minutes: 10)),
      ('timer 1 hour 30 mins', const Duration(hours: 1, minutes: 30)),
      ('start a timer for 45 seconds', const Duration(seconds: 45)),
      ('১০ মিনিটের টাইমার দাও', const Duration(minutes: 10)),
      ('5 minit er timer dao', const Duration(minutes: 5)),
    ]) {
      test(text, () => expect(parse(text), SetTimer(length)));
    }
    test('a timer without a length is not a command', () {
      expect(parse('set a timer'), isNull);
    });
  });

  group('flashlight', () {
    for (final (text, on) in [
      ('turn on the flashlight', true),
      ('Flashlight on', true),
      ('torch off', false),
      ('Turn off the torch please', false),
      ('switch the light on', true),
      ('টর্চ জ্বালাও', true),
      ('টর্চ বন্ধ করো', false),
      ('ফ্ল্যাশলাইট চালু করো', true),
      ('লাইট নিভাও', false),
      ('torch jalao', true),
      ('flashlight bondho koro', false),
    ]) {
      test(text, () => expect(parse(text), SwitchTorch(on: on)));
    }
    test('the word alone toggles', () {
      expect(parse('flashlight'), const SwitchTorch());
      expect(parse('Torch!'), const SwitchTorch());
      expect(parse('light'), isNull);
    });
  });

  group('apps', () {
    for (final (text, name) in [
      ('open YouTube', 'youtube'),
      ('Open the camera app', 'camera'),
      ('launch google maps', 'google maps'),
      ('can you open whatsapp for me', 'whatsapp'),
      ('Please open Settings.', 'settings'),
      ('YouTube kholo', 'youtube'),
      ('whatsapp ta open koro', 'whatsapp'),
      ('ইউটিউব খোলো', 'youtube'),
      ('ফেসবুক অ্যাপটা খুলুন', 'facebook'),
      ('bKash খোলো', 'bkash'),
      ('camera open', 'camera'),
    ]) {
      test(text, () => expect(parse(text), OpenApp(name)));
    }
  });

  group('not commands', () {
    for (final text in [
      'How do I set an alarm in Python?',
      'What is a torch?',
      'Explain how a flashlight works',
      'why does my alarm not ring',
      'Tell me about YouTube',
      'কিভাবে অ্যালার্ম দিতে হয়?',
      _longStory,
      'set alarm\nand tell me a joke',
      'What is 2+2?',
      'hello',
    ]) {
      test(text, () => expect(parse(text), isNull));
    }
  });
}

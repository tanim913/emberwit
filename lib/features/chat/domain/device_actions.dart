import 'package:emberwit/features/chat/domain/device_command.dart';
import 'package:emberwit/features/chat/domain/reply_language.dart';
import 'package:flutter/foundation.dart';

/// How a phone action went.
enum ActionOutcome {
  /// Done.
  done,

  /// The phone cannot do it (no clock app, no flashlight).
  unavailable,

  /// Something else is using what the action needs (the camera has the
  /// flashlight).
  busy,

  /// Anything else.
  failed,
}

/// An app that can be opened from the launcher.
@immutable
final class InstalledApp {
  /// Creates the entry.
  const new({required this.label, required this.packageName});

  /// Name shown under the launcher icon.
  final String label;

  /// Android package name.
  final String packageName;
}

/// Phone actions the chat can run: alarms, timers, the flashlight and
/// opening apps. Everything is local; nothing is sent anywhere.
abstract interface class DeviceActions {
  /// Whether this platform runs actions at all.
  bool get supported;

  /// Sets an alarm with the clock app, or opens its new alarm screen when
  /// [hour] is `null`.
  Future<ActionOutcome> setAlarm({int? hour, int minute = 0});

  /// Starts a timer with the clock app.
  Future<ActionOutcome> setTimer(Duration length);

  /// Turns the flashlight on or off ([on] `null` toggles). Returns the
  /// outcome and the flashlight's state afterwards.
  Future<(ActionOutcome, bool)> setTorch({bool? on});

  /// Apps the launcher shows, except this one.
  Future<List<InstalledApp>> installedApps();

  /// Opens [app].
  Future<ActionOutcome> openApp(InstalledApp app);
}

/// Runs [command] and returns the sentence to show as the reply, in
/// [language]. Returns `null` when an [OpenApp] names no installed app, so
/// the message goes to the model instead.
Future<String?> runDeviceCommand(
  DeviceCommand command,
  DeviceActions actions,
  ReplyLanguage language,
) async {
  final bn = language == ReplyLanguage.bengali;
  String say(String english, String bengali) => bn ? bengali : english;
  switch (command) {
    case SetAlarm(:final hour, :final minute):
      final outcome = await actions.setAlarm(hour: hour, minute: minute);
      if (outcome != ActionOutcome.done) return _failure(outcome, bn);
      if (hour == null) {
        return say(
          'I opened the clock app so you can set the alarm.',
          'অ্যালার্ম দিতে ঘড়ি অ্যাপ খুলে দিয়েছি।',
        );
      }
      return say(
        'Alarm set for ${_englishTime(hour, minute)}.',
        '${_bengaliTime(hour, minute)}-এ অ্যালার্ম দেওয়া হয়েছে।',
      );
    case SetTimer(:final length):
      final outcome = await actions.setTimer(length);
      if (outcome != ActionOutcome.done) return _failure(outcome, bn);
      return say(
        'Timer set for ${_englishLength(length)}.',
        'টাইমার চালু হয়েছে: ${_bengaliLength(length)}।',
      );
    case SwitchTorch(:final on):
      final (outcome, lit) = await actions.setTorch(on: on);
      if (outcome == ActionOutcome.unavailable) {
        return say('This phone has no flashlight.', 'এই ফোনে টর্চ নেই।');
      }
      if (outcome != ActionOutcome.done) return _failure(outcome, bn);
      return lit
          ? say('Flashlight on.', 'টর্চ জ্বালানো হয়েছে।')
          : say('Flashlight off.', 'টর্চ নেভানো হয়েছে।');
    case OpenApp(:final name):
      final app = matchApp(name, await actions.installedApps());
      if (app == null) return null;
      final outcome = await actions.openApp(app);
      if (outcome != ActionOutcome.done) {
        return say("Couldn't open ${app.label}.", '${app.label} খোলা গেল না।');
      }
      return say('Opening ${app.label}.', '${app.label} খোলা হচ্ছে।');
  }
}

String _failure(ActionOutcome outcome, bool bn) => switch (outcome) {
  ActionOutcome.unavailable =>
    bn
        ? 'এই ফোনে অ্যালার্ম দেওয়ার মতো কোনো ঘড়ি অ্যাপ নেই।'
        : 'This phone has no clock app that can set alarms.',
  ActionOutcome.busy =>
    bn
        ? 'টর্চটি এখন অন্য একটি অ্যাপ (যেমন ক্যামেরা) ব্যবহার করছে।'
        : 'Another app, such as the camera, is using the flashlight.',
  _ => bn ? 'কাজটি করা গেল না।' : "That didn't work.",
};

/// The installed app [name] means: an exact label match, else a label
/// starting with it, else a label containing it as a word, else one whose
/// words all appear in [name] ("google maps" finds "Maps"). Shorter labels
/// win ties. Case, spaces and punctuation are ignored.
InstalledApp? matchApp(String name, List<InstalledApp> apps) {
  final wanted = _key(name);
  if (wanted.isEmpty) return null;
  final wantedWords = _words(name);
  int? rank(InstalledApp app) {
    final label = _key(app.label);
    if (label.isEmpty) return null;
    if (label == wanted) return 0;
    if (label.startsWith(wanted)) return 1;
    if (_words(app.label).contains(wanted)) return 2;
    if (_words(app.label).every(wantedWords.contains)) return 3;
    return null;
  }

  InstalledApp? best;
  var bestRank = 99;
  for (final app in apps) {
    final r = rank(app);
    if (r == null) continue;
    if (r < bestRank ||
        r == bestRank && app.label.length < best!.label.length) {
      best = app;
      bestRank = r;
    }
  }
  return best;
}

String _key(String text) =>
    text.toLowerCase().replaceAll(RegExp('[^a-z0-9\u0980-\u09FF]'), '');

Set<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp('[^a-z0-9\u0980-\u09FF]+'))
    .where((w) => w.isNotEmpty)
    .toSet();

String _englishTime(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  final m = minute.toString().padLeft(2, '0');
  return '$h:$m ${hour < 12 ? 'AM' : 'PM'}';
}

String _bengaliTime(int hour, int minute) {
  final part = switch (hour) {
    >= 4 && < 6 => 'ভোর',
    >= 6 && < 12 => 'সকাল',
    >= 12 && < 15 => 'দুপুর',
    >= 15 && < 18 => 'বিকেল',
    >= 18 && < 20 => 'সন্ধ্যা',
    _ => 'রাত',
  };
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$part ${_bengaliDigits('$h:${minute.toString().padLeft(2, '0')}')}';
}

String _englishLength(Duration length) {
  final parts = [
    if (length.inHours > 0)
      '${length.inHours} hour${length.inHours == 1 ? '' : 's'}',
    if (length.inMinutes % 60 > 0)
      '${length.inMinutes % 60} minute${length.inMinutes % 60 == 1 ? '' : 's'}',
    if (length.inSeconds % 60 > 0)
      '${length.inSeconds % 60} second${length.inSeconds % 60 == 1 ? '' : 's'}',
  ];
  return parts.join(' ');
}

String _bengaliLength(Duration length) {
  final parts = [
    if (length.inHours > 0) '${_bengaliDigits('${length.inHours}')} ঘণ্টা',
    if (length.inMinutes % 60 > 0)
      '${_bengaliDigits('${length.inMinutes % 60}')} মিনিট',
    if (length.inSeconds % 60 > 0)
      '${_bengaliDigits('${length.inSeconds % 60}')} সেকেন্ড',
  ];
  return parts.join(' ');
}

String _bengaliDigits(String text) => String.fromCharCodes(
  text.codeUnits.map((c) => c >= 0x30 && c <= 0x39 ? c - 0x30 + 0x09E6 : c),
);

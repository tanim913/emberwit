import 'package:flutter/foundation.dart';

/// A phone action asked for in a chat message, in English, Bengali or
/// Bengali typed in Latin letters.
///
/// Commands are recognized with fixed rules, never by the model: a small
/// model guessing actions would set wrong alarms or open wrong apps. Only
/// short, imperative messages count; questions such as "how do I set an
/// alarm?" go to the model as usual.
@immutable
sealed class DeviceCommand {
  const new();

  /// The command in [text], or `null` when it is not one. [now] resolves
  /// times without AM or PM to their next occurrence.
  static DeviceCommand? parse(String text, {required DateTime now}) {
    final normalized = _normalize(text);
    if (normalized.isEmpty ||
        normalized.length > _maxLength ||
        text.contains('\n') ||
        _question.hasMatch(normalized)) {
      return null;
    }
    return _timer(normalized) ??
        _alarm(normalized, now) ??
        _torch(normalized) ??
        _openApp(normalized);
  }
}

/// Sets an alarm at [hour]:[minute] (24 hour clock), or opens the clock
/// app's new alarm screen when no time was given.
final class SetAlarm extends DeviceCommand {
  /// Creates the command.
  const new({this.hour, this.minute = 0});

  /// Hour, 0 to 23, or `null` to let the user pick.
  final int? hour;

  /// Minute, 0 to 59.
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is SetAlarm && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'SetAlarm($hour:$minute)';
}

/// Starts a countdown timer.
final class SetTimer extends DeviceCommand {
  /// Creates the command.
  const new(this.length);

  /// How long the timer runs.
  final Duration length;

  @override
  bool operator ==(Object other) => other is SetTimer && other.length == length;

  @override
  int get hashCode => length.hashCode;

  @override
  String toString() => 'SetTimer($length)';
}

/// Turns the flashlight on or off, or toggles it when [on] is `null`.
final class SwitchTorch extends DeviceCommand {
  /// Creates the command.
  const new({this.on});

  /// The wanted state, `null` to toggle.
  final bool? on;

  @override
  bool operator ==(Object other) => other is SwitchTorch && other.on == on;

  @override
  int get hashCode => on.hashCode;

  @override
  String toString() => 'SwitchTorch($on)';
}

/// Opens the installed app called [name].
final class OpenApp extends DeviceCommand {
  /// Creates the command.
  const new(this.name);

  /// The app name as said, lower case, in Latin letters when a common
  /// Bengali spelling was used ("ইউটিউব" becomes "youtube").
  final String name;

  @override
  bool operator ==(Object other) => other is OpenApp && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'OpenApp($name)';
}

/// Longest message, in characters, that can be a command.
const int _maxLength = 80;

/// Lower case, ASCII digits, no surrounding punctuation, single spaces.
String _normalize(String text) {
  final digits = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if (rune >= 0x09E6 && rune <= 0x09EF) {
      // Bengali digits ০ to ৯.
      digits.writeCharCode(rune - 0x09E6 + 0x30);
    } else if (_nukta.containsKey(rune)) {
      // ড়, ঢ় and য় typed as one character: written here as letter plus
      // nukta, the form the patterns use.
      digits
        ..writeCharCode(_nukta[rune]!)
        ..writeCharCode(0x09BC);
    } else {
      digits.writeCharCode(rune);
    }
  }
  return digits
      .toString()
      .replaceAll(RegExp('[!?।,;"“”]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'[.\s]+$'), '');
}

const Map<int, int> _nukta = {0x09DC: 0x09A1, 0x09DD: 0x09A2, 0x09DF: 0x09AF};

/// Messages that ask about something rather than ask for it.
final RegExp _question = RegExp(
  '^(how|what|why|when|where|who|which|explain|describe|tell me about|'
  'is|are|does|do|কিভাবে|কীভাবে|কেন|কী|কি ভাবে|kivabe|kibhabe|keno) ',
);

// Timers ---------------------------------------------------------------------

final RegExp _timerWord = RegExp('timer|টাইমার');

final RegExp _durationPart = RegExp(
  r'(\d+)\s*(hours?|hrs?|ঘণ্টা|ঘন্টা|ghonta|minutes?|mins?|মিনিট|minit|'
  'seconds?|secs?|সেকেন্ড|second)',
);

DeviceCommand? _timer(String text) {
  if (!_timerWord.hasMatch(text)) return null;
  var length = Duration.zero;
  for (final m in _durationPart.allMatches(text)) {
    final amount = int.parse(m[1]!);
    final unit = m[2]!;
    if (_isHours(unit)) {
      length += Duration(hours: amount);
    } else if (unit.startsWith('m') || unit.startsWith('ম')) {
      length += Duration(minutes: amount);
    } else {
      length += Duration(seconds: amount);
    }
  }
  if (length == Duration.zero || length > const Duration(hours: 24)) {
    return null;
  }
  return SetTimer(length);
}

// Alarms ---------------------------------------------------------------------

final RegExp _alarmWord = RegExp(
  'alarm|wake me|অ্যালার্ম|এলার্ম|আলার্ম|elarm|ঘুম থেকে তুল',
);

final RegExp _clock = RegExp(
  r'(?<![\d:])(\d{1,2})(?:[:.](\d{2}))?\s*'
  r'(a\.?m\.?|p\.?m\.?|টায়|টার|টা|tay|tar|ta)?(?![\d:])',
);

final RegExp _extraMinutes = RegExp(r'^\s*(\d{1,2})\s*(মিনিট|minit|min)');

final RegExp _relative = RegExp(
  r'(?:in|for|after) (\d+)\s*(hours?|hrs?|minutes?|mins?)|'
  r'(\d+)\s*(ঘণ্টা|ঘন্টা|ghonta|মিনিট|minit)\s*(পরে|পর|pore|por)',
);

/// "Half past", "quarter past" and "quarter to" in Bengali: সাড়ে ৭টা is
/// 7:30, সোয়া ৭টা 7:15 and পৌনে ৮টা 7:45.
final RegExp _bengaliFraction = RegExp(
  '(সাড়ে|sare|shade|sade|সোয়া|soa|shoa|sowa|পৌনে|poune|pone) ?'
  r'(\d{1,2})',
);

const Map<String, int> _fractionMinutes = {
  'সাড়ে': 30,
  'sare': 30,
  'shade': 30,
  'sade': 30,
  'সোয়া': 15,
  'soa': 15,
  'shoa': 15,
  'sowa': 15,
  'পৌনে': -15,
  'poune': -15,
  'pone': -15,
};

DeviceCommand? _alarm(String text, DateTime now) {
  if (!_alarmWord.hasMatch(text)) return null;
  final relative = _relative.firstMatch(text);
  if (relative != null) {
    final amount = int.parse(relative[1] ?? relative[3]!);
    final unit = relative[2] ?? relative[4]!;
    final at = now.add(
      _isHours(unit) ? Duration(hours: amount) : Duration(minutes: amount),
    );
    return SetAlarm(hour: at.hour, minute: at.minute);
  }

  int? hour;
  var minute = 0;
  String? marker;
  final fraction = _bengaliFraction.firstMatch(text);
  if (fraction != null) {
    hour = int.parse(fraction[2]!);
    final offset = _fractionMinutes[fraction[1]]!;
    if (offset < 0) {
      hour = (hour + 23) % 24; // পৌনে ৮টা is a quarter to 8.
      minute = 60 + offset;
    } else {
      minute = offset;
    }
  } else {
    final m = _clock.firstMatch(text);
    if (m == null) return const SetAlarm();
    hour = int.parse(m[1]!);
    minute = m[2] == null
        ? int.parse(_extraMinutes.firstMatch(text.substring(m.end))?[1] ?? '0')
        : int.parse(m[2]!);
    marker = m[3];
  }
  if (hour > 23 || minute > 59) return null;

  final resolved = switch (_dayPart(text, marker)) {
    _DayPart.am => hour == 12 ? 0 : hour,
    _DayPart.pm => hour < 12 ? hour + 12 : hour,
    _DayPart.night =>
      hour == 12 ? 0 : (hour >= 6 && hour < 12 ? hour + 12 : hour),
    null when hour == 0 || hour > 12 => hour,
    null => _next(hour, minute, now),
  };
  return SetAlarm(hour: resolved, minute: minute);
}

bool _isHours(String unit) =>
    unit.startsWith('h') || unit.startsWith('ঘ') || unit.startsWith('gh');

enum _DayPart { am, pm, night }

final RegExp _morning = RegExp(
  r'\b(morning|sokal|shokal|sakal|vor|bhor)\b|সকাল|ভোর',
);

final RegExp _afternoon = RegExp(
  r'\b(afternoon|evening|noon|dupur|bikal|bikel|sondha|shondha|sondhya)\b|'
  'দুপুর|বিকাল|বিকেল|সন্ধ্যা',
);

final RegExp _night = RegExp(r'\b(night|tonight|raat|rat|rate)\b|রাত');

_DayPart? _dayPart(String text, String? marker) {
  if (marker != null && marker.startsWith('a')) return _DayPart.am;
  if (marker != null && marker.startsWith('p')) return _DayPart.pm;
  if (_morning.hasMatch(text)) return _DayPart.am;
  if (_afternoon.hasMatch(text)) return _DayPart.pm;
  if (_night.hasMatch(text)) return _DayPart.night;
  return null;
}

/// [hour] (1 to 12, no AM or PM) as whichever of hour:minute and
/// (hour + 12):minute comes next after [now].
int _next(int hour, int minute, DateTime now) {
  final morning = hour % 12;
  final nowMinutes = now.hour * 60 + now.minute;
  int until(int h) => (h * 60 + minute - nowMinutes) % (24 * 60);
  return until(morning) <= until(morning + 12) ? morning : morning + 12;
}

// Flashlight -----------------------------------------------------------------

final RegExp _torchWord = RegExp(
  'flashlight|flash light|torch|টর্চ|ফ্ল্যাশলাইট|ফ্লাশলাইট|ফ্ল্যাশ লাইট|লাইট|'
  r'\blight\b|\bflash\b',
);

final RegExp _onWord = RegExp(
  r'\bon\b|জ্বালাও|জ্বালান|জ্বালো|জালাও|চালু|অন|jalao|jalan|jalo|chalu',
);

final RegExp _offWord = RegExp(
  r'\boff\b|নিভাও|নেভাও|নিভিয়ে|বন্ধ|অফ|nivao|nevao|nibhao|bondho|bondo|bndho',
);

DeviceCommand? _torch(String text) {
  final word = _torchWord.firstMatch(text);
  if (word == null) return null;
  final strong = !RegExp(r'^(light|flash|লাইট)$').hasMatch(word[0]!);
  final off = _offWord.hasMatch(text);
  final on = _onWord.hasMatch(text);
  if (off) return const SwitchTorch(on: false);
  if (on) return const SwitchTorch(on: true);
  // A bare "flashlight" or "torch" toggles; "light" alone is too vague.
  if (strong && text.split(' ').length <= 2) return const SwitchTorch();
  return null;
}

// Apps -----------------------------------------------------------------------

final RegExp _openFirst = RegExp(
  '^(?:(?:can|could|would) you |please |plz )*(?:open|launch|start|run)'
  r'(?: the| my)? (.+?)(?: app| application)?(?: for me)?(?: please| plz)?$',
);

final RegExp _openLast = RegExp(
  '^(.+?)(?: অ্যাপটা| অ্যাপটি| অ্যাপ| app ta| app ti| app| ta| টা)? '
  '(?:খোলো|খুলুন|খোল|খুলে দাও|চালু করো|চালু কর|চালাও|ওপেন করো|ওপেন কর|'
  r'open koro|open kor|open করো|kholo|khulo|khol|chalu koro|chalao|open)$',
);

/// Common app names written in Bengali script, in the Latin spelling their
/// launcher labels use.
const Map<String, String> _bengaliAppNames = {
  'ইউটিউব': 'youtube',
  'হোয়াটসঅ্যাপ': 'whatsapp',
  'হোয়াটসআপ': 'whatsapp',
  'ফেসবুক': 'facebook',
  'মেসেঞ্জার': 'messenger',
  'ইমো': 'imo',
  'বিকাশ': 'bkash',
  'নগদ': 'nagad',
  'ক্যামেরা': 'camera',
  'ক্যালকুলেটর': 'calculator',
  'গ্যালারি': 'gallery',
  'সেটিংস': 'settings',
  'সেটিং': 'settings',
  'ক্রোম': 'chrome',
  'ঘড়ি': 'clock',
  'ম্যাপ': 'maps',
  'ম্যাপস': 'maps',
  'জিমেইল': 'gmail',
  'ইনস্টাগ্রাম': 'instagram',
  'টেলিগ্রাম': 'telegram',
  'টিকটক': 'tiktok',
  'স্পটিফাই': 'spotify',
  'ক্যালেন্ডার': 'calendar',
  'ফোন': 'phone',
  'মেসেজ': 'messages',
  'কন্টাক্ট': 'contacts',
  'ফাইল': 'files',
};

DeviceCommand? _openApp(String text) {
  final match = _openFirst.firstMatch(text) ?? _openLast.firstMatch(text);
  if (match == null) return null;
  var name = match[1]!.trim();
  if (name.isEmpty || name.split(' ').length > 4) return null;
  name = _bengaliAppNames[name] ?? name;
  return OpenApp(name);
}

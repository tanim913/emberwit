import 'package:flutter/foundation.dart';

/// Language voice typing listens for.
enum VoiceLanguage {
  /// English.
  english(['en-US', 'en-GB', 'en-IN']),

  /// Bengali.
  bengali(['bn-BD', 'bn-IN']);

  new(this.tags);

  /// BCP 47 tags in order of preference; any other region of the same
  /// language is accepted too.
  final List<String> tags;

  /// The language for a locale's [languageCode], English for any other.
  static VoiceLanguage forLanguageCode(String? languageCode) =>
      languageCode == 'bn' ? VoiceLanguage.bengali : VoiceLanguage.english;
}

/// Why voice typing did not work.
enum VoiceProblem {
  /// The user did not allow the microphone.
  permissionDenied,

  /// The phone has no offline speech recognizer.
  unavailable,

  /// The phone can recognize the language offline once its pack is
  /// downloaded.
  notInstalled,

  /// The language pack is being downloaded.
  downloading,

  /// The phone cannot recognize the language offline at all.
  unsupported,

  /// Nothing was heard, or nothing was understood.
  noSpeech,

  /// Another app is using the recognizer.
  busy,

  /// Anything else.
  failed;

  /// The problem for a native error code.
  static VoiceProblem fromCode(String? code) => switch (code) {
    'permission' => VoiceProblem.permissionDenied,
    'unavailable' => VoiceProblem.unavailable,
    'not_installed' => VoiceProblem.notInstalled,
    'downloading' => VoiceProblem.downloading,
    'unsupported' => VoiceProblem.unsupported,
    'no_speech' => VoiceProblem.noSpeech,
    'busy' => VoiceProblem.busy,
    _ => VoiceProblem.failed,
  };
}

/// What the recognizer reports while listening.
@immutable
sealed class VoiceEvent {
  const new();
}

/// The microphone is open.
final class VoiceReady extends VoiceEvent {
  /// Creates the event.
  const new();
}

/// Loudness of the speech, about 0 (silence) to 1.
final class VoiceLevel extends VoiceEvent {
  /// Creates the event.
  const new(this.level);

  /// Loudness, 0 to 1.
  final double level;
}

/// Text heard so far ([isFinal] false) or the finished text.
final class VoiceText extends VoiceEvent {
  /// Creates the event.
  const new(this.text, {required this.isFinal});

  /// Recognized text.
  final String text;

  /// Whether listening ended with this text.
  final bool isFinal;
}

/// Listening ended with [problem].
final class VoiceFailed extends VoiceEvent {
  /// Creates the event.
  const new(this.problem);

  /// What went wrong.
  final VoiceProblem problem;
}

/// Voice typing with the phone's offline speech recognizer. Audio never
/// leaves the phone and is never stored; only the recognized text is
/// returned.
abstract interface class VoiceInput {
  /// Whether this phone can recognize speech offline.
  Future<bool> isAvailable();

  /// Events of the current listening session.
  Stream<VoiceEvent> get events;

  /// Starts listening for [language]. Asks for the microphone the first
  /// time. Returns the problem when listening could not start.
  Future<VoiceProblem?> start(VoiceLanguage language);

  /// Stops listening and delivers the final text.
  Future<void> stop();

  /// Stops listening and drops the text.
  Future<void> cancel();

  /// Asks the phone to download [language]'s offline pack. Returns false
  /// when the phone cannot do it from the app.
  Future<bool> install(VoiceLanguage language);
}

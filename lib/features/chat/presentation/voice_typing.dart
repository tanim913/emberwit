import 'dart:async';

import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/features/chat/data/chat_providers.dart';
import 'package:emberwit/features/chat/domain/voice_input.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'voice_typing.freezed.dart';
part 'voice_typing.g.dart';

/// What the voice typing controls show.
@freezed
abstract class VoiceTypingState with _$VoiceTypingState {
  /// Creates the state.
  const factory({
    /// Whether the phone can recognize speech offline.
    @Default(false) bool available,

    /// Language chosen by the user; `null` follows the app language.
    VoiceLanguage? language,

    /// Listening (or about to).
    @Default(false) bool listening,

    /// The microphone is open: what is said now is heard. False while the
    /// recognizer starts, which can take a moment the first time.
    @Default(false) bool ready,

    /// Counts listening sessions, so the screen knows when one starts.
    @Default(0) int session,

    /// Loudness of the speech, 0 to 1.
    @Default(0) double level,

    /// Text heard in the current or last session.
    @Default('') String text,

    /// Why the last session failed.
    VoiceProblem? problem,

    /// Language the failed session listened for.
    VoiceLanguage? problemLanguage,

    /// The failed language was dropped and English is chosen again.
    @Default(false) bool backToEnglish,
  }) = _VoiceTypingState;
}

/// Problems that make a language unusable until something changes on the
/// phone. Such a language is not kept as the choice.
const Set<VoiceProblem> _unusable = {
  VoiceProblem.unsupported,
  VoiceProblem.notInstalled,
  VoiceProblem.downloading,
};

/// Voice typing in the chat composer: start, stop, switch language.
///
/// Recognized text is only held here until the screen puts it in the message
/// field. Nothing is saved except the chosen language.
@riverpod
class VoiceTyping extends _$VoiceTyping {
  StreamSubscription<VoiceEvent>? _events;
  VoiceLanguage? _listeningFor;
  bool _retried = false;

  @override
  VoiceTypingState build() {
    final voice = ref.watch(voiceInputProvider);
    final saved = ref
        .watch(sharedPreferencesProvider)
        .getString(PreferenceKeys.voiceLanguage);
    ref.onDispose(() {
      // Leaving the chat stops a session that may still be listening.
      if (_events != null) unawaited(voice.cancel());
      unawaited(_events?.cancel());
    });
    unawaited(
      voice.isAvailable().then((available) {
        if (ref.mounted) state = state.copyWith(available: available);
      }),
    );
    return VoiceTypingState(language: VoiceLanguage.values.asNameMap()[saved]);
  }

  /// Starts listening for [language].
  Future<void> start(VoiceLanguage language) async {
    if (state.listening) return;
    _retried = false;
    state = state.copyWith(
      listening: true,
      ready: false,
      session: state.session + 1,
      level: 0,
      text: '',
      problem: null,
      problemLanguage: null,
      backToEnglish: false,
    );
    await _listen(language);
  }

  Future<void> _listen(VoiceLanguage language) async {
    final voice = ref.read(voiceInputProvider);
    // Subscribed on first use, so phones without a recognizer never open
    // the native event channel.
    _events ??= voice.events.listen(_onEvent);
    _listeningFor = language;
    final problem = await voice.start(language);
    if (problem != null && ref.mounted && state.listening) {
      await _fail(problem, language);
    }
  }

  /// Ends the session with [problem]. A language other than English that
  /// cannot listen right now is not kept: the choice goes back to English,
  /// so the user is never stuck with a language the phone lacks.
  Future<void> _fail(VoiceProblem problem, VoiceLanguage language) async {
    final drop =
        _unusable.contains(problem) && language != VoiceLanguage.english;
    state = state.copyWith(
      listening: false,
      ready: false,
      level: 0,
      problem: problem,
      problemLanguage: language,
      backToEnglish: drop,
      language: drop ? VoiceLanguage.english : state.language,
    );
    if (drop) await _save(VoiceLanguage.english);
  }

  /// Stops listening; the text heard so far is kept.
  Future<void> stop() => ref.read(voiceInputProvider).stop();

  /// Stops listening and drops what was heard.
  Future<void> cancel() async {
    if (!state.listening) return;
    state = state.copyWith(listening: false, ready: false, text: '', level: 0);
    await ref.read(voiceInputProvider).cancel();
  }

  /// Remembers [language] and, when listening, starts again with it.
  Future<void> switchLanguage(VoiceLanguage language) async {
    final restart = state.listening;
    await cancel();
    state = state.copyWith(language: language);
    await _save(language);
    if (restart && ref.mounted) await start(language);
  }

  Future<void> _save(VoiceLanguage language) => ref
      .read(sharedPreferencesProvider)
      .setString(PreferenceKeys.voiceLanguage, language.name);

  /// Asks the phone to download [language]'s offline pack.
  Future<bool> install(VoiceLanguage language) =>
      ref.read(voiceInputProvider).install(language);

  void _onEvent(VoiceEvent event) {
    if (!state.listening) return;
    switch (event) {
      case VoiceReady():
        state = state.copyWith(ready: true);
      case VoiceLevel(:final level):
        state = state.copyWith(level: level, ready: true);
      case VoiceText(:final text, :final isFinal):
        state = state.copyWith(text: text, listening: !isFinal, level: 0);
      case VoiceFailed(problem: VoiceProblem.noSpeech)
          when state.text.isEmpty && !_retried && _listeningFor != null:
        // The first session after the app opens often ends before the
        // recognizer hears anything (it is still starting when the user
        // speaks). Listen once more instead of asking to try again.
        _retried = true;
        state = state.copyWith(ready: false, level: 0);
        unawaited(_listen(_listeningFor!));
      case VoiceFailed(:final problem):
        // Silence after some words just ends the session.
        if (problem == VoiceProblem.noSpeech && state.text != '') {
          state = state.copyWith(listening: false, ready: false, level: 0);
        } else {
          unawaited(_fail(problem, _listeningFor ?? VoiceLanguage.english));
        }
    }
  }
}

/// [base] (what was in the message field) followed by the [heard] text,
/// with one space between them.
String joinDictation(String base, String heard) {
  final words = heard.trim();
  if (words.isEmpty) return base;
  if (base.isEmpty || base.endsWith(' ') || base.endsWith('\n')) {
    return '$base$words';
  }
  return '$base $words';
}

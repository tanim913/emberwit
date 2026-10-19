import 'dart:async';

import 'package:emberwit/features/chat/domain/voice_input.dart';

/// Scripted [VoiceInput]: tests push events with [emit].
final class FakeVoiceInput implements VoiceInput {
  /// Creates the fake. [available] is what [isAvailable] answers.
  new({this.available = true});

  /// Whether the phone "has" an offline recognizer.
  bool available;

  /// Returned by the next [start].
  VoiceProblem? startProblem;

  /// Returned by [install].
  bool installs = true;

  /// Languages [start] was called with.
  final List<VoiceLanguage> started = [];

  /// Languages [install] was called with.
  final List<VoiceLanguage> installed = [];

  /// Calls to [stop] and [cancel].
  int stops = 0;
  int cancels = 0;

  final StreamController<VoiceEvent> _events = StreamController.broadcast();

  /// Sends [event] as the recognizer would.
  void emit(VoiceEvent event) => _events.add(event);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<VoiceProblem?> start(VoiceLanguage language) async {
    started.add(language);
    return startProblem;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<bool> install(VoiceLanguage language) async {
    installed.add(language);
    return installs;
  }
}

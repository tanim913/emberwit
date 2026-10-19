import 'package:emberwit/features/chat/domain/voice_input.dart';
import 'package:flutter/services.dart';

/// [VoiceInput] backed by the Android host (`VoiceInputChannel.kt`).
///
/// Platforms without the channel (iOS for now) report voice typing as
/// unavailable, so the microphone button is not shown.
final class PlatformVoiceInput implements VoiceInput {
  /// Creates the adapter.
  new({
    this._methods = const MethodChannel('app.emberwit/voice'),
    this._events = const EventChannel('app.emberwit/voice/events'),
  });

  final MethodChannel _methods;
  final EventChannel _events;

  /// The native recognizer's loudness in dB, roughly -2 (silence) to 10.
  static const double _quiet = -2;
  static const double _loud = 10;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  late final Stream<VoiceEvent> events = _events
      .receiveBroadcastStream()
      .map(_event)
      .where((e) => e != null)
      .cast<VoiceEvent>();

  static VoiceEvent? _event(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['type']) {
      'ready' => const VoiceReady(),
      'level' => VoiceLevel(
        ((((raw['value'] as num?) ?? _quiet) - _quiet) / (_loud - _quiet))
            .clamp(0, 1)
            .toDouble(),
      ),
      'partial' => VoiceText(raw['text'] as String? ?? '', isFinal: false),
      'final' => VoiceText(raw['text'] as String? ?? '', isFinal: true),
      'error' => VoiceFailed(VoiceProblem.fromCode(raw['code'] as String?)),
      _ => null,
    };
  }

  @override
  Future<VoiceProblem?> start(VoiceLanguage language) async {
    try {
      await _methods.invokeMethod<String>('start', {'tags': language.tags});
      return null;
    } on MissingPluginException {
      return VoiceProblem.unavailable;
    } on PlatformException catch (e) {
      return VoiceProblem.fromCode(e.code);
    }
  }

  @override
  Future<void> stop() => _call('stop');

  @override
  Future<void> cancel() => _call('cancel');

  @override
  Future<bool> install(VoiceLanguage language) async {
    try {
      return await _methods.invokeMethod<bool>('install', {
            'tags': language.tags,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _call(String method) async {
    try {
      await _methods.invokeMethod<void>(method);
    } on MissingPluginException {
      // No recognizer on this platform: nothing to stop.
    } on PlatformException {
      // Already stopped.
    }
  }
}

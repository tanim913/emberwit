import 'package:emberwit/features/chat/domain/device_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// [DeviceActions] backed by the Android host (`DeviceActionsChannel.kt`).
/// Other platforms run no actions; their messages go to the model.
final class PlatformDeviceActions implements DeviceActions {
  /// Creates the adapter. [supported] defaults to "running on Android".
  new({
    this._channel = const MethodChannel('app.emberwit/device_actions'),
    bool? supported,
  }) : supported = supported ?? defaultTargetPlatform == TargetPlatform.android;

  final MethodChannel _channel;

  @override
  final bool supported;

  @override
  Future<ActionOutcome> setAlarm({int? hour, int minute = 0}) =>
      _outcome('setAlarm', {'hour': ?hour, 'minute': minute});

  @override
  Future<ActionOutcome> setTimer(Duration length) =>
      _outcome('setTimer', {'seconds': length.inSeconds});

  @override
  Future<(ActionOutcome, bool)> setTorch({bool? on}) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'setTorch',
        {'on': on},
      );
      return (
        _parse(result?['outcome'] as String?),
        result?['on'] as bool? ?? false,
      );
    } on PlatformException {
      return (ActionOutcome.failed, false);
    } on MissingPluginException {
      return (ActionOutcome.unavailable, false);
    }
  }

  @override
  Future<List<InstalledApp>> installedApps() async {
    try {
      final apps = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'installedApps',
      );
      return [
        for (final app in apps ?? const <Map<Object?, Object?>>[])
          if (app['label'] case final String label)
            if (app['package'] case final String packageName)
              InstalledApp(label: label, packageName: packageName),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<ActionOutcome> openApp(InstalledApp app) =>
      _outcome('openApp', {'package': app.packageName});

  Future<ActionOutcome> _outcome(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return _parse(await _channel.invokeMethod<String>(method, arguments));
    } on PlatformException {
      return ActionOutcome.failed;
    } on MissingPluginException {
      return ActionOutcome.unavailable;
    }
  }

  static ActionOutcome _parse(String? outcome) => switch (outcome) {
    'done' => ActionOutcome.done,
    'unavailable' => ActionOutcome.unavailable,
    'busy' => ActionOutcome.busy,
    _ => ActionOutcome.failed,
  };
}

import 'package:emberwit/features/chat/domain/device_actions.dart';

/// Records phone actions instead of running them.
final class FakeDeviceActions implements DeviceActions {
  /// Creates the fake with [apps] installed.
  new({this.apps = const [], this.supported = true});

  @override
  final bool supported;

  /// Installed launcher apps.
  List<InstalledApp> apps;

  /// Outcome of every action.
  ActionOutcome outcome = ActionOutcome.done;

  /// Flashlight state.
  bool torch = false;

  /// What was asked, in order, for example `alarm 7:0` or `open youtube`.
  final List<String> log = [];

  @override
  Future<ActionOutcome> setAlarm({int? hour, int minute = 0}) async {
    log.add('alarm $hour:$minute');
    return outcome;
  }

  @override
  Future<ActionOutcome> setTimer(Duration length) async {
    log.add('timer ${length.inSeconds}');
    return outcome;
  }

  @override
  Future<(ActionOutcome, bool)> setTorch({bool? on}) async {
    log.add('torch $on');
    if (outcome == ActionOutcome.done) torch = on ?? !torch;
    return (outcome, torch);
  }

  @override
  Future<List<InstalledApp>> installedApps() async => apps;

  @override
  Future<ActionOutcome> openApp(InstalledApp app) async {
    log.add('open ${app.packageName}');
    return outcome;
  }
}

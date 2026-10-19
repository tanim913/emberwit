import 'dart:async';

import 'package:emberwit/app/router/app_router.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/features/chat/presentation/chat_controllers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Handles what the app was opened for by the Android host: the home screen
/// voice widget opens a new chat that starts listening.
///
/// Asks the host once at start (cold start from the widget) and listens for
/// later taps while the app runs.
class LaunchActions extends ConsumerStatefulWidget {
  /// Wraps [child].
  const new({
    required this.child,
    this.channel = const MethodChannel('app.emberwit/launch'),
    super.key,
  });

  /// The app.
  final Widget child;

  /// Channel to the host. Replaced in tests.
  final MethodChannel channel;

  @override
  ConsumerState<LaunchActions> createState() => _LaunchActionsState();
}

class _LaunchActionsState extends ConsumerState<LaunchActions> {
  @override
  void initState() {
    super.initState();
    widget.channel.setMethodCallHandler((call) async {
      if (call.method == 'action') await _run(call.arguments as String?);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_take()));
  }

  @override
  void dispose() {
    widget.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _take() async {
    try {
      await _run(await widget.channel.invokeMethod<String>('takeAction'));
    } on MissingPluginException {
      // No host channel (iOS, tests): nothing to do.
    } on PlatformException {
      // Ignore: the app opens normally.
    }
  }

  Future<void> _run(String? action) async {
    if (action != 'voice' || !mounted) return;
    // Onboarding comes first; the router shows it.
    if (!ref.read(onboardingCompletedProvider)) return;
    final id = await reuseEmptyConversation(
      ref,
      title: context.l10n.chatUntitled,
    );
    if (!mounted) return;
    ref.read(appRouterProvider()).go(AppRoutes.chatWithVoice(id));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

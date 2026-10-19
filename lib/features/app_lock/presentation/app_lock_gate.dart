import 'dart:async';

import 'package:emberwit/core/constants/app_constants.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/core/widgets/action_colors.dart';
import 'package:emberwit/features/app_lock/data/app_lock_providers.dart';
import 'package:emberwit/features/app_lock/data/secure_window.dart';
import 'package:emberwit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Puts the lock screen over [child] when the app lock requires it.
///
/// While covered or locked, [child] stays mounted (so navigation and drafts
/// survive) but is hidden from screen readers and stops animating.
class AppLockGate extends ConsumerStatefulWidget {
  /// Creates the gate.
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appLockControllerProvider.notifier);
    switch (state) {
      // Covering on `inactive` (before the app is hidden) lets the cover
      // draw while frames still run, so the app switcher shows it rather
      // than the conversation.
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        // The system prompt itself makes the app inactive; that must not
        // restart the lock.
        if (!controller.authenticating) controller.onBackground();
      case AppLifecycleState.resumed:
        controller.onForeground();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(appLockControllerProvider);
    final hidden = phase != LockPhase.unlocked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: hidden,
          child: TickerMode(enabled: !hidden, child: widget.child),
        ),
        if (hidden) LockScreen(locked: phase == LockPhase.locked),
      ],
    );
  }
}

/// Full screen cover with an unlock button. Screenshots and the app
/// switcher thumbnail are blocked while it shows (Android).
class LockScreen extends ConsumerStatefulWidget {
  /// Creates the lock screen. When [locked] is false it only covers.
  const new({required this.locked, super.key});

  /// Whether authentication is needed.
  final bool locked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  AuthenticationResult? _result;
  bool _prompted = false;
  // Kept for dispose, where providers can no longer be read.
  late final SecureWindow _window = ref.read(secureWindowProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_window.setSecure(secure: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ask right away the first time the lock shows.
    if (widget.locked && !_prompted) {
      _prompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void didUpdateWidget(LockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locked && !oldWidget.locked && !_prompted) {
      _prompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void dispose() {
    unawaited(_window.setSecure(secure: false));
    super.dispose();
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    final result = await ref
        .read(appLockControllerProvider.notifier)
        .unlock(context.l10n.lockReason(AppConstants.appName));
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = switch (_result) {
      AuthenticationResult.unavailable => l10n.lockUnavailable,
      AuthenticationResult.lockedOut => l10n.lockLockedOut,
      AuthenticationResult.failed => l10n.lockFailed,
      AuthenticationResult.success || null => null,
    };
    // Its own Material: the gate sits above the navigator, outside any
    // Scaffold.
    return Material(
      key: const Key('lock-screen'),
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.action,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 36,
                      color: scheme.onAction,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.lockTitle(AppConstants.appName),
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if (widget.locked) ...[
                  const SizedBox(height: 8),
                  Text(
                    message ?? l10n.lockBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: message == null
                          ? scheme.onSurfaceVariant
                          : scheme.error,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('unlock'),
                    onPressed: _unlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: Text(l10n.lockUnlock),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

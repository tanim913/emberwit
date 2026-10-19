import 'dart:async';

import 'package:emberwit/core/constants/app_constants.dart';
import 'package:emberwit/core/l10n/failure_messages.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/l10n/recommendation_messages.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:emberwit/core/widgets/action_colors.dart';
import 'package:emberwit/core/widgets/error_banner.dart';
import 'package:emberwit/features/onboarding/presentation/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// First run introduction in four steps: what the app is, how it works,
/// what this device can do, and a first model to download.
class OnboardingPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  /// Number of steps.
  static const int pageCount = 4;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish({bool browseModels = false}) async {
    await ref.read(onboardingControllerProvider.notifier).finish();
    if (!mounted) return;
    context.go(AppRoutes.chats);
    if (browseModels) unawaited(context.push(AppRoutes.models));
  }

  void _next() => _pages.nextPage(
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final last = _index == OnboardingPage.pageCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: last
                    ? const SizedBox(height: 48)
                    : TextButton(
                        key: const Key('onboarding-skip'),
                        onPressed: _finish,
                        child: Text(l10n.onboardingSkip),
                      ),
              ),
            ),
            Expanded(
              child: PageView(
                key: const Key('onboarding-pages'),
                controller: _pages,
                onPageChanged: (index) => setState(() => _index = index),
                children: [
                  const _WelcomeStep(),
                  const _HowItWorksStep(),
                  const _DeviceStep(),
                  _ModelStep(onFinish: _finish),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  Semantics(
                    label: l10n.onboardingProgress(
                      _index + 1,
                      OnboardingPage.pageCount,
                    ),
                    child: ExcludeSemantics(
                      child: _Dots(
                        count: OnboardingPage.pageCount,
                        index: _index,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!last)
                    FilledButton(
                      key: const Key('onboarding-next'),
                      onPressed: _next,
                      child: Text(l10n.onboardingNext),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const new({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsetsDirectional.only(end: 6),
            width: i == index ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? scheme.action : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// Shared layout of a step: icon, title, body, then optional content.
class _Step extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.action,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, size: 40, color: scheme.onAction),
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(body, style: theme.textTheme.bodyLarge),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _PromiseCard extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Step(
      icon: Icons.local_fire_department_rounded,
      title: l10n.welcomeTitle(AppConstants.appName),
      body: l10n.welcomeBody(AppConstants.appName),
      children: [
        const SizedBox(height: 12),
        _PromiseCard(icon: Icons.lock_outline_rounded, text: l10n.privacyLine),
        _PromiseCard(icon: Icons.wifi_off_rounded, text: l10n.offlineLine),
      ],
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Step(
      icon: Icons.download_for_offline_rounded,
      title: l10n.onboardingHowTitle,
      body: l10n.onboardingHowBody,
      children: [
        const SizedBox(height: 12),
        _PromiseCard(
          icon: Icons.download_rounded,
          text: l10n.onboardingHowDownload,
        ),
        _PromiseCard(icon: Icons.memory_rounded, text: l10n.onboardingHowRuns),
        _PromiseCard(
          icon: Icons.translate_rounded,
          text: l10n.onboardingHowLanguages,
        ),
      ],
    );
  }
}

class _DeviceStep extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(onboardingControllerProvider);
    final profile = state.profile;
    final tier = state.tier;
    return _Step(
      icon: Icons.speed_rounded,
      title: l10n.onboardingDeviceTitle,
      body: l10n.onboardingDeviceBody,
      children: [
        const SizedBox(height: 16),
        if (state.profiling)
          const Center(child: CircularProgressIndicator())
        else if (profile == null || tier == null)
          Text(l10n.failureDeviceProfiling)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceTierName(l10n, tier),
                    key: const Key('onboarding-tier'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(deviceTierDescription(l10n, tier)),
                  const SizedBox(height: 8),
                  Text(
                    l10n.onboardingDeviceMemory(
                      gigabytes(profile.totalRamBytes),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingDeviceSpeedTest,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ModelStep extends ConsumerWidget {
  const new({required this.onFinish});

  final Future<void> Function({bool browseModels}) onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(onboardingControllerProvider);
    final entry = state.suggested;
    final recommendation = state.recommendation;
    return _Step(
      icon: Icons.smart_toy_outlined,
      title: l10n.onboardingModelTitle,
      body: state.hasModel
          ? l10n.onboardingModelReady
          : l10n.onboardingModelBody,
      children: [
        const SizedBox(height: 16),
        if (state.profiling)
          const Center(child: CircularProgressIndicator())
        else if (entry != null && recommendation != null && !state.hasModel)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    key: const Key('onboarding-suggested'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${recommendationLabelText(l10n, recommendation.label)}'
                    ' · ${l10n.modelsSize(gigabytes(entry.fileSizeBytes))}',
                  ),
                  const SizedBox(height: 12),
                  if (state.downloadStarted)
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l10n.onboardingDownloadStarted)),
                      ],
                    )
                  else
                    FilledButton.icon(
                      key: const Key('onboarding-download'),
                      onPressed: () => ref
                          .read(onboardingControllerProvider.notifier)
                          .downloadSuggested(),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(l10n.modelsDownload),
                    ),
                ],
              ),
            ),
          )
        else if (!state.hasModel)
          Text(l10n.onboardingNoSuggestion),
        if (state.failure != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(describeFailure(l10n, state.failure!)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('onboarding-finish'),
          onPressed: onFinish,
          child: Text(l10n.onboardingStart),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('onboarding-browse'),
          onPressed: () => onFinish(browseModels: true),
          child: Text(l10n.onboardingBrowse),
        ),
      ],
    );
  }
}

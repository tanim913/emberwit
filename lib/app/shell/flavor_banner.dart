import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Marks non production builds with a corner banner so screenshots and bug
/// reports can never be confused with store builds.
class FlavorBanner extends ConsumerWidget {
  /// Wraps [child] with a banner when the flavor asks for one.
  const new({required this.child, super.key});

  /// The app content.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(flavorConfigProvider);
    if (!config.showBanner) return child;
    final l10n = context.l10n;
    final label = switch (config.flavor) {
      AppFlavor.dev => l10n.flavorBannerDev,
      AppFlavor.staging => l10n.flavorBannerStaging,
      AppFlavor.prod => '',
    };
    return Banner(
      message: label,
      location: BannerLocation.topEnd,
      color: Theme.of(context).colorScheme.tertiary,
      textStyle: TextStyle(
        color: Theme.of(context).colorScheme.onTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
      child: child,
    );
  }
}

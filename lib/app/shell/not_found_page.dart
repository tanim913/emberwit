import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown when navigation targets a route that does not exist.
class NotFoundPage extends StatelessWidget {
  /// Creates the not found page.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notFoundTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_off_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.notFoundBody,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: Text(l10n.goHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

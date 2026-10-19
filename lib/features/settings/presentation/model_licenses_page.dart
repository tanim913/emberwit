import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Licenses of the catalog models and of models on this phone.
typedef ModelLicenses = ({
  List<CatalogEntry> catalog,
  List<InstalledModel> installed,
});

final FutureProvider<ModelLicenses> _modelLicensesProvider =
    FutureProvider.autoDispose<ModelLicenses>((ref) async {
      final library = ref.watch(modelLibraryProvider);
      await library.initialize();
      final snapshot = await ref.watch(catalogRepositoryProvider).current();
      return (
        catalog: snapshot.catalog.models,
        installed: library.state.installed,
      );
    });

/// Lists every model's license: catalog models (marked when installed) and
/// imported models, whose license the app cannot know.
class ModelLicensesPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final data = ref.watch(_modelLicensesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsModelLicenses)),
      body: SafeArea(
        child: switch (data) {
          AsyncData(:final value) => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(l10n.modelLicensesIntro),
              ),
              for (final entry in value.catalog)
                _LicenseTile(
                  id: entry.id,
                  name: entry.displayName,
                  license: entry.license,
                  installed: value.installed.any((m) => m.id == entry.id),
                ),
              for (final model in value.installed)
                if (model.isImported)
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: Text(model.displayName),
                    subtitle: Text(l10n.modelLicensesImported),
                  ),
            ],
          ),
          AsyncError() => Center(child: Text(l10n.failureUnexpected)),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _LicenseTile extends StatelessWidget {
  const new({
    required this.id,
    required this.name,
    required this.license,
    required this.installed,
  });

  final String id;
  final String name;
  final CatalogLicense license;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListTile(
      key: Key('license-$id'),
      leading: Icon(
        installed ? Icons.check_circle_rounded : Icons.article_outlined,
        color: installed ? theme.colorScheme.primary : null,
      ),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.modelsLicense(license.name)),
          if (license.requiresAgreement)
            Text(
              l10n.modelLicensesRestricted,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          SelectableText(
            license.url,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: l10n.modelLicensesCopyLink,
        icon: const Icon(Icons.link_rounded),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: license.url));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(l10n.chatCopied)));
        },
      ),
    );
  }
}

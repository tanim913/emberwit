import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/l10n/failure_messages.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/l10n/recommendation_messages.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/download_preferences.dart';
import 'package:emberwit/core/recommendation/model_recommendation.dart';
import 'package:emberwit/core/widgets/error_banner.dart';
import 'package:emberwit/features/model_manager/presentation/models_controller.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists models on the phone, downloads in progress and catalog models with
/// a recommendation for this device.
class ModelsPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(modelsControllerProvider);
    final controller = ref.read(modelsControllerProvider.notifier);
    final downloads = state.library.downloads.values.toList();
    final available = state.available;
    final catalogProblem = state.catalogFailure;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.modelsTitle),
        actions: [
          IconButton(
            key: const Key('import-model'),
            tooltip: l10n.modelsImport,
            onPressed: controller.importFromDevice,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: l10n.modelsRefreshCatalog,
            onPressed: state.refreshingCatalog
                ? null
                : controller.refreshCatalog,
            icon: state.refreshingCatalog
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _StorageHeader(state: state),
            if (state.catalog?.source != null &&
                state.catalog!.source != CatalogSource.remote)
              _Notice(
                state.catalog!.source == CatalogSource.bundled
                    ? l10n.modelsCatalogBundled
                    : l10n.modelsCatalogCached,
              ),
            if (catalogProblem != null &&
                catalogProblem is CatalogFailure &&
                catalogProblem.reason != CatalogFailureReason.network) ...[
              const SizedBox(height: 12),
              ErrorBanner(describeFailure(l10n, catalogProblem)),
            ],
            if (state.actionFailure != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(describeFailure(l10n, state.actionFailure!)),
            ],
            if (state.library.installed.isNotEmpty) ...[
              _SectionTitle(l10n.modelsSectionInstalled),
              for (final details in state.installedDetails)
                _InstalledTile(
                  details: details,
                  onDelete: () =>
                      _confirmDelete(context, controller, details.model),
                ),
            ],
            if (downloads.isNotEmpty) ...[
              _SectionTitle(l10n.modelsSectionDownloads),
              for (final download in downloads)
                _DownloadTile(
                  download: download,
                  name:
                      state.entryFor(download.modelId)?.displayName ??
                      download.modelId,
                  controller: controller,
                ),
            ],
            if (available.isNotEmpty) ...[
              _SectionTitle(l10n.modelsSectionAvailable),
              for (final model in available)
                _AvailableTile(
                  model: model,
                  onDownload: () =>
                      _startDownload(context, controller, model.entry),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startDownload(
    BuildContext context,
    ModelsController controller,
    CatalogEntry entry,
  ) async {
    if (entry.license.requiresAgreement) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => _LicenseDialog(entry: entry),
      );
      if (accepted != true) return;
    }
    await controller.download(entry);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ModelsController controller,
    InstalledModel model,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.modelsDeleteTitle(model.displayName)),
        content: Text(l10n.modelsDeleteBody(gigabytes(model.sizeBytes))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.modelsDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.delete(model.id);
  }
}

class _StorageHeader extends ConsumerWidget {
  const new({required this.state});

  final ModelsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final wifiOnly = ref.watch(wifiOnlyDownloadsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.modelsStorageSummary(
            state.library.installed.length,
            gigabytes(state.library.totalBytes),
            gigabytes(state.profile?.freeStorageBytes ?? 0),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SwitchListTile(
          key: const Key('wifi-only'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.modelsWifiOnly),
          subtitle: Text(l10n.modelsWifiOnlyHint),
          value: wifiOnly,
          onChanged: (value) =>
              ref.read(wifiOnlyDownloadsProvider.notifier).set(wifiOnly: value),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Notice extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstalledTile extends StatelessWidget {
  const new({required this.details, required this.onDelete});

  final InstalledDetails details;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final model = details.model;
    final entry = details.entry;
    final recommendation = details.recommendation;
    final reason = recommendation?.reasons.firstOrNull;
    final verified = model.verification == ModelVerification.verified;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      key: Key('installed-${model.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (recommendation != null)
                        _LabelChip(recommendation.label),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        verified
                            ? Icons.verified_rounded
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: verified
                            ? theme.colorScheme.primary
                            : theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            if (verified)
                              l10n.modelsVerified
                            else
                              l10n.modelsUnverified,
                            l10n.modelsSize(gigabytes(model.sizeBytes)),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (entry == null) ...[
                    const SizedBox(height: 8),
                    Text(l10n.modelsImportedDetails, style: muted),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        l10n.modelsParameters(entry.parameterCount),
                        l10n.modelsBengaliQuality(
                          languageQualityText(l10n, entry.qualityFor('bn')),
                        ),
                      ].join(' · '),
                      style: muted,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.descriptionFor(
                        Localizations.localeOf(context).languageCode,
                      ),
                    ),
                    if (reason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        describeRecommendationReason(l10n, reason),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(l10n.modelsLicense(entry.license.name), style: muted),
                  ],
                ],
              ),
            ),
            IconButton(
              key: Key('delete-${model.id}'),
              tooltip: l10n.modelsDelete,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const new({
    required this.download,
    required this.name,
    required this.controller,
  });

  final DownloadState download;
  final String name;
  final ModelsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final id = download.modelId;
    final failed = download.phase == DownloadPhase.failed;
    final determinate =
        download.phase == DownloadPhase.downloading ||
        download.phase == DownloadPhase.paused;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
                if (download.phase == DownloadPhase.paused)
                  IconButton(
                    key: Key('resume-$id'),
                    tooltip: l10n.downloadResume,
                    onPressed: () => controller.resume(id),
                    icon: const Icon(Icons.play_arrow_rounded),
                  )
                else if (!failed && download.phase != DownloadPhase.verifying)
                  IconButton(
                    key: Key('pause-$id'),
                    tooltip: l10n.downloadPause,
                    onPressed: () => controller.pause(id),
                    icon: const Icon(Icons.pause_rounded),
                  ),
                if (download.phase != DownloadPhase.verifying)
                  IconButton(
                    key: Key('cancel-$id'),
                    tooltip: failed
                        ? l10n.downloadDismiss
                        : l10n.downloadCancel,
                    onPressed: () => controller.cancel(id),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            if (failed) ...[
              ErrorBanner(
                describeFailure(
                  l10n,
                  download.failure ?? const UnexpectedFailure(),
                ),
              ),
              TextButton(
                onPressed: () => controller.retry(id),
                child: Text(l10n.downloadRetry),
              ),
            ] else ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: determinate ? download.progress : null,
              ),
              const SizedBox(height: 6),
              Text(
                downloadStatusText(l10n, download),
                key: Key('download-status-$id'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Localized one line status of [download], for example
/// `45% · 3.2 MB/s · 4 min left`.
String downloadStatusText(AppLocalizations l10n, DownloadState download) {
  switch (download.phase) {
    case DownloadPhase.queued:
      return l10n.downloadQueued;
    case DownloadPhase.waitingForWifi:
      return l10n.downloadWaitingForWifi;
    case DownloadPhase.verifying:
      return l10n.downloadVerifying;
    case DownloadPhase.failed:
      return '';
    case DownloadPhase.paused:
      return '${l10n.downloadPaused} · '
          '${l10n.downloadProgress((download.progress * 100).floor())}';
    case DownloadPhase.downloading:
      final parts = [l10n.downloadProgress((download.progress * 100).floor())];
      final speed = download.bytesPerSecond;
      if (speed != null) parts.add(l10n.downloadSpeed(speed / 1e6));
      final remaining = download.remaining;
      if (remaining != null) parts.add(remainingText(l10n, remaining));
      return parts.join(' · ');
  }
}

/// Localized estimate of the time left.
String remainingText(AppLocalizations l10n, Duration remaining) {
  if (remaining.inMinutes < 1) return l10n.downloadRemainingSoon;
  if (remaining.inHours < 1) {
    return l10n.downloadRemainingMinutes(remaining.inMinutes);
  }
  return l10n.downloadRemainingHours(
    remaining.inHours,
    remaining.inMinutes % 60,
  );
}

/// Localized name of a language quality level.
String languageQualityText(AppLocalizations l10n, LanguageQuality quality) =>
    switch (quality) {
      LanguageQuality.good => l10n.languageQualityGood,
      LanguageQuality.basic => l10n.languageQualityBasic,
      LanguageQuality.limited => l10n.languageQualityLimited,
      LanguageQuality.unknown => l10n.languageQualityUnknown,
    };

class _AvailableTile extends StatelessWidget {
  const new({required this.model, required this.onDownload});

  final AvailableModel model;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final entry = model.entry;
    final recommendation = model.recommendation;
    final label = recommendation?.label;
    final languageCode = Localizations.localeOf(context).languageCode;
    final reason = recommendation?.reasons.firstOrNull;
    final button = Text(l10n.modelsDownload);
    final downloadKey = Key('download-${entry.id}');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (label != null) _LabelChip(label),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                l10n.modelsSize(gigabytes(entry.fileSizeBytes)),
                l10n.modelsParameters(entry.parameterCount),
                l10n.modelsBengaliQuality(
                  languageQualityText(l10n, entry.qualityFor('bn')),
                ),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(entry.descriptionFor(languageCode)),
            if (reason != null) ...[
              const SizedBox(height: 8),
              Text(
                describeRecommendationReason(l10n, reason),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              l10n.modelsLicense(entry.license.name),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            switch (label) {
              RecommendationLabel.notSupported => FilledButton(
                key: downloadKey,
                onPressed: null,
                child: button,
              ),
              RecommendationLabel.runsSlowly => OutlinedButton(
                key: downloadKey,
                onPressed: onDownload,
                child: button,
              ),
              RecommendationLabel.recommended || null => FilledButton(
                key: downloadKey,
                onPressed: onDownload,
                child: button,
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const new(this.label);

  final RecommendationLabel label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (label) {
      RecommendationLabel.recommended => (
        Icons.check_circle_rounded,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      RecommendationLabel.runsSlowly => (
        Icons.schedule_rounded,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      RecommendationLabel.notSupported => (
        Icons.block_rounded,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
            Text(
              recommendationLabelText(context.l10n, label),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _LicenseDialog extends StatelessWidget {
  const new({required this.entry});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.licenseDialogTitle(entry.displayName)),
      content: SelectableText(
        l10n.licenseDialogBody(entry.license.name, entry.license.url),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('accept-license'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.licenseDialogAccept),
        ),
      ],
    );
  }
}

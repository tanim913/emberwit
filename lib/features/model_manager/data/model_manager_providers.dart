import 'dart:ui';

import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/download_preferences.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/features/model_manager/data/model_downloader.dart';
import 'package:emberwit/features/model_manager/data/model_file_picker.dart';
import 'package:emberwit/features/model_manager/data/model_library_impl.dart';
import 'package:emberwit/features/model_manager/data/model_registry.dart';
import 'package:emberwit/features/model_manager/data/model_storage.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'model_manager_providers.g.dart';

/// The model manager's [ModelLibrary]; exposed through the shared
/// `modelLibraryProvider` by `featureBindings()`.
@Riverpod(keepAlive: true)
ModelLibrary modelManagerLibrary(Ref ref) {
  final storage = ModelStorage(ref.watch(appSupportDirectoryProvider));
  final l10n = lookupAppLocalizations(
    PlatformDispatcher.instance.locale.languageCode == 'bn'
        ? const Locale('bn')
        : const Locale('en'),
  );
  final library = ModelLibraryImpl(
    storage: storage,
    registry: ModelRegistry(
      registryFile: storage.registryFile,
      pendingFile: storage.pendingFile,
    ),
    downloader: BackgroundModelDownloader(
      notificationTexts: DownloadNotificationTexts(
        // The downloader fills in {progress}.
        running: l10n.downloadNotificationRunning('{progress}'),
        complete: l10n.downloadNotificationComplete,
        error: l10n.downloadNotificationError,
        paused: l10n.downloadNotificationPaused,
      ),
    ),
    picker: const SystemModelFilePicker(),
    deviceProfile: ref.watch(deviceProfileRepositoryProvider),
    engine: ref.watch(inferenceEngineProvider),
    wifiOnly: () => ref.read(wifiOnlyDownloadsProvider),
    clock: ref.watch(clockProvider),
    logger: ref.watch(appLoggerProvider),
  );
  ref.onDispose(library.dispose);
  return library;
}

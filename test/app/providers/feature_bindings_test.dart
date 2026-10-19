import 'dart:io';

import 'package:emberwit/app/providers/feature_bindings.dart';
import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/features/app_lock/data/local_auth_authenticator.dart';
import 'package:emberwit/features/chat/data/chat_archive_impl.dart';
import 'package:emberwit/features/device_profiler/data/device_conditions_source_impl.dart';
import 'package:emberwit/features/device_profiler/data/device_profile_repository_impl.dart';
import 'package:emberwit/features/model_catalog/data/catalog_repository_impl.dart';
import 'package:emberwit/features/model_manager/data/model_library_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_inference_engine.dart';
import '../../helpers/preferences.dart';

void main() {
  test('shared contracts fail loudly without the composition root', () {
    final container = ProviderContainer.test();
    expect(
      () => container.read(deviceProfileRepositoryProvider),
      throwsA(anything),
    );
    expect(
      () => container.read(appSupportDirectoryProvider),
      throwsA(anything),
    );
  });

  test('featureBindings wire every feature implementation', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final container = ProviderContainer.test(
      overrides: [
        flavorConfigProvider.overrideWithValue(
          FlavorConfig.forFlavor(AppFlavor.dev),
        ),
        appLoggerProvider.overrideWithValue(const SilentAppLogger()),
        appSupportDirectoryProvider.overrideWithValue(Directory.systemTemp),
        sharedPreferencesProvider.overrideWithValue(
          await inMemoryPreferences(),
        ),
        inferenceEngineProvider.overrideWithValue(FakeInferenceEngine()),
        ...featureBindings(),
      ],
    );
    expect(
      container.read(deviceProfileRepositoryProvider),
      isA<DeviceProfileRepositoryImpl>(),
    );
    expect(
      container.read(catalogRepositoryProvider),
      isA<CatalogRepositoryImpl>(),
    );
    expect(container.read(modelLibraryProvider), isA<ModelLibraryImpl>());
    expect(
      container.read(deviceConditionsSourceProvider),
      isA<SnapshotDeviceConditionsSource>(),
    );
    expect(container.read(chatArchiveProvider), isA<ChatArchiveImpl>());
    expect(
      container.read(authenticatorProvider),
      isA<LocalAuthAuthenticator>(),
    );
    // The bundled catalog loads through the real wiring.
    final snapshot = await container.read(catalogRepositoryProvider).current();
    expect(snapshot.catalog.models, hasLength(8));
  });
}

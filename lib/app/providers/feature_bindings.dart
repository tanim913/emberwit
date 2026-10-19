import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/app_lock/data/app_lock_providers.dart';
import 'package:emberwit/features/chat/data/chat_providers.dart';
import 'package:emberwit/features/device_profiler/data/device_profiler_providers.dart';
import 'package:emberwit/features/model_catalog/data/model_catalog_providers.dart';
import 'package:emberwit/features/model_manager/data/model_manager_providers.dart';
import 'package:flutter_riverpod/misc.dart';

/// Connects shared contracts in `core` to the features that implement them.
///
/// Features never import each other. When one feature needs another's
/// capability, the contract lives in `core` as an interface plus a provider
/// that throws unless overridden, and this composition root supplies the
/// implementation.
List<Override> featureBindings() => [
  deviceProfileRepositoryProvider.overrideWith(
    (ref) => ref.watch(deviceProfilerRepositoryProvider),
  ),
  catalogRepositoryProvider.overrideWith(
    (ref) => ref.watch(modelCatalogRepositoryProvider),
  ),
  modelLibraryProvider.overrideWith(
    (ref) => ref.watch(modelManagerLibraryProvider),
  ),
  deviceConditionsSourceProvider.overrideWith(
    (ref) => ref.watch(deviceProfilerConditionsProvider),
  ),
  chatArchiveProvider.overrideWith((ref) => ref.watch(chatArchiveImplProvider)),
  authenticatorProvider.overrideWith(
    (ref) => ref.watch(localAuthenticatorProvider),
  ),
];

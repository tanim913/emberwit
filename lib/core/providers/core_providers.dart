import 'dart:io';

import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'core_providers.g.dart';

/// Configuration of the running build flavor.
///
/// Has no default: `bootstrap` overrides it with the resolved flavor, and
/// tests override it explicitly. Reading it without an override is a
/// programming error and fails loudly.
@Riverpod(keepAlive: true)
FlavorConfig flavorConfig(Ref ref) => throw StateError(
  'flavorConfigProvider must be overridden in bootstrap or in the test.',
);

/// Application logger. Silent in release builds.
@Riverpod(keepAlive: true)
AppLogger appLogger(Ref ref) => createDefaultLogger();

/// Source of the current time.
@Riverpod(keepAlive: true)
Clock clock(Ref ref) => const SystemClock();

/// The app's private support directory (Android `files/`, iOS
/// `Library/Application Support`). Resolved once in `bootstrap` and
/// overridden, so every consumer can read it synchronously.
@Riverpod(keepAlive: true)
Directory appSupportDirectory(Ref ref) => throw StateError(
  'appSupportDirectoryProvider must be overridden in bootstrap or in the test.',
);

/// Key-value preferences, loaded once in `bootstrap` and overridden.
@Riverpod(keepAlive: true)
SharedPreferencesWithCache sharedPreferences(Ref ref) => throw StateError(
  'sharedPreferencesProvider must be overridden in bootstrap or in the test.',
);

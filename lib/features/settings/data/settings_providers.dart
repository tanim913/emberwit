import 'package:emberwit/features/settings/data/archive_files.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_providers.g.dart';

/// File dialogs for chat exports. Overridden in tests.
@Riverpod(keepAlive: true)
ArchiveFiles archiveFiles(Ref ref) => const SystemArchiveFiles();

/// App version shown in About, for example `0.1.0 (1)`.
@riverpod
Future<String> appVersion(Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
}

import 'dart:convert';
import 'dart:io';

import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/models/model_library.dart';

/// Persists installed model records and pending downloads as JSON files.
///
/// Writes are atomic (temporary file, then rename) and serialized, so
/// overlapping updates (a download finishing while another starts) never
/// race. Unreadable files are treated as empty: the worst case is
/// re-downloading, never a crash.
final class ModelRegistry {
  /// Creates a registry backed by [registryFile] and [pendingFile].
  new({required this.registryFile, required this.pendingFile});

  /// Installed models.
  final File registryFile;

  /// Downloads in progress: model id to catalog entry and mirror index.
  final File pendingFile;

  /// Installed models.
  Future<List<InstalledModel>> readInstalled() async {
    final json = await _read(registryFile);
    if (json is! List<dynamic>) return [];
    final models = <InstalledModel>[];
    for (final item in json) {
      try {
        models.add(InstalledModel.fromJson(item as Map<String, dynamic>));
      } on Object {
        // Skip one damaged record instead of losing the others.
      }
    }
    return models;
  }

  /// Saves installed models.
  Future<void> writeInstalled(List<InstalledModel> models) =>
      _write(registryFile, [for (final m in models) m.toJson()]);

  /// Pending downloads.
  Future<Map<String, PendingDownload>> readPending() async {
    final json = await _read(pendingFile);
    if (json is! Map<String, dynamic>) return {};
    final pending = <String, PendingDownload>{};
    for (final MapEntry(:key, :value) in json.entries) {
      try {
        pending[key] = PendingDownload.fromJson(value as Map<String, dynamic>);
      } on Object {
        // Skip damaged record.
      }
    }
    return pending;
  }

  /// Saves pending downloads.
  Future<void> writePending(Map<String, PendingDownload> pending) => _write(
    pendingFile,
    {for (final MapEntry(:key, :value) in pending.entries) key: value.toJson()},
  );

  Future<Object?> _read(File file) async {
    try {
      if (!file.existsSync()) return null;
      return jsonDecode(await file.readAsString());
    } on Object {
      return null;
    }
  }

  Future<void> _lastWrite = Future.value();
  int _writeCount = 0;

  Future<void> _write(File file, Object json) {
    final encoded = jsonEncode(json);
    final id = _writeCount++;
    return _lastWrite = _lastWrite.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.$id.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    });
  }
}

/// A download that has started but not finished: what is being downloaded
/// and from which of its URLs.
final class PendingDownload {
  /// Creates a record.
  const new({required this.entry, required this.urlIndex});

  /// Restores a record from JSON.
  factory fromJson(Map<String, dynamic> json) => PendingDownload(
    entry: CatalogEntry.fromJson(json['entry'] as Map<String, dynamic>),
    urlIndex: json['urlIndex'] as int,
  );

  /// The catalog entry, including its trusted SHA-256.
  final CatalogEntry entry;

  /// Index into [CatalogEntry.downloadUrls] currently used.
  final int urlIndex;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'urlIndex': urlIndex,
  };
}

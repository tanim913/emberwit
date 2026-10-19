import 'package:emberwit/core/recommendation/model_spec.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'model_catalog.freezed.dart';
part 'model_catalog.g.dart';

/// Highest catalog schema version this app understands. Newer minor
/// additions (extra fields) are ignored; a higher schema version means an
/// incompatible format and the manifest is rejected.
const int supportedCatalogSchemaVersion = 1;

/// How well a model handles a language.
@JsonEnum(fieldRename: FieldRename.snake)
enum LanguageQuality {
  /// Fluent and reliable.
  good,

  /// Understands and answers, with noticeable mistakes.
  basic,

  /// Not officially supported; often wrong.
  limited,

  /// A value this app version does not know.
  unknown,
}

/// A language a model supports and how well.
@freezed
abstract class CatalogLanguage with _$CatalogLanguage {
  /// Creates a language entry.
  const factory({
    /// ISO 639-1 code, for example `en` or `bn`.
    required String code,

    /// Quality level; unknown values from newer catalogs become
    /// [LanguageQuality.unknown].
    @JsonKey(unknownEnumValue: LanguageQuality.unknown)
    @Default(LanguageQuality.unknown)
    LanguageQuality quality,
  }) = _CatalogLanguage;

  /// Parses JSON.
  factory fromJson(Map<String, dynamic> json) =>
      _$CatalogLanguageFromJson(json);
}

/// License of a model.
@freezed
abstract class CatalogLicense with _$CatalogLicense {
  /// Creates a license entry.
  const factory({
    /// SPDX id or a short id such as `gemma` or `llama3.2`.
    required String id,

    /// Human readable name.
    required String name,

    /// Where to read the full license.
    required String url,

    /// Whether the license has use restrictions the user must accept before
    /// downloading (for example the Gemma terms or the Llama license).
    @Default(false) bool requiresAgreement,
  }) = _CatalogLicense;

  /// Parses JSON.
  factory fromJson(Map<String, dynamic> json) => _$CatalogLicenseFromJson(json);
}

/// One downloadable model.
@freezed
abstract class CatalogEntry with _$CatalogEntry {
  /// Creates an entry.
  const factory({
    /// Stable id, also the installed file name.
    required String id,

    /// Name shown to users.
    required String displayName,

    /// Model family, for example `qwen3`, `gemma3`, `llama3.2`, `phi4`.
    required String family,

    /// Number of parameters.
    required int parameterCount,

    /// Quantization, for example `Q4_K_M`.
    required String quantization,

    /// Exact file size in bytes.
    required int fileSizeBytes,

    /// Lowercase hex SHA-256 of the file.
    required String sha256,

    /// Download URLs for the same file, primary first, then mirrors.
    required List<String> downloadUrls,

    /// License.
    required CatalogLicense license,

    /// Chat template id: `chatml`, `gemma`, `llama3`, `phi4`.
    required String chatTemplate,

    /// Minimum total device RAM, 0 for none.
    @Default(0) int minRamBytes,

    /// Largest context to use by default.
    @Default(4096) int recommendedContextLength,

    /// KV cache per token of context (see `ModelSpec`).
    int? kvCacheBytesPerToken,

    /// Languages and quality.
    @Default(<CatalogLanguage>[]) List<CatalogLanguage> languages,

    /// Description by language code (`en`, `bn`).
    @Default(<String, String>{}) Map<String, String> description,
  }) = _CatalogEntry;

  /// Parses JSON; unknown fields are ignored.
  factory fromJson(Map<String, dynamic> json) => _$CatalogEntryFromJson(json);

  const new _();

  /// Quality for [languageCode], [LanguageQuality.unknown] when not listed.
  LanguageQuality qualityFor(String languageCode) => languages
      .firstWhere(
        (l) => l.code == languageCode,
        orElse: () => CatalogLanguage(code: languageCode),
      )
      .quality;

  /// Description in [languageCode], falling back to English.
  String descriptionFor(String languageCode) =>
      description[languageCode] ?? description['en'] ?? '';

  /// Input for the recommendation engine.
  ModelSpec toSpec({bool isInstalled = false}) => ModelSpec(
    id: id,
    parameterCount: parameterCount,
    fileSizeBytes: fileSizeBytes,
    recommendedContextLength: recommendedContextLength,
    minRamBytes: minRamBytes,
    kvCacheBytesPerToken: this.kvCacheBytesPerToken,
    isInstalled: isInstalled,
  );
}

/// The model catalog manifest (the signed payload).
@freezed
abstract class ModelCatalog with _$ModelCatalog {
  /// Creates a catalog.
  const factory({
    /// Format version; see [supportedCatalogSchemaVersion].
    required int schemaVersion,

    /// Monotonic content version. The app never replaces a catalog with an
    /// older one, which blocks replaying an old, validly signed manifest.
    required int catalogVersion,

    /// When the catalog was generated.
    required DateTime generatedAt,

    /// Models, in display order.
    required List<CatalogEntry> models,
  }) = _ModelCatalog;

  /// Parses JSON; unknown fields are ignored.
  factory fromJson(Map<String, dynamic> json) => _$ModelCatalogFromJson(json);

  const new _();

  /// The entry with [id], or `null`.
  CatalogEntry? entry(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

/// Where the catalog in use came from.
enum CatalogSource {
  /// Downloaded just now.
  remote,

  /// The last valid download, stored on the device.
  cache,

  /// The copy shipped inside the app.
  bundled,
}

/// A verified catalog and its origin.
@immutable
final class CatalogSnapshot {
  /// Creates a snapshot.
  const new({
    required this.catalog,
    required this.source,
    required this.loadedAt,
  });

  /// The catalog.
  final ModelCatalog catalog;

  /// Where it came from.
  final CatalogSource source;

  /// When it was loaded.
  final DateTime loadedAt;
}

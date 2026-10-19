import 'package:file_picker/file_picker.dart';

/// Lets the user choose a model file from device storage.
abstract interface class ModelFilePicker {
  /// Path of the chosen file, or `null` when the user cancels.
  Future<String?> pick();
}

/// [ModelFilePicker] using the system file picker. GGUF has no registered
/// MIME type, so any file can be chosen and the importer validates it.
final class SystemModelFilePicker implements ModelFilePicker {
  /// Creates the picker.
  const new();

  @override
  Future<String?> pick() async {
    final files = await FilePicker.pickFiles();
    return files.isEmpty ? null : files.first.path;
  }
}

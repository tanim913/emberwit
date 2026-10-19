import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Saves and opens chat export files through the system file dialogs, so
/// the user decides where an export goes (device storage, a USB drive, a
/// cloud folder they trust).
abstract interface class ArchiveFiles {
  /// Asks where to save [bytes] as [fileName]. Returns `false` when the user
  /// cancels.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Lets the user pick an export file. Returns `null` when cancelled.
  Future<Uint8List?> open();
}

/// [ArchiveFiles] using file_picker.
final class SystemArchiveFiles implements ArchiveFiles {
  /// Creates the file access.
  const new();

  /// Largest file accepted on import. Exports are text; even years of chats
  /// stay far below this, and a bound keeps a wrong pick from exhausting
  /// memory.
  static const int maxImportBytes = 256 * 1024 * 1024;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
    );
    return uri != null;
  }

  @override
  Future<Uint8List?> open() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return null;
    final file = files.first;
    final length = await file.length();
    if (length != null && length > maxImportBytes) return Uint8List(0);
    return await file.readAsBytes();
  }
}

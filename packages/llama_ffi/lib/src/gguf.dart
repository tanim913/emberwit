import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// The fixed header at the start of every GGUF file.
@immutable
final class GgufHeader {
  /// Creates a header.
  const new({
    required this.version,
    required this.tensorCount,
    required this.metadataCount,
  });

  /// GGUF format version. llama.cpp reads versions 2 and 3.
  final int version;

  /// Number of tensors in the file.
  final int tensorCount;

  /// Number of metadata key/value pairs.
  final int metadataCount;

  /// Whether llama.cpp can read this version.
  bool get isSupportedVersion => version == 2 || version == 3;
}

/// ASCII `GGUF`.
const List<int> _magic = [0x47, 0x47, 0x55, 0x46];

/// Size of the header: magic, version, tensor count, metadata count.
const int _headerSize = 4 + 4 + 8 + 8;

/// Reads the GGUF header of [file], or returns `null` when the file is too
/// short or does not start with the GGUF magic. Reads only 24 bytes.
GgufHeader? readGgufHeader(File file) {
  final RandomAccessFile handle;
  try {
    handle = file.openSync();
  } on FileSystemException {
    return null;
  }
  try {
    final bytes = handle.readSync(_headerSize);
    return parseGgufHeader(bytes);
  } on FileSystemException {
    return null;
  } finally {
    handle.closeSync();
  }
}

/// Parses a GGUF header from its first 24 [bytes] (little endian).
GgufHeader? parseGgufHeader(Uint8List bytes) {
  if (bytes.length < _headerSize) return null;
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  return GgufHeader(
    version: data.getUint32(4, Endian.little),
    tensorCount: data.getUint64(8, Endian.little),
    metadataCount: data.getUint64(16, Endian.little),
  );
}

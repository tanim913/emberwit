import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llama_ffi/src/bindings/llama_bindings.dart';
import 'package:llama_ffi/src/llama_runtime.dart';

/// The loaded llama.cpp native library, one per isolate.
///
/// Opening it also registers the compute backends. On Android and Linux the
/// CPU backend is a separate module picked at runtime for the CPU's features,
/// loaded from the directory that holds `libllama.so`. On Apple platforms the
/// backends (CPU and Metal) are linked into `llama.framework`.
final class LlamaLibrary {
  new _(this.bindings);

  /// Opens the native library and initialises llama.cpp once per isolate.
  ///
  /// [libraryDirectory] overrides where the libraries are looked up. Tests use
  /// it with a host build (see `tool/build_host.sh`). Throws [LlamaException]
  /// with [LlamaErrorCode.libraryUnavailable] when the library is missing,
  /// for example on an unsupported ABI.
  factory open({String? libraryDirectory}) {
    final existing = _instance;
    if (existing != null) return existing;

    final DynamicLibrary dylib;
    try {
      dylib = _openDynamicLibrary(libraryDirectory);
      // DynamicLibrary.open reports a missing library with an ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      throw LlamaException(
        LlamaErrorCode.libraryUnavailable,
        error.message.toString(),
      );
    }
    // Default logging goes to stderr, which is discarded on phones.
    final bindings = LlamaBindings(dylib)..llama_log_set(nullptr, nullptr);
    _registerBackends(bindings, libraryDirectory);
    bindings.llama_backend_init();
    return _instance = LlamaLibrary._(bindings);
  }

  static LlamaLibrary? _instance;

  /// Raw bindings. Prefer `FfiLlamaRuntime`.
  final LlamaBindings bindings;

  static DynamicLibrary _openDynamicLibrary(String? directory) {
    if (directory != null) {
      final name = Platform.isWindows
          ? 'llama.dll'
          : Platform.isMacOS
          ? 'libllama.dylib'
          : 'libllama.so';
      return DynamicLibrary.open('$directory${Platform.pathSeparator}$name');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.open('llama.framework/llama');
    }
    if (Platform.isWindows) return DynamicLibrary.open('llama.dll');
    return DynamicLibrary.open('libllama.so');
  }

  static void _registerBackends(LlamaBindings bindings, String? directory) {
    // Apple builds link their backends statically; they are already there.
    if (bindings.ggml_backend_dev_count() > 0) return;
    final dir = directory ?? _loadedLibraryDirectory();
    if (dir == null) return;
    final path = dir.toNativeUtf8();
    try {
      bindings.ggml_backend_load_all_from_path(path.cast());
    } finally {
      malloc.free(path);
    }
  }

  static String? _loadedLibraryDirectory() {
    if (Platform.isWindows) {
      return File(Platform.resolvedExecutable).parent.path;
    }
    try {
      return backendDirectoryFromMaps(
        File('/proc/self/maps').readAsStringSync(),
      );
    } on FileSystemException {
      return null;
    }
  }
}

/// Finds the directory of the mapped `libllama.so` in the text of
/// `/proc/self/maps`. Returns `null` when it is not mapped from a plain file
/// (for example when loaded straight from an APK).
String? backendDirectoryFromMaps(String maps) {
  for (final line in maps.split('\n')) {
    final index = line.indexOf('/');
    if (index < 0) continue;
    final path = line.substring(index).trim();
    if (!path.endsWith('/libllama.so') && !path.contains('/libllama.so.')) {
      continue;
    }
    if (path.contains('!/')) return null;
    return path.substring(0, path.lastIndexOf('/'));
  }
  return null;
}

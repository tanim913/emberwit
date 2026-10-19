import 'dart:io';

/// Directory of a host build of the native libraries (`tool/build_host.sh`),
/// taken from the `LLAMA_FFI_LIB_DIR` environment variable.
final String? nativeLibDir = Platform.environment['LLAMA_FFI_LIB_DIR'];

/// Path of the tiny test model (`tool/fetch_test_model.sh`).
const String testModelPath = 'test/fixtures/stories260K.gguf';

/// Skip reason for tests that need the native library and test model, or
/// `null` when both are available.
String? get nativeSkipReason {
  if (nativeLibDir == null) {
    return 'LLAMA_FFI_LIB_DIR not set; run tool/build_host.sh';
  }
  if (!File(testModelPath).existsSync()) {
    return 'test model missing; run tool/fetch_test_model.sh';
  }
  return null;
}

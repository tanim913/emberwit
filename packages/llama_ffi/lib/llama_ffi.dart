/// Dart bindings for llama.cpp.
///
/// [LlamaRuntime] is a small synchronous API over llama.cpp: load a GGUF
/// model, tokenize, decode, sample. Every call blocks the calling thread, so
/// use it from a background isolate, never from the UI isolate.
library;

import 'package:llama_ffi/llama_ffi.dart' show LlamaRuntime;
import 'package:llama_ffi/src/llama_runtime.dart' show LlamaRuntime;

export 'src/ffi_llama_runtime.dart' show FfiLlamaRuntime;
export 'src/gguf.dart' show GgufHeader, readGgufHeader;
export 'src/llama_library.dart' show LlamaLibrary, backendDirectoryFromMaps;
export 'src/llama_runtime.dart';

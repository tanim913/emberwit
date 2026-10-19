import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// A cancellation signal shared between the UI isolate and the engine worker.
///
/// The worker spends its time inside blocking native calls and cannot read
/// messages until they return, so cancellation cannot wait for a message. The
/// flag lives in native memory that both isolates can see: the UI isolate
/// sets it, and the worker checks it between tokens, between prompt chunks
/// and in the model load progress callback.
abstract interface class CancelFlag {
  /// Whether cancellation was requested.
  bool get isSet;

  /// Requests cancellation.
  void set();

  /// Clears the request before new work starts.
  void clear();
}

/// [CancelFlag] in native memory, readable from any isolate by [address].
final class NativeCancelFlag implements CancelFlag {
  /// Allocates a cleared flag. Call [free] when done.
  new allocate() : _pointer = calloc<Int32>();

  /// Wraps a flag allocated by another isolate. Never call [free] on it.
  new fromAddress(int address) : _pointer = Pointer<Int32>.fromAddress(address);

  final Pointer<Int32> _pointer;

  /// Address to hand to another isolate.
  int get address => _pointer.address;

  @override
  bool get isSet => _pointer.value != 0;

  @override
  void set() => _pointer.value = 1;

  @override
  void clear() => _pointer.value = 0;

  /// Frees the native memory. Only the allocating side may call this, and
  /// only after the worker has stopped.
  void free() => calloc.free(_pointer);
}

/// In-memory [CancelFlag] for tests and single isolate use.
final class MemoryCancelFlag implements CancelFlag {
  bool _set = false;

  @override
  bool get isSet => _set;

  @override
  void set() => _set = true;

  @override
  void clear() => _set = false;
}

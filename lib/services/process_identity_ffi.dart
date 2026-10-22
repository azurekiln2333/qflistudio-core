import 'dart:ffi';
import 'dart:io';

/// Optional Linux identity handle; signals cannot target a reused numeric PID.
class ProcessIdentityHandle {
  ProcessIdentityHandle._(this._fd, this._bindings);

  final int _fd;
  final _LinuxPidfds _bindings;
  bool _closed = false;

  /// Returns null when this host cannot safely pin and signal the process.
  static ProcessIdentityHandle? tryOpen(int pid) {
    if (!Platform.isLinux || pid <= 0) return null;
    final bindings = _LinuxPidfds.instance;
    if (bindings == null) return null;
    final fd = bindings.open(pid, 0);
    if (fd < 0) return null;
    final handle = ProcessIdentityHandle._(fd, bindings);
    if (!handle.sendSignal(0)) {
      handle.close();
      return null;
    }
    return handle;
  }

  bool sendSignal(int signalNumber) =>
      !_closed && _bindings.signal(_fd, signalNumber, nullptr, 0) == 0;

  void close() {
    if (_closed) return;
    _closed = true;
    _bindings.close(_fd);
  }
}

typedef _PidfdOpenNative = Int32 Function(Int32, Uint32);
typedef _PidfdOpen = int Function(int, int);
typedef _PidfdSignalNative =
    Int32 Function(Int32, Int32, Pointer<Void>, Uint32);
typedef _PidfdSignal = int Function(int, int, Pointer<Void>, int);
typedef _CloseFdNative = Int32 Function(Int32);
typedef _CloseFd = int Function(int);

class _LinuxPidfds {
  _LinuxPidfds(DynamicLibrary library)
    : open = library.lookupFunction<_PidfdOpenNative, _PidfdOpen>('pidfd_open'),
      signal = library.lookupFunction<_PidfdSignalNative, _PidfdSignal>(
        'pidfd_send_signal',
      ),
      close = library.lookupFunction<_CloseFdNative, _CloseFd>('close');

  static final _LinuxPidfds? instance = _load();
  final _PidfdOpen open;
  final _PidfdSignal signal;
  final _CloseFd close;

  static _LinuxPidfds? _load() {
    if (!Platform.isLinux) return null;
    try {
      return _LinuxPidfds(DynamicLibrary.process());
    } on ArgumentError {
      return null;
    }
  }
}

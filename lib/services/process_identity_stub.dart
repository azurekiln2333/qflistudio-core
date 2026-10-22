/// Keeps consumers compilable on targets without dart:ffi.
class ProcessIdentityHandle {
  ProcessIdentityHandle._();

  static ProcessIdentityHandle? tryOpen(int pid) => null;

  bool sendSignal(int signalNumber) => false;

  void close() {}
}

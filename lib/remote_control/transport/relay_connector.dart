// Platform selection for the relay transport.
//
// Import this file (not `relay_socket_io.dart`) to get `connectRelaySocket` for
// the current platform. Native targets get the `dart:io` WebSocket; everything
// else gets the stub that reports the feature as unsupported.

export 'relay_socket_stub.dart' if (dart.library.io) 'relay_socket_io.dart';

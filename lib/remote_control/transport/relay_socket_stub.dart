// Browser / unsupported-platform relay transport.
//
// Remote control drives a paired desktop over a raw WebSocket to the relay; the
// web target has no `dart:io` socket and no pairing UI is offered there. Rather
// than silently failing, this entry throws a truthful error that the connection
// loop surfaces through [RemoteException].

import 'relay_socket.dart';

/// Unsupported-platform entry point.
///
/// Never resolves: the remote-computer module requires a native platform.
Future<RelaySocket> connectRelaySocket(Uri url) async {
  throw UnsupportedError('远程电脑需要原生平台（Android / iOS / 桌面），当前环境不支持直连中继服务器');
}

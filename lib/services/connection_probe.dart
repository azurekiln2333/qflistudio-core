import 'dart:async';
import 'dart:io';

/// 连接诊断用的最小网络层：域名解析、TCP 连接、TLS 握手。
///
/// 只由 `ApiClient.probeConnection()` 使用，并且只连 API 服务器。
/// 测试注入假实现，跑在离线环境下，不碰真实网络。
abstract class ConnectionProbe {
  /// 域名解析。失败时抛 [SocketException]。
  Future<List<String>> lookup(String host);

  /// 建立 TCP 连接，成功后立即关闭。失败时抛 [SocketException]。
  Future<void> connect(String host, int port);

  /// 完成 TLS 握手，成功后立即关闭。失败时抛 [HandshakeException] 等。
  Future<void> handshake(String host, int port);
}

/// 真机实现：系统 DNS、[Socket]、[SecureSocket]。
class SocketConnectionProbe implements ConnectionProbe {
  const SocketConnectionProbe();

  @override
  Future<List<String>> lookup(String host) async {
    final addresses = await InternetAddress.lookup(host);
    return [for (final address in addresses) address.address];
  }

  @override
  Future<void> connect(String host, int port) async {
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw SocketException('$host 没有对应的地址');
    }
    final socket = await Socket.connect(addresses.first, port);
    socket.destroy();
  }

  @override
  Future<void> handshake(String host, int port) async {
    final socket = await SecureSocket.connect(host, port);
    socket.destroy();
  }
}

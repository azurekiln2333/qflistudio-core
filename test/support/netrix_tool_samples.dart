import 'package:qfli_studio_core/tools/ported/models.dart';

/// 每条 netrix 工具跑一次时用的示例输入。
///
/// 起点是工具自己的字段默认值（netrix 的示例值），只有需要把网络目标换成
/// 本机回环的工具才覆盖字段。这样测试既不联网，也不依赖外部服务。
Map<String, String> netrixSampleValues(ToolDefinition tool) {
  final values = <String, String>{
    for (final ToolField field in tool.fields) field.id: field.initialValue,
  };
  final overrides = _loopbackOverrides[tool.id];
  if (overrides != null) values.addAll(overrides);
  return values;
}

/// 会把包发到网卡外面的工具。
///
/// widget 测试不跑这些工具：真实 socket 的 Future 在 widget 测试的假时钟里
/// 不会完成。它们由 `test/netrix_tools_contract_test.dart` 用同一张示例表
/// 直接调用 `run` 跑，HTTP 走本文件里的离线覆盖，TCP 走本机回环。
const Set<String> netrixNetworkToolIds = <String>{
  'reachability',
  'port-check',
  'port-scan',
  'host-scan',
  'hostname-lookup',
  'dns-record',
  'public-ip',
  'local-interfaces',
  'http-request',
  'websocket',
  'dns-propagation',
  'rdap',
  'tls-inspector',
};

/// 网络类工具的示例值：目标一律换成回环地址或 1 号端口。
///
/// `host-scan` 只用回环 CIDR。它的服务层只接受 RFC 1918 私有网段，
/// 因此这次运行会稳定返回 `error_private_network_only`，而不是真的扫网段。
const Map<String, Map<String, String>> _loopbackOverrides =
    <String, Map<String, String>>{
      'reachability': <String, String>{'host': '127.0.0.1', 'port': '1'},
      'port-check': <String, String>{'host': '127.0.0.1', 'port': '1'},
      'port-scan': <String, String>{'host': '127.0.0.1', 'ports': '1'},
      'host-scan': <String, String>{'cidr': '127.0.0.1/32', 'ports': '1'},
      'hostname-lookup': <String, String>{'host': 'localhost'},
      'dns-record': <String, String>{'name': 'localhost'},
      'http-request': <String, String>{'url': 'http://127.0.0.1/'},
      'websocket': <String, String>{'url': 'ws://127.0.0.1:1'},
      'dns-propagation': <String, String>{'name': 'localhost'},
      'rdap': <String, String>{'target': '127.0.0.1'},
      'tls-inspector': <String, String>{'host': '127.0.0.1', 'port': '1'},
      'jwt': <String, String>{
        'token': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl',
      },
    };

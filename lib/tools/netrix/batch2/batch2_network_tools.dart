import 'package:flutter/material.dart';

import 'batch2_address_service.dart';
import 'batch2_models.dart';
import 'batch2_network_service.dart';

/// The 14 network tools of the netrix port (batch 2).
///
/// Each entry copies `netrix/lib/core/registry.dart` verbatim: same id, same
/// Chinese/English titles, same description, same icon, same fields (ids,
/// labels, hints, defaults, keyboard type, option order) and the same runner
/// output rows. Reaching the network requires the host platform to allow
/// outbound sockets; failures surface the same netrix error keys.
const NetworkService _network = NetworkService();

final List<NetrixToolDefinition> batch2NetworkTools = <NetrixToolDefinition>[
  NetrixToolDefinition(
    id: 'reachability',
    title: '主机连通性',
    titleEn: 'TCP Reachability',
    description: '通过 TCP 连接测试主机和端口的可达性与耗时。',
    category: NetrixToolCategory.diagnostics,
    icon: Icons.speed_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'host', label: '主机或 URL', hint: 'example.com'),
      NetrixToolField(
        id: 'port',
        label: '端口',
        initialValue: '443',
        keyboardType: TextInputType.number,
      ),
    ],
    run: _runReachability,
  ),
  NetrixToolDefinition(
    id: 'port-check',
    title: 'TCP 端口检测',
    titleEn: 'TCP Port Check',
    description: '检查单个 TCP 端口是否接受连接。',
    category: NetrixToolCategory.diagnostics,
    icon: Icons.power_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'host', label: '主机或 URL', hint: 'example.com'),
      NetrixToolField(
        id: 'port',
        label: '端口',
        initialValue: '80',
        keyboardType: TextInputType.number,
      ),
    ],
    run: _runPortCheck,
  ),
  NetrixToolDefinition(
    id: 'port-scan',
    title: '端口批量探测',
    titleEn: 'Bounded Port Scan',
    description: '按端口列表或范围进行有限并发 TCP 探测，单次最多 256 个端口。',
    category: NetrixToolCategory.diagnostics,
    icon: Icons.radar_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'host', label: '主机或 URL', hint: '127.0.0.1'),
      NetrixToolField(
        id: 'ports',
        label: '端口列表',
        initialValue: '22,80,443,8000-8003',
        hint: '22,80,8000-8010',
      ),
    ],
    run: _runPortScan,
  ),
  NetrixToolDefinition(
    id: 'host-scan',
    title: '主机扫描',
    titleEn: 'Private Host Scanner',
    description: '在私有 IPv4 网段内进行有上限的 TCP 主机探测，不是 ICMP Ping。',
    category: NetrixToolCategory.diagnostics,
    icon: Icons.radar_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(
        id: 'cidr',
        label: '私有 IPv4 网段',
        initialValue: '192.168.1.0/24',
        hint: '最多 256 个地址',
      ),
      NetrixToolField(
        id: 'ports',
        label: 'TCP 端口',
        initialValue: '22,80,443',
        hint: '最多 16 个端口',
      ),
    ],
    run: _runHostScan,
  ),
  NetrixToolDefinition(
    id: 'hostname-lookup',
    title: '主机名解析',
    titleEn: 'Hostname Lookup',
    description: '使用系统解析器查看主机对应的 IPv4 和 IPv6 地址。',
    category: NetrixToolCategory.dns,
    icon: Icons.travel_explore_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'host', label: '域名或主机', hint: 'example.com'),
    ],
    run: _runHostnameLookup,
  ),
  NetrixToolDefinition(
    id: 'dns-record',
    title: 'DNS 记录查询',
    titleEn: 'DNS-over-HTTPS',
    description: '通过 Cloudflare DNS-over-HTTPS 查询常见记录类型。',
    category: NetrixToolCategory.dns,
    icon: Icons.dns_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'name', label: '域名或地址', hint: 'example.com'),
      NetrixToolField(
        id: 'type',
        label: '记录类型',
        type: NetrixToolFieldType.select,
        initialValue: 'A',
        options: <String>['A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT', 'PTR'],
      ),
    ],
    run: _runDnsRecord,
  ),
  NetrixToolDefinition(
    id: 'public-ip',
    title: '公网 IP',
    titleEn: 'Public IP',
    description: '通过 ipify 查询当前网络出口看到的公网 IP。',
    category: NetrixToolCategory.address,
    icon: Icons.public_outlined,
    fields: const <NetrixToolField>[],
    run: _runPublicIp,
  ),
  NetrixToolDefinition(
    id: 'local-interfaces',
    title: '本机网络接口',
    titleEn: 'Local Interfaces',
    description: '列出当前设备可见的网络接口和地址。',
    category: NetrixToolCategory.local,
    icon: Icons.router_outlined,
    fields: const <NetrixToolField>[],
    run: _runLocalInterfaces,
  ),
  NetrixToolDefinition(
    id: 'http-request',
    title: 'HTTP 请求测试',
    titleEn: 'HTTP Request',
    description: '发送受限的 HTTP 请求并查看状态、响应头、耗时和响应体。',
    category: NetrixToolCategory.web,
    icon: Icons.http_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(
        id: 'method',
        label: '方法',
        type: NetrixToolFieldType.select,
        initialValue: 'GET',
        options: <String>['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'],
      ),
      NetrixToolField(id: 'url', label: 'URL', hint: 'https://example.com'),
      NetrixToolField(
        id: 'headers',
        label: '请求头',
        type: NetrixToolFieldType.multiline,
        required: false,
        hint: 'Accept: application/json',
      ),
      NetrixToolField(
        id: 'body',
        label: '请求体',
        type: NetrixToolFieldType.multiline,
        required: false,
      ),
    ],
    run: _runHttpRequest,
  ),
  NetrixToolDefinition(
    id: 'websocket',
    title: 'WebSocket 测试',
    titleEn: 'WebSocket Probe',
    description: '连接 WebSocket 服务，发送可选消息并等待一条响应。',
    category: NetrixToolCategory.web,
    icon: Icons.cable_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(
        id: 'url',
        label: 'WebSocket URL',
        hint: 'wss://echo.websocket.events',
      ),
      NetrixToolField(
        id: 'message',
        label: '发送消息',
        required: false,
        initialValue: 'hello from Netrix',
      ),
    ],
    run: _runWebSocket,
  ),
  NetrixToolDefinition(
    id: 'mac-normalizer',
    title: 'MAC 地址规范化',
    titleEn: 'MAC Normalizer',
    description: '统一冒号、短横线、点分格式并校验 MAC 地址。',
    category: NetrixToolCategory.local,
    icon: Icons.devices_other_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'mac', label: 'MAC 地址', initialValue: '00-11-22-33-44-55'),
    ],
    run: _runMacNormalizer,
  ),
  NetrixToolDefinition(
    id: 'dns-propagation',
    title: 'DNS 多解析器对比',
    titleEn: 'DNS Propagation',
    description: '同时查询 Cloudflare、Google、AdGuard 并比较不同解析器结果。',
    category: NetrixToolCategory.dns,
    icon: Icons.compare_arrows_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'name', label: '域名', initialValue: 'example.com'),
      NetrixToolField(
        id: 'type',
        label: '记录类型',
        type: NetrixToolFieldType.select,
        initialValue: 'A',
        options: <String>['A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT'],
      ),
    ],
    run: _runDnsPropagation,
  ),
  NetrixToolDefinition(
    id: 'rdap',
    title: 'RDAP 注册信息',
    titleEn: 'RDAP Lookup',
    description: '查询 IP 或域名的注册机构、状态和事件时间线。',
    category: NetrixToolCategory.diagnostics,
    icon: Icons.badge_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'target', label: 'IP 或域名', initialValue: '8.8.8.8'),
    ],
    run: _runRdap,
  ),
  NetrixToolDefinition(
    id: 'tls-inspector',
    title: 'TLS 证书查看',
    titleEn: 'TLS Inspector',
    description: '建立 TLS 连接并查看证书主题、颁发者、有效期和 DER 大小。',
    category: NetrixToolCategory.web,
    icon: Icons.verified_user_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'host', label: '主机或 URL', initialValue: 'example.com'),
      NetrixToolField(
        id: 'port',
        label: '端口',
        initialValue: '443',
        keyboardType: TextInputType.number,
      ),
    ],
    run: _runTlsInspector,
  ),
];

Future<NetrixToolResult> _runReachability(Map<String, String> values) async {
  final TcpProbe probe = await _network.tcpProbe(
    rawHost: values['host'] ?? '',
    port: requirePort(values['port'] ?? ''),
  );
  return NetrixToolResult(
    title: '主机可达',
    summary: 'TCP 连接已建立；这不是 ICMP Ping。',
    rows: <NetrixResultRow>[
      NetrixResultRow('主机', probe.host, mono: false),
      NetrixResultRow('端口', '${probe.port}'),
      NetrixResultRow('解析地址', probe.address ?? '-'),
      NetrixResultRow('连接耗时', formatDuration(probe.elapsed)),
    ],
  );
}

Future<NetrixToolResult> _runPortCheck(Map<String, String> values) async {
  final int port = requirePort(values['port'] ?? '');
  final PortProbe probe = await _network.checkPort(
    rawHost: values['host'] ?? '',
    port: port,
  );
  return NetrixToolResult(
    title: probe.open ? '端口开放或接受连接' : '端口未接受连接',
    ok: probe.open,
    summary: '${values['host']}:$port',
    rows: <NetrixResultRow>[
      NetrixResultRow('端口', '$port'),
      NetrixResultRow('耗时', formatDuration(probe.elapsed)),
    ],
  );
}

Future<NetrixToolResult> _runPortScan(Map<String, String> values) async {
  final List<PortProbe> probes = await _network.scanPorts(
    rawHost: values['host'] ?? '',
    ports: parsePortList(values['ports'] ?? ''),
  );
  final List<PortProbe> open =
      probes.where((PortProbe probe) => probe.open).toList();
  return NetrixToolResult(
    title: '端口探测完成',
    summary: '开放或接受连接的端口：${open.length}/${probes.length}',
    rows: open.isEmpty
        ? <NetrixResultRow>[
            const NetrixResultRow('结果', '没有发现可连接端口', mono: false),
          ]
        : open
            .map(
              (PortProbe probe) =>
                  NetrixResultRow('${probe.port}', formatDuration(probe.elapsed)),
            )
            .toList(),
    panels: <NetrixToolPanel>[
      NetrixToolPanel(
        title: '全部结果',
        text: probes
            .map(
              (PortProbe probe) =>
                  '${probe.port}\t${probe.open ? 'open' : 'closed'}',
            )
            .join('\n'),
      ),
    ],
  );
}

Future<NetrixToolResult> _runHostScan(Map<String, String> values) async {
  final List<HostProbe> probes = await _network.scanHosts(
    rawCidr: values['cidr'] ?? '',
    ports: parsePortList(values['ports'] ?? ''),
  );
  final List<HostProbe> open =
      probes.where((HostProbe probe) => probe.open).toList();
  return NetrixToolResult(
    title: '主机扫描完成',
    summary: 'TCP 探测发现 ${open.length} 个可连接的主机端口',
    rows: open.isEmpty
        ? <NetrixResultRow>[
            const NetrixResultRow('结果', '没有发现可连接主机端口', mono: false),
          ]
        : open
            .map(
              (HostProbe probe) => NetrixResultRow(
                '${probe.host}:${probe.port}',
                formatDuration(probe.elapsed),
              ),
            )
            .toList(),
    panels: <NetrixToolPanel>[
      NetrixToolPanel(
        title: '全部 TCP 结果',
        text: probes
            .map(
              (HostProbe probe) =>
                  '${probe.host}\t${probe.port}\t${probe.open ? 'open' : 'closed'}',
            )
            .join('\n'),
      ),
    ],
  );
}

Future<NetrixToolResult> _runHostnameLookup(Map<String, String> values) async {
  final List<dynamic> addresses =
      await _network.resolveHost(values['host'] ?? '');
  return NetrixToolResult(
    title: '解析完成',
    summary: '共找到 ${addresses.length} 个地址',
    rows: addresses
        .map((dynamic address) => NetrixResultRow('地址', address.address))
        .toList(),
  );
}

Future<NetrixToolResult> _runDnsRecord(Map<String, String> values) async {
  final DnsRecordResult result = await _network.dnsOverHttps(
    rawName: values['name'] ?? '',
    type: values['type'] ?? 'A',
  );
  return NetrixToolResult(
    title: '${result.type} 记录',
    summary: result.records.isEmpty ? '没有返回记录' : '返回 ${result.records.length} 条记录',
    rows: result.records
        .map((String value) => NetrixResultRow('记录', value, mono: false))
        .toList(),
  );
}

Future<NetrixToolResult> _runPublicIp(Map<String, String> values) async {
  final String address = await _network.publicIp();
  return NetrixToolResult(
    title: '公网 IP',
    rows: <NetrixResultRow>[NetrixResultRow('地址', address)],
  );
}

Future<NetrixToolResult> _runLocalInterfaces(Map<String, String> values) async {
  final List<LocalInterfaceInfo> interfaces = await _network.localInterfaces();
  return NetrixToolResult(
    title: '本机网络接口',
    rows: interfaces
        .map(
          (LocalInterfaceInfo item) =>
              NetrixResultRow(item.name, item.addresses.join(', ')),
        )
        .toList(),
  );
}

Future<NetrixToolResult> _runHttpRequest(Map<String, String> values) async {
  final HttpResultData response = await _network.httpRequest(
    method: values['method'] ?? 'GET',
    rawUrl: values['url'] ?? '',
    rawHeaders: values['headers'] ?? '',
    body: values['body'] ?? '',
  );
  return NetrixToolResult(
    title: 'HTTP ${response.statusCode}',
    summary: response.reasonPhrase,
    rows: <NetrixResultRow>[
      NetrixResultRow('方法', response.method),
      NetrixResultRow('状态码', '${response.statusCode}'),
      NetrixResultRow('耗时', formatDuration(response.elapsed)),
      NetrixResultRow('响应头', '${response.headers.length} 项'),
      if (response.truncated)
        const NetrixResultRow('响应体', '已截断到 256 KB', mono: false),
    ],
    panels: <NetrixToolPanel>[
      NetrixToolPanel(
        title: '响应头',
        text: response.headers.entries
            .map(
              (MapEntry<String, String> entry) =>
                  '${entry.key}: ${entry.value}',
            )
            .join('\n'),
      ),
      NetrixToolPanel(
        title: '响应体',
        text: response.body.isEmpty ? '(空)' : response.body,
      ),
    ],
  );
}

Future<NetrixToolResult> _runWebSocket(Map<String, String> values) async {
  final String response = await _network.webSocketProbe(
    rawUrl: values['url'] ?? '',
    message: values['message'] ?? '',
  );
  return NetrixToolResult(
    title: 'WebSocket 收到响应',
    panels: <NetrixToolPanel>[
      NetrixToolPanel(title: '消息', text: response),
    ],
  );
}

Future<NetrixToolResult> _runMacNormalizer(Map<String, String> values) async {
  final String normalized = normalizeMac(values['mac'] ?? '');
  final String hex = normalized.replaceAll(':', '');
  return NetrixToolResult(
    title: 'MAC 地址有效',
    rows: <NetrixResultRow>[
      NetrixResultRow('冒号格式', normalized),
      NetrixResultRow('短横线格式', normalized.replaceAll(':', '-')),
      NetrixResultRow(
        '点分格式',
        '${hex.substring(0, 4)}.${hex.substring(4, 8)}.${hex.substring(8)}',
      ),
    ],
  );
}

Future<NetrixToolResult> _runDnsPropagation(Map<String, String> values) async {
  final List<DnsResolverResult> results = await _network.dnsPropagation(
    rawName: values['name'] ?? '',
    type: values['type'] ?? 'A',
  );
  final int successCount =
      results.where((DnsResolverResult item) => item.error == null).length;
  return NetrixToolResult(
    title: 'DNS 解析器对比',
    summary: '$successCount/${results.length} 个解析器返回结果',
    rows: results
        .map(
          (DnsResolverResult item) => NetrixResultRow(
            item.resolver,
            item.error ?? (item.records.isEmpty ? '(无记录)' : item.records.join(', ')),
            mono: false,
          ),
        )
        .toList(),
  );
}

Future<NetrixToolResult> _runRdap(Map<String, String> values) async {
  final RdapResult result = await _network.rdapLookup(values['target'] ?? '');
  return NetrixToolResult(
    title: 'RDAP 查询完成',
    rows: <NetrixResultRow>[
      NetrixResultRow('目标', result.target, mono: false),
      NetrixResultRow('类型', result.kind),
      NetrixResultRow('名称', result.name ?? '-'),
      NetrixResultRow('句柄', result.handle ?? '-'),
      NetrixResultRow(
        '状态',
        result.status.isEmpty ? '-' : result.status.join(', '),
        mono: false,
      ),
      NetrixResultRow(
        '事件',
        result.events.isEmpty ? '-' : result.events.join('\n'),
        mono: false,
      ),
    ],
    panels: <NetrixToolPanel>[
      NetrixToolPanel(title: 'RDAP JSON', text: result.body),
    ],
  );
}

Future<NetrixToolResult> _runTlsInspector(Map<String, String> values) async {
  final TlsInfo info = await _network.inspectTls(
    rawHost: values['host'] ?? '',
    port: requirePort(values['port'] ?? '', fallback: 443),
  );
  return NetrixToolResult(
    title: 'TLS 证书已读取',
    summary: '此工具为读取证书而接受无效证书，不代表证书可信。',
    rows: <NetrixResultRow>[
      NetrixResultRow('主机', '${info.host}:${info.port}'),
      NetrixResultRow('Subject', info.subject, mono: false),
      NetrixResultRow('Issuer', info.issuer, mono: false),
      NetrixResultRow('生效时间', info.validFrom?.toIso8601String() ?? '-'),
      NetrixResultRow('过期时间', info.validTo?.toIso8601String() ?? '-'),
      NetrixResultRow('DER 大小', formatBytes(info.derLength)),
    ],
  );
}

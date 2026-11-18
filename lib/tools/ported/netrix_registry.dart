import 'dart:convert';

import 'package:flutter/material.dart';

import 'models.dart';
import 'services/address_service.dart';
import 'services/advanced_service.dart';
import 'services/network_service.dart';
import 'services/text_service.dart';

const NetworkService _network = NetworkService();

final List<ToolDefinition> kTools = <ToolDefinition>[
  ToolDefinition(
    id: 'reachability',
    title: '主机连通性',
    titleEn: 'TCP Reachability',
    description: '通过 TCP 连接测试主机和端口的可达性与耗时。',
    category: ToolCategory.diagnostics,
    icon: Icons.speed_outlined,
    fields: <ToolField>[
      ToolField(id: 'host', label: '主机或 URL', hint: 'example.com'),
      ToolField(
          id: 'port',
          label: '端口',
          initialValue: '443',
          keyboardType: TextInputType.number),
    ],
    run: _runReachability,
  ),
  ToolDefinition(
    id: 'port-check',
    title: 'TCP 端口检测',
    titleEn: 'TCP Port Check',
    description: '检查单个 TCP 端口是否接受连接。',
    category: ToolCategory.diagnostics,
    icon: Icons.power_outlined,
    fields: <ToolField>[
      ToolField(id: 'host', label: '主机或 URL', hint: 'example.com'),
      ToolField(
          id: 'port',
          label: '端口',
          initialValue: '80',
          keyboardType: TextInputType.number),
    ],
    run: _runPortCheck,
  ),
  ToolDefinition(
    id: 'port-scan',
    title: '端口批量探测',
    titleEn: 'Bounded Port Scan',
    description: '按端口列表或范围进行有限并发 TCP 探测，单次最多 256 个端口。',
    category: ToolCategory.diagnostics,
    icon: Icons.radar_outlined,
    fields: <ToolField>[
      ToolField(id: 'host', label: '主机或 URL', hint: '127.0.0.1'),
      ToolField(
          id: 'ports',
          label: '端口列表',
          initialValue: '22,80,443,8000-8003',
          hint: '22,80,8000-8010'),
    ],
    run: _runPortScan,
  ),
  ToolDefinition(
    id: 'host-scan',
    title: '主机扫描',
    titleEn: 'Private Host Scanner',
    description: '在私有 IPv4 网段内进行有上限的 TCP 主机探测，不是 ICMP Ping。',
    category: ToolCategory.diagnostics,
    icon: Icons.radar_outlined,
    fields: <ToolField>[
      ToolField(
        id: 'cidr',
        label: '私有 IPv4 网段',
        initialValue: '192.168.1.0/24',
        hint: '最多 256 个地址',
      ),
      ToolField(
        id: 'ports',
        label: 'TCP 端口',
        initialValue: '22,80,443',
        hint: '最多 16 个端口',
      ),
    ],
    run: _runHostScan,
  ),
  ToolDefinition(
    id: 'hostname-lookup',
    title: '主机名解析',
    titleEn: 'Hostname Lookup',
    description: '使用系统解析器查看主机对应的 IPv4 和 IPv6 地址。',
    category: ToolCategory.dns,
    icon: Icons.travel_explore_outlined,
    fields: <ToolField>[
      ToolField(id: 'host', label: '域名或主机', hint: 'example.com')
    ],
    run: _runHostnameLookup,
  ),
  ToolDefinition(
    id: 'dns-record',
    title: 'DNS 记录查询',
    titleEn: 'DNS-over-HTTPS',
    description: '通过 Cloudflare DNS-over-HTTPS 查询常见记录类型。',
    category: ToolCategory.dns,
    icon: Icons.dns_outlined,
    fields: <ToolField>[
      ToolField(id: 'name', label: '域名或地址', hint: 'example.com'),
      ToolField(
        id: 'type',
        label: '记录类型',
        type: ToolFieldType.select,
        initialValue: 'A',
        options: <String>['A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT', 'PTR'],
      ),
    ],
    run: _runDnsRecord,
  ),
  ToolDefinition(
    id: 'subnet-calculator',
    title: 'IPv4 子网计算',
    titleEn: 'IPv4 CIDR Calculator',
    description: '计算网络地址、掩码、广播地址和可用主机范围。',
    category: ToolCategory.address,
    icon: Icons.account_tree_outlined,
    fields: <ToolField>[
      ToolField(id: 'cidr', label: 'CIDR 地址', initialValue: '192.168.1.42/24'),
    ],
    run: _runSubnet,
  ),
  ToolDefinition(
    id: 'public-ip',
    title: '公网 IP',
    titleEn: 'Public IP',
    description: '通过 ipify 查询当前网络出口看到的公网 IP。',
    category: ToolCategory.address,
    icon: Icons.public_outlined,
    fields: const <ToolField>[],
    run: _runPublicIp,
  ),
  ToolDefinition(
    id: 'local-interfaces',
    title: '本机网络接口',
    titleEn: 'Local Interfaces',
    description: '列出当前设备可见的网络接口和地址。',
    category: ToolCategory.local,
    icon: Icons.router_outlined,
    fields: const <ToolField>[],
    run: _runLocalInterfaces,
  ),
  ToolDefinition(
    id: 'http-request',
    title: 'HTTP 请求测试',
    titleEn: 'HTTP Request',
    description: '发送受限的 HTTP 请求并查看状态、响应头、耗时和响应体。',
    category: ToolCategory.web,
    icon: Icons.http_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'method',
          label: '方法',
          type: ToolFieldType.select,
          initialValue: 'GET',
          options: <String>['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD']),
      ToolField(id: 'url', label: 'URL', hint: 'https://example.com'),
      ToolField(
          id: 'headers',
          label: '请求头',
          type: ToolFieldType.multiline,
          required: false,
          hint: 'Accept: application/json'),
      ToolField(
          id: 'body',
          label: '请求体',
          type: ToolFieldType.multiline,
          required: false),
    ],
    run: _runHttpRequest,
  ),
  ToolDefinition(
    id: 'websocket',
    title: 'WebSocket 测试',
    titleEn: 'WebSocket Probe',
    description: '连接 WebSocket 服务，发送可选消息并等待一条响应。',
    category: ToolCategory.web,
    icon: Icons.cable_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'url',
          label: 'WebSocket URL',
          hint: 'wss://echo.websocket.events'),
      ToolField(
          id: 'message',
          label: '发送消息',
          required: false,
          initialValue: 'hello from Netrix'),
    ],
    run: _runWebSocket,
  ),
  ToolDefinition(
    id: 'url-parser',
    title: 'URL 解析',
    titleEn: 'URL Parser',
    description: '拆解 URL 的协议、主机、端口、路径、查询参数和片段。',
    category: ToolCategory.web,
    icon: Icons.link_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'url',
          label: 'URL',
          initialValue: 'https://example.com/path?query=1#section')
    ],
    run: _runUrlParser,
  ),
  ToolDefinition(
    id: 'json',
    title: 'JSON 格式化',
    titleEn: 'JSON Formatter',
    description: '校验 JSON 并输出缩进后的可读格式。',
    category: ToolCategory.text,
    icon: Icons.data_object_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'input',
          label: 'JSON',
          type: ToolFieldType.multiline,
          initialValue: '{"name":"Netrix","ok":true}')
    ],
    run: _runJson,
  ),
  ToolDefinition(
    id: 'base64',
    title: 'Base64 编解码',
    titleEn: 'Base64 Codec',
    description: '在 UTF-8 文本和 Base64 字符串之间转换。',
    category: ToolCategory.text,
    icon: Icons.swap_horiz_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'mode',
          label: '模式',
          type: ToolFieldType.select,
          initialValue: 'encode',
          options: <String>['encode', 'decode']),
      ToolField(id: 'input', label: '内容', type: ToolFieldType.multiline),
    ],
    run: _runBase64,
  ),
  ToolDefinition(
    id: 'url-codec',
    title: 'URL 编解码',
    titleEn: 'URL Codec',
    description: '对 URL 组件进行百分号编码或解码。',
    category: ToolCategory.text,
    icon: Icons.link_off_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'mode',
          label: '模式',
          type: ToolFieldType.select,
          initialValue: 'encode',
          options: <String>['encode', 'decode']),
      ToolField(id: 'input', label: '内容', type: ToolFieldType.multiline),
    ],
    run: _runUrlCodec,
  ),
  ToolDefinition(
    id: 'hex',
    title: 'Hex 编解码',
    titleEn: 'Hex Codec',
    description: '在 UTF-8 文本和十六进制字节之间转换。',
    category: ToolCategory.text,
    icon: Icons.code_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'mode',
          label: '模式',
          type: ToolFieldType.select,
          initialValue: 'encode',
          options: <String>['encode', 'decode']),
      ToolField(id: 'input', label: '内容', type: ToolFieldType.multiline),
    ],
    run: _runHex,
  ),
  ToolDefinition(
    id: 'digest',
    title: '摘要哈希',
    titleEn: 'Digest Hash',
    description: '计算 MD5、SHA-1、SHA-256 或 SHA-512 摘要。',
    category: ToolCategory.security,
    icon: Icons.fingerprint_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'algorithm',
          label: '算法',
          type: ToolFieldType.select,
          initialValue: 'sha256',
          options: <String>['md5', 'sha1', 'sha256', 'sha512']),
      ToolField(id: 'input', label: '内容', type: ToolFieldType.multiline),
    ],
    run: _runDigest,
  ),
  ToolDefinition(
    id: 'jwt',
    title: 'JWT 查看器',
    titleEn: 'JWT Viewer',
    description: '本地解码 JWT 的 header 和 payload，不验证签名有效性。',
    category: ToolCategory.security,
    icon: Icons.key_outlined,
    fields: <ToolField>[
      ToolField(id: 'token', label: 'JWT', type: ToolFieldType.multiline)
    ],
    run: _runJwt,
  ),
  ToolDefinition(
    id: 'subnet-splitter',
    title: '子网拆分规划',
    titleEn: 'Subnet Splitter',
    description: '把一个 IPv4 CIDR 按新前缀拆成等大小子网，最多生成 256 段。',
    category: ToolCategory.address,
    icon: Icons.call_split_outlined,
    fields: <ToolField>[
      ToolField(id: 'cidr', label: '父网段', initialValue: '10.0.0.0/16'),
      ToolField(
          id: 'prefix',
          label: '新前缀',
          initialValue: '24',
          keyboardType: TextInputType.number),
    ],
    run: _runSubnetSplitter,
  ),
  ToolDefinition(
    id: 'range-to-cidr',
    title: 'IP 范围转 CIDR',
    titleEn: 'Range to CIDR',
    description: '把起止 IPv4 地址转换为不重叠的最小 CIDR 列表。',
    category: ToolCategory.address,
    icon: Icons.swap_calls_outlined,
    fields: <ToolField>[
      ToolField(id: 'start', label: '起始地址', initialValue: '192.168.1.10'),
      ToolField(id: 'end', label: '结束地址', initialValue: '192.168.1.31'),
    ],
    run: _runRangeToCidr,
  ),
  ToolDefinition(
    id: 'cidr-aggregate',
    title: 'CIDR 聚合',
    titleEn: 'CIDR Aggregator',
    description: '合并输入中连续且对齐的相邻网段，减少路由条目数量。',
    category: ToolCategory.address,
    icon: Icons.merge_type_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'cidrs',
          label: 'CIDR 列表',
          type: ToolFieldType.multiline,
          initialValue: '10.0.0.0/25\n10.0.0.128/25'),
    ],
    run: _runCidrAggregate,
  ),
  ToolDefinition(
    id: 'ip-converter',
    title: 'IPv4 进制转换',
    titleEn: 'IPv4 Converter',
    description: '查看 IPv4 的十进制整数、二进制和十六进制表示。',
    category: ToolCategory.address,
    icon: Icons.calculate_outlined,
    fields: <ToolField>[
      ToolField(id: 'ip', label: 'IPv4 地址', initialValue: '192.168.1.1')
    ],
    run: _runIpConverter,
  ),
  ToolDefinition(
    id: 'wildcard-mask',
    title: '通配符掩码',
    titleEn: 'Wildcard Mask',
    description: '根据 CIDR 前缀计算 ACL/OSPF 常用的反掩码。',
    category: ToolCategory.address,
    icon: Icons.filter_alt_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'prefix',
          label: '前缀长度',
          initialValue: '24',
          keyboardType: TextInputType.number)
    ],
    run: _runWildcardMask,
  ),
  ToolDefinition(
    id: 'ip-inspector',
    title: 'IPv4 / IPv6 查看',
    titleEn: 'IP Inspector',
    description: '识别地址族、规范化地址并查看原始字节。',
    category: ToolCategory.address,
    icon: Icons.account_tree_outlined,
    fields: <ToolField>[
      ToolField(id: 'ip', label: 'IP 地址', initialValue: '2001:db8::1')
    ],
    run: _runIpInspector,
  ),
  ToolDefinition(
    id: 'mac-normalizer',
    title: 'MAC 地址规范化',
    titleEn: 'MAC Normalizer',
    description: '统一冒号、短横线、点分格式并校验 MAC 地址。',
    category: ToolCategory.local,
    icon: Icons.devices_other_outlined,
    fields: <ToolField>[
      ToolField(id: 'mac', label: 'MAC 地址', initialValue: '00-11-22-33-44-55')
    ],
    run: _runMacNormalizer,
  ),
  ToolDefinition(
    id: 'dns-propagation',
    title: 'DNS 多解析器对比',
    titleEn: 'DNS Propagation',
    description: '同时查询 Cloudflare、Google、AdGuard 并比较不同解析器结果。',
    category: ToolCategory.dns,
    icon: Icons.compare_arrows_outlined,
    fields: <ToolField>[
      ToolField(id: 'name', label: '域名', initialValue: 'example.com'),
      ToolField(
          id: 'type',
          label: '记录类型',
          type: ToolFieldType.select,
          initialValue: 'A',
          options: <String>['A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT']),
    ],
    run: _runDnsPropagation,
  ),
  ToolDefinition(
    id: 'rdap',
    title: 'RDAP 注册信息',
    titleEn: 'RDAP Lookup',
    description: '查询 IP 或域名的注册机构、状态和事件时间线。',
    category: ToolCategory.diagnostics,
    icon: Icons.badge_outlined,
    fields: <ToolField>[
      ToolField(id: 'target', label: 'IP 或域名', initialValue: '8.8.8.8')
    ],
    run: _runRdap,
  ),
  ToolDefinition(
    id: 'tls-inspector',
    title: 'TLS 证书查看',
    titleEn: 'TLS Inspector',
    description: '建立 TLS 连接并查看证书主题、颁发者、有效期和 DER 大小。',
    category: ToolCategory.web,
    icon: Icons.verified_user_outlined,
    fields: <ToolField>[
      ToolField(id: 'host', label: '主机或 URL', initialValue: 'example.com'),
      ToolField(
          id: 'port',
          label: '端口',
          initialValue: '443',
          keyboardType: TextInputType.number),
    ],
    run: _runTlsInspector,
  ),
  ToolDefinition(
    id: 'http-status',
    title: 'HTTP 状态码参考',
    titleEn: 'HTTP Status Reference',
    description: '离线查询常见 HTTP 状态码、类别和处理建议。',
    category: ToolCategory.web,
    icon: Icons.rule_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'code',
          label: '状态码',
          initialValue: '503',
          keyboardType: TextInputType.number)
    ],
    run: _runHttpStatus,
  ),
  ToolDefinition(
    id: 'port-reference',
    title: '常用端口参考',
    titleEn: 'Port Reference',
    description: '离线查询常用服务端口、协议和安全建议。',
    category: ToolCategory.diagnostics,
    icon: Icons.list_alt_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'port',
          label: '端口',
          initialValue: '443',
          keyboardType: TextInputType.number)
    ],
    run: _runPortReference,
  ),
  ToolDefinition(
    id: 'headers-parser',
    title: 'HTTP 请求头分析',
    titleEn: 'Header Analyzer',
    description: '解析原始请求头并按字段展示，便于排查代理和 API 问题。',
    category: ToolCategory.web,
    icon: Icons.subject_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'headers',
          label: '请求头',
          type: ToolFieldType.multiline,
          initialValue: 'Host: example.com\nAccept: application/json')
    ],
    run: _runHeadersParser,
  ),
  ToolDefinition(
    id: 'curl-builder',
    title: 'cURL 命令生成',
    titleEn: 'cURL Builder',
    description: '从方法、URL、请求头和请求体生成可复制的 cURL 命令。',
    category: ToolCategory.web,
    icon: Icons.terminal_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'method',
          label: '方法',
          type: ToolFieldType.select,
          initialValue: 'GET',
          options: <String>['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD']),
      ToolField(
          id: 'url', label: 'URL', initialValue: 'https://example.com/api'),
      ToolField(
          id: 'headers',
          label: '请求头',
          type: ToolFieldType.multiline,
          required: false,
          initialValue: 'Accept: application/json'),
      ToolField(
          id: 'body',
          label: '请求体',
          type: ToolFieldType.multiline,
          required: false),
    ],
    run: _runCurlBuilder,
  ),
  ToolDefinition(
    id: 'ip-membership',
    title: 'IPv4 网段归属',
    titleEn: 'IPv4 CIDR Membership',
    description: '判断 IPv4 地址是否属于指定 CIDR 网段。',
    category: ToolCategory.address,
    icon: Icons.account_tree_outlined,
    fields: <ToolField>[
      ToolField(id: 'ip', label: 'IPv4 地址', initialValue: '192.168.1.42'),
      ToolField(id: 'cidr', label: 'CIDR 网段', initialValue: '192.168.1.0/24'),
    ],
    run: _runIpMembership,
  ),
  ToolDefinition(
    id: 'ip-range',
    title: 'IPv4 地址范围',
    titleEn: 'IPv4 Range',
    description: '查看 CIDR 的网络、广播和首尾主机地址。',
    category: ToolCategory.address,
    icon: Icons.swap_calls_outlined,
    fields: <ToolField>[
      ToolField(id: 'cidr', label: 'CIDR 网段', initialValue: '10.0.0.0/24')
    ],
    run: _runIpRange,
  ),
  ToolDefinition(
    id: 'reverse-dns',
    title: '反向 DNS 名称',
    titleEn: 'Reverse DNS Name',
    description: '把 IPv4 或 IPv6 地址转换为 in-addr.arpa 或 ip6.arpa 名称。',
    category: ToolCategory.dns,
    icon: Icons.dns_outlined,
    fields: <ToolField>[
      ToolField(id: 'ip', label: 'IP 地址', initialValue: '192.0.2.1')
    ],
    run: _runReverseDns,
  ),
  ToolDefinition(
    id: 'dns-name',
    title: 'DNS 名称检查',
    titleEn: 'DNS Name Inspector',
    description: '规范化 DNS 名称并检查标签长度、字符和完全限定形式。',
    category: ToolCategory.dns,
    icon: Icons.travel_explore_outlined,
    fields: <ToolField>[
      ToolField(id: 'name', label: 'DNS 名称', initialValue: 'Api.Example.com.')
    ],
    run: _runDnsName,
  ),
  ToolDefinition(
    id: 'query-parser',
    title: '查询字符串解析',
    titleEn: 'Query String Parser',
    description: '解码 URL 查询参数，保留重复键并限制参数数量。',
    category: ToolCategory.web,
    icon: Icons.subject_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'query', label: '查询字符串', initialValue: 'q=netrix&page=1&page=2')
    ],
    run: _runQueryParser,
  ),
  ToolDefinition(
    id: 'query-builder',
    title: '查询字符串生成',
    titleEn: 'Query String Builder',
    description: '从每行 name=value 输入生成百分号编码的查询字符串。',
    category: ToolCategory.web,
    icon: Icons.link_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'parameters',
          label: '参数',
          type: ToolFieldType.multiline,
          initialValue: 'q=network toolbox\npage=1'),
    ],
    run: _runQueryBuilder,
  ),
  ToolDefinition(
    id: 'http-content-type',
    title: 'Content-Type 分析',
    titleEn: 'Content-Type Inspector',
    description: '拆解 HTTP Content-Type 的媒体类型、字符集和参数。',
    category: ToolCategory.web,
    icon: Icons.http_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'contentType',
          label: 'Content-Type',
          initialValue: 'application/json; charset=utf-8')
    ],
    run: _runHttpContentType,
  ),
  ToolDefinition(
    id: 'http-cache-control',
    title: 'Cache-Control 分析',
    titleEn: 'Cache-Control Inspector',
    description: '按指令解析缓存策略，便于排查浏览器和代理缓存行为。',
    category: ToolCategory.web,
    icon: Icons.rule_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'header',
          label: 'Cache-Control',
          initialValue: 'public, max-age=3600, no-cache')
    ],
    run: _runHttpCacheControl,
  ),
  ToolDefinition(
    id: 'http-date',
    title: 'HTTP 日期转换',
    titleEn: 'HTTP Date Parser',
    description: '解析 RFC HTTP 日期并输出 UTC ISO-8601 时间。',
    category: ToolCategory.web,
    icon: Icons.schedule_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'date',
          label: 'HTTP 日期',
          initialValue: 'Tue, 15 Nov 1994 08:12:31 GMT')
    ],
    run: _runHttpDate,
  ),
  ToolDefinition(
    id: 'basic-auth',
    title: 'Basic 认证头',
    titleEn: 'Basic Auth Header',
    description: '离线生成 UTF-8 Basic Authorization 请求头。',
    category: ToolCategory.security,
    icon: Icons.lock_outline,
    fields: <ToolField>[
      ToolField(id: 'username', label: '用户名', initialValue: 'netrix'),
      ToolField(
          id: 'password',
          label: '密码',
          initialValue: 'secret',
          obscureText: true),
    ],
    run: _runBasicAuth,
  ),
  ToolDefinition(
    id: 'timestamp-converter',
    title: 'Unix 时间戳转换',
    titleEn: 'Unix Timestamp Converter',
    description: '识别秒或毫秒 Unix 时间戳并转换为 UTC 时间。',
    category: ToolCategory.text,
    icon: Icons.schedule_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'timestamp',
          label: '时间戳',
          initialValue: '1720000000',
          keyboardType: TextInputType.number)
    ],
    run: _runTimestamp,
  ),
  ToolDefinition(
    id: 'prefix-mask',
    title: '前缀转子网掩码',
    titleEn: 'Prefix to Netmask',
    description: '把 IPv4 CIDR 前缀转换为子网掩码和通配符掩码。',
    category: ToolCategory.address,
    icon: Icons.filter_alt_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'prefix',
          label: '前缀长度',
          initialValue: '24',
          keyboardType: TextInputType.number)
    ],
    run: _runPrefixMask,
  ),
  ToolDefinition(
    id: 'mask-prefix',
    title: '子网掩码转前缀',
    titleEn: 'Netmask to Prefix',
    description: '校验连续 IPv4 子网掩码并转换为 CIDR 前缀。',
    category: ToolCategory.address,
    icon: Icons.compare_arrows_outlined,
    fields: <ToolField>[
      ToolField(id: 'mask', label: '子网掩码', initialValue: '255.255.255.0')
    ],
    run: _runMaskPrefix,
  ),
  ToolDefinition(
    id: 'port-range',
    title: '端口范围分析',
    titleEn: 'Port Range Analyzer',
    description: '校验端口范围并计算端口数量，最大限制为 4096 个。',
    category: ToolCategory.diagnostics,
    icon: Icons.list_alt_outlined,
    fields: <ToolField>[
      ToolField(id: 'ports', label: '端口范围', initialValue: '8000-8080')
    ],
    run: _runPortRange,
  ),
  ToolDefinition(
    id: 'ipv4-classifier',
    title: 'IPv4 分类查看',
    titleEn: 'IPv4 Classifier',
    description: '查看 IPv4 的传统地址类和常见用途范围。',
    category: ToolCategory.address,
    icon: Icons.category_outlined,
    fields: <ToolField>[
      ToolField(id: 'ip', label: 'IPv4 地址', initialValue: '192.168.1.1')
    ],
    run: _runIpv4Classifier,
  ),
  ToolDefinition(
    id: 'ipv4-scope',
    title: 'IPv4 地址范围',
    titleEn: 'IPv4 Scope',
    description: '识别回环、私有、链路本地、组播和共享地址空间。',
    category: ToolCategory.address,
    icon: Icons.public_outlined,
    fields: <ToolField>[
      ToolField(id: 'ip', label: 'IPv4 地址', initialValue: '10.0.0.1')
    ],
    run: _runIpv4Scope,
  ),
  ToolDefinition(
    id: 'cookie-parser',
    title: 'Cookie 请求头分析',
    titleEn: 'Cookie Header Parser',
    description: '按名称和值解析 Cookie 请求头，限制最多 64 个 Cookie。',
    category: ToolCategory.web,
    icon: Icons.subject_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'cookie',
          label: 'Cookie',
          initialValue: 'session=abc123; theme=dark')
    ],
    run: _runCookieParser,
  ),
  ToolDefinition(
    id: 'url-join',
    title: 'URL 路径拼接',
    titleEn: 'URL Resolver',
    description: '按照 URL 解析规则把基础 URL 和相对路径组合起来。',
    category: ToolCategory.web,
    icon: Icons.link_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'base',
          label: '基础 URL',
          initialValue: 'https://example.com/api/'),
      ToolField(id: 'path', label: '相对路径', initialValue: 'v1/status'),
    ],
    run: _runUrlJoin,
  ),
  ToolDefinition(
    id: 'http-method',
    title: 'HTTP 方法参考',
    titleEn: 'HTTP Method Reference',
    description: '查看 HTTP 方法是否安全、幂等以及通常是否携带请求体。',
    category: ToolCategory.web,
    icon: Icons.rule_outlined,
    fields: <ToolField>[
      ToolField(
          id: 'method',
          label: '方法',
          type: ToolFieldType.select,
          initialValue: 'GET',
          options: <String>[
            'GET',
            'POST',
            'PUT',
            'PATCH',
            'DELETE',
            'HEAD',
            'OPTIONS',
            'TRACE'
          ]),
    ],
    run: _runHttpMethod,
  ),
  ToolDefinition(
    id: 'dns-label',
    title: 'DNS 标签检查',
    titleEn: 'DNS Label Validator',
    description: '单独检查一个 DNS 标签的字符和长度限制。',
    category: ToolCategory.dns,
    icon: Icons.dns_outlined,
    fields: <ToolField>[
      ToolField(id: 'label', label: 'DNS 标签', initialValue: 'gateway-01')
    ],
    run: _runDnsLabel,
  ),
];

Future<ToolResult> _runReachability(Map<String, String> values) async {
  final TcpProbe probe = await _network.tcpProbe(
    rawHost: values['host'] ?? '',
    port: requirePort(values['port'] ?? ''),
  );
  return ToolResult(
    title: '主机可达',
    summary: 'TCP 连接已建立；这不是 ICMP Ping。',
    rows: <ResultRow>[
      ResultRow('主机', probe.host, mono: false),
      ResultRow('端口', '${probe.port}'),
      ResultRow('解析地址', probe.address ?? '-'),
      ResultRow('连接耗时', formatDuration(probe.elapsed)),
    ],
  );
}

Future<ToolResult> _runPortCheck(Map<String, String> values) async {
  final int port = requirePort(values['port'] ?? '');
  final PortProbe probe =
      await _network.checkPort(rawHost: values['host'] ?? '', port: port);
  return ToolResult(
    title: probe.open ? '端口开放或接受连接' : '端口未接受连接',
    ok: probe.open,
    summary: '${values['host']}:$port',
    rows: <ResultRow>[
      ResultRow('端口', '$port'),
      ResultRow('耗时', formatDuration(probe.elapsed))
    ],
  );
}

Future<ToolResult> _runPortScan(Map<String, String> values) async {
  final List<PortProbe> probes = await _network.scanPorts(
    rawHost: values['host'] ?? '',
    ports: parsePortList(values['ports'] ?? ''),
  );
  final List<PortProbe> open =
      probes.where((PortProbe probe) => probe.open).toList();
  return ToolResult(
    title: '端口探测完成',
    summary: '开放或接受连接的端口：${open.length}/${probes.length}',
    rows: open.isEmpty
        ? <ResultRow>[const ResultRow('结果', '没有发现可连接端口', mono: false)]
        : open
            .map((PortProbe probe) =>
                ResultRow('${probe.port}', formatDuration(probe.elapsed)))
            .toList(),
    panels: <ToolPanel>[
      ToolPanel(
          title: '全部结果',
          text: probes
              .map((PortProbe probe) =>
                  '${probe.port}\t${probe.open ? 'open' : 'closed'}')
              .join('\n')),
    ],
  );
}

Future<ToolResult> _runHostScan(Map<String, String> values) async {
  final List<HostProbe> probes = await _network.scanHosts(
    rawCidr: values['cidr'] ?? '',
    ports: parsePortList(values['ports'] ?? ''),
  );
  final List<HostProbe> open =
      probes.where((HostProbe probe) => probe.open).toList();
  return ToolResult(
    title: '主机扫描完成',
    summary: 'TCP 探测发现 ${open.length} 个可连接的主机端口',
    rows: open.isEmpty
        ? <ResultRow>[const ResultRow('结果', '没有发现可连接主机端口', mono: false)]
        : open
            .map(
              (HostProbe probe) => ResultRow(
                '${probe.host}:${probe.port}',
                formatDuration(probe.elapsed),
              ),
            )
            .toList(),
    panels: <ToolPanel>[
      ToolPanel(
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

Future<ToolResult> _runHostnameLookup(Map<String, String> values) async {
  final List<dynamic> addresses =
      await _network.resolveHost(values['host'] ?? '');
  return ToolResult(
    title: '解析完成',
    summary: '共找到 ${addresses.length} 个地址',
    rows: addresses
        .map((dynamic address) => ResultRow('地址', address.address))
        .toList(),
  );
}

Future<ToolResult> _runDnsRecord(Map<String, String> values) async {
  final DnsRecordResult result = await _network.dnsOverHttps(
    rawName: values['name'] ?? '',
    type: values['type'] ?? 'A',
  );
  return ToolResult(
    title: '${result.type} 记录',
    summary:
        result.records.isEmpty ? '没有返回记录' : '返回 ${result.records.length} 条记录',
    rows: result.records
        .map((String value) => ResultRow('记录', value, mono: false))
        .toList(),
  );
}

Future<ToolResult> _runSubnet(Map<String, String> values) async {
  final SubnetInfo info = calculateSubnet(values['cidr'] ?? '');
  return ToolResult(
    title: '子网计算完成',
    rows: <ResultRow>[
      ResultRow('网络地址', info.network),
      ResultRow('前缀长度', '/${info.prefix}'),
      ResultRow('子网掩码', info.mask),
      ResultRow('广播地址', info.broadcast),
      ResultRow('首个主机', info.firstHost),
      ResultRow('最后主机', info.lastHost),
      ResultRow('可用主机数', '${info.hostCount}'),
    ],
  );
}

Future<ToolResult> _runPublicIp(Map<String, String> values) async {
  final String address = await _network.publicIp();
  return ToolResult(
      title: '公网 IP', rows: <ResultRow>[ResultRow('地址', address)]);
}

Future<ToolResult> _runLocalInterfaces(Map<String, String> values) async {
  final List<LocalInterfaceInfo> interfaces = await _network.localInterfaces();
  return ToolResult(
    title: '本机网络接口',
    rows: interfaces
        .map((LocalInterfaceInfo item) =>
            ResultRow(item.name, item.addresses.join(', ')))
        .toList(),
  );
}

Future<ToolResult> _runHttpRequest(Map<String, String> values) async {
  final HttpResultData response = await _network.httpRequest(
    method: values['method'] ?? 'GET',
    rawUrl: values['url'] ?? '',
    rawHeaders: values['headers'] ?? '',
    body: values['body'] ?? '',
  );
  return ToolResult(
    title: 'HTTP ${response.statusCode}',
    summary: response.reasonPhrase,
    rows: <ResultRow>[
      ResultRow('方法', response.method),
      ResultRow('状态码', '${response.statusCode}'),
      ResultRow('耗时', formatDuration(response.elapsed)),
      ResultRow('响应头', '${response.headers.length} 项'),
      if (response.truncated)
        const ResultRow('响应体', '已截断到 256 KB', mono: false),
    ],
    panels: <ToolPanel>[
      ToolPanel(
          title: '响应头',
          text: response.headers.entries
              .map((MapEntry<String, String> entry) =>
                  '${entry.key}: ${entry.value}')
              .join('\n')),
      ToolPanel(
          title: '响应体', text: response.body.isEmpty ? '(空)' : response.body),
    ],
  );
}

Future<ToolResult> _runWebSocket(Map<String, String> values) async {
  final String response = await _network.webSocketProbe(
    rawUrl: values['url'] ?? '',
    message: values['message'] ?? '',
  );
  return ToolResult(
      title: 'WebSocket 收到响应',
      panels: <ToolPanel>[ToolPanel(title: '消息', text: response)]);
}

Future<ToolResult> _runUrlParser(Map<String, String> values) async {
  final String raw = requireValue(values['url'] ?? '', field: 'URL');
  final Uri? uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    throw ToolException('error_invalid_url');
  }
  return ToolResult(
    title: 'URL 解析完成',
    rows: <ResultRow>[
      ResultRow('协议', uri.scheme),
      ResultRow('主机', uri.host),
      ResultRow('端口', uri.hasPort ? '${uri.port}' : '(默认)'),
      ResultRow('路径', uri.path.isEmpty ? '/' : uri.path),
      ResultRow('查询', uri.query.isEmpty ? '(无)' : uri.query, mono: false),
      ResultRow('片段', uri.fragment.isEmpty ? '(无)' : uri.fragment, mono: false),
    ],
  );
}

Future<ToolResult> _runJson(Map<String, String> values) async {
  return ToolResult(title: 'JSON 有效', panels: <ToolPanel>[
    ToolPanel(title: '格式化结果', text: formatJson(values['input'] ?? ''))
  ]);
}

Future<ToolResult> _runBase64(Map<String, String> values) async {
  final bool encode = values['mode'] != 'decode';
  final String input = values['input'] ?? '';
  return ToolResult(
      title: encode ? 'Base64 编码完成' : 'Base64 解码完成',
      panels: <ToolPanel>[
        ToolPanel(
            title: '结果',
            text: encode ? base64EncodeText(input) : base64DecodeText(input))
      ]);
}

Future<ToolResult> _runUrlCodec(Map<String, String> values) async {
  final bool encode = values['mode'] != 'decode';
  final String input = values['input'] ?? '';
  return ToolResult(
      title: encode ? 'URL 编码完成' : 'URL 解码完成',
      panels: <ToolPanel>[
        ToolPanel(
            title: '结果',
            text: encode ? urlEncodeText(input) : urlDecodeText(input))
      ]);
}

Future<ToolResult> _runHex(Map<String, String> values) async {
  final bool encode = values['mode'] != 'decode';
  final String input = values['input'] ?? '';
  return ToolResult(
      title: encode ? 'Hex 编码完成' : 'Hex 解码完成',
      panels: <ToolPanel>[
        ToolPanel(
            title: '结果',
            text: encode ? hexEncodeText(input) : hexDecodeText(input))
      ]);
}

Future<ToolResult> _runDigest(Map<String, String> values) async {
  final String algorithm = values['algorithm'] ?? 'sha256';
  return ToolResult(title: '$algorithm 摘要完成', panels: <ToolPanel>[
    ToolPanel(title: '摘要', text: digestText(values['input'] ?? '', algorithm))
  ]);
}

Future<ToolResult> _runJwt(Map<String, String> values) async {
  final JwtDecodeResult result = decodeJwt(values['token'] ?? '');
  return ToolResult(
    title: 'JWT 已解码',
    summary: result.hasSignature ? '仅解码，不代表签名有效。' : '此 JWT 没有签名段。',
    panels: <ToolPanel>[
      ToolPanel(
          title: 'Header',
          text: const JsonEncoder.withIndent('  ').convert(result.header)),
      ToolPanel(
          title: 'Payload',
          text: const JsonEncoder.withIndent('  ').convert(result.payload)),
    ],
  );
}

Future<ToolResult> _runSubnetSplitter(Map<String, String> values) async {
  final int? prefix = int.tryParse(values['prefix']?.trim() ?? '');
  if (prefix == null) throw ToolException('error_prefix_integer');
  final List<SubnetInfo> subnets = splitSubnet(values['cidr'] ?? '', prefix);
  return ToolResult(
    title: '子网拆分完成',
    summary: '生成 ${subnets.length} 个 /$prefix 子网',
    rows: <ResultRow>[
      ResultRow('首个子网', '${subnets.first.network}/$prefix'),
      ResultRow('最后子网', '${subnets.last.network}/$prefix'),
      ResultRow('每段可用主机', '${subnets.first.hostCount}'),
    ],
    panels: <ToolPanel>[
      ToolPanel(
        title: '子网列表',
        text: subnets
            .map((SubnetInfo subnet) => '${subnet.network}/$prefix')
            .join('\n'),
      ),
    ],
  );
}

Future<ToolResult> _runRangeToCidr(Map<String, String> values) async {
  final List<String> cidrs =
      rangeToCidrs(values['start'] ?? '', values['end'] ?? '');
  return ToolResult(
    title: '范围转换完成',
    summary: '生成 ${cidrs.length} 个 CIDR',
    panels: <ToolPanel>[ToolPanel(title: 'CIDR 列表', text: cidrs.join('\n'))],
  );
}

Future<ToolResult> _runCidrAggregate(Map<String, String> values) async {
  final List<String> cidrs = aggregateCidrs(values['cidrs'] ?? '');
  return ToolResult(
    title: 'CIDR 聚合完成',
    summary: '聚合后 ${cidrs.length} 个网段',
    panels: <ToolPanel>[ToolPanel(title: '聚合结果', text: cidrs.join('\n'))],
  );
}

Future<ToolResult> _runIpConverter(Map<String, String> values) async {
  final IPv4Address address = IPv4Address.parse(values['ip'] ?? '');
  return ToolResult(
    title: 'IPv4 转换完成',
    rows: <ResultRow>[
      ResultRow('点分十进制', address.dotted),
      ResultRow('无符号整数', '${address.value}'),
      ResultRow('十六进制', '0x${ipv4Hex(address.dotted)}'),
      ResultRow('二进制', ipv4Binary(address.dotted)),
    ],
  );
}

Future<ToolResult> _runWildcardMask(Map<String, String> values) async {
  final int? prefix = int.tryParse(values['prefix']?.trim() ?? '');
  if (prefix == null) throw ToolException('error_prefix_integer');
  return ToolResult(
    title: '通配符掩码',
    rows: <ResultRow>[
      ResultRow('前缀', '/$prefix'),
      ResultRow('通配符掩码', wildcardMaskForPrefix(prefix)),
    ],
  );
}

Future<ToolResult> _runIpInspector(Map<String, String> values) async {
  final IpAddressInfo info = inspectIpAddress(values['ip'] ?? '');
  return ToolResult(
    title: '${info.type} 地址',
    rows: <ResultRow>[
      ResultRow('规范化地址', info.address),
      ResultRow('地址族', info.type),
      ResultRow('字节数', '${info.byteCount}'),
      ResultRow('原始字节', info.bytes),
    ],
  );
}

Future<ToolResult> _runMacNormalizer(Map<String, String> values) async {
  final String normalized = normalizeMac(values['mac'] ?? '');
  final String hex = normalized.replaceAll(':', '');
  return ToolResult(
    title: 'MAC 地址有效',
    rows: <ResultRow>[
      ResultRow('冒号格式', normalized),
      ResultRow('短横线格式', normalized.replaceAll(':', '-')),
      ResultRow('点分格式',
          '${hex.substring(0, 4)}.${hex.substring(4, 8)}.${hex.substring(8)}'),
    ],
  );
}

Future<ToolResult> _runDnsPropagation(Map<String, String> values) async {
  final List<DnsResolverResult> results = await _network.dnsPropagation(
    rawName: values['name'] ?? '',
    type: values['type'] ?? 'A',
  );
  final int successCount =
      results.where((DnsResolverResult item) => item.error == null).length;
  return ToolResult(
    title: 'DNS 解析器对比',
    summary: '$successCount/${results.length} 个解析器返回结果',
    rows: results
        .map((DnsResolverResult item) => ResultRow(
              item.resolver,
              item.error ??
                  (item.records.isEmpty ? '(无记录)' : item.records.join(', ')),
              mono: false,
            ))
        .toList(),
  );
}

Future<ToolResult> _runRdap(Map<String, String> values) async {
  final RdapResult result = await _network.rdapLookup(values['target'] ?? '');
  return ToolResult(
    title: 'RDAP 查询完成',
    rows: <ResultRow>[
      ResultRow('目标', result.target, mono: false),
      ResultRow('类型', result.kind),
      ResultRow('名称', result.name ?? '-'),
      ResultRow('句柄', result.handle ?? '-'),
      ResultRow('状态', result.status.isEmpty ? '-' : result.status.join(', '),
          mono: false),
      ResultRow('事件', result.events.isEmpty ? '-' : result.events.join('\n'),
          mono: false),
    ],
    panels: <ToolPanel>[ToolPanel(title: 'RDAP JSON', text: result.body)],
  );
}

Future<ToolResult> _runTlsInspector(Map<String, String> values) async {
  final TlsInfo info = await _network.inspectTls(
    rawHost: values['host'] ?? '',
    port: requirePort(values['port'] ?? '', fallback: 443),
  );
  return ToolResult(
    title: 'TLS 证书已读取',
    summary: '此工具为读取证书而接受无效证书，不代表证书可信。',
    rows: <ResultRow>[
      ResultRow('主机', '${info.host}:${info.port}'),
      ResultRow('Subject', info.subject, mono: false),
      ResultRow('Issuer', info.issuer, mono: false),
      ResultRow('生效时间', info.validFrom?.toIso8601String() ?? '-'),
      ResultRow('过期时间', info.validTo?.toIso8601String() ?? '-'),
      ResultRow('DER 大小', formatBytes(info.derLength)),
    ],
  );
}

Future<ToolResult> _runHttpStatus(Map<String, String> values) async {
  final int? code = int.tryParse(values['code']?.trim() ?? '');
  if (code == null || code < 100 || code > 599) {
    throw ToolException('error_http_status');
  }
  final String description = _httpStatusDescriptions[code] ?? '未收录的状态码';
  return ToolResult(
    title: 'HTTP $code',
    rows: <ResultRow>[
      ResultRow('类别', '${code ~/ 100}xx'),
      ResultRow('说明', description, mono: false),
      ResultRow('处理建议', _httpStatusAdvice(code), mono: false),
    ],
  );
}

Future<ToolResult> _runPortReference(Map<String, String> values) async {
  final int port = requirePort(values['port'] ?? '');
  final String? service = _commonPorts[port];
  return ToolResult(
    title: service == null ? '端口 $port' : '$port / $service',
    summary: service == null ? '本地参考表没有收录此端口' : '常见服务参考，不代表目标实际运行该服务。',
    rows: <ResultRow>[
      ResultRow('端口', '$port'),
      ResultRow('常见服务', service ?? '-'),
      ResultRow('传输', port == 53 ? 'TCP / UDP' : 'TCP'),
    ],
  );
}

Future<ToolResult> _runHeadersParser(Map<String, String> values) async {
  final Map<String, String> headers = parseHeaders(values['headers'] ?? '');
  return ToolResult(
    title: '请求头解析完成',
    summary: '共 ${headers.length} 个字段',
    rows: headers.entries
        .map((MapEntry<String, String> entry) =>
            ResultRow(entry.key, entry.value, mono: false))
        .toList(),
  );
}

Future<ToolResult> _runCurlBuilder(Map<String, String> values) async {
  final String method = (values['method'] ?? 'GET').toUpperCase();
  final String url = requireValue(values['url'] ?? '', field: 'URL');
  final Map<String, String> headers = parseHeaders(values['headers'] ?? '');
  final List<String> parts = <String>['curl', '-i', '-X', method];
  for (final MapEntry<String, String> entry in headers.entries) {
    parts.add('-H');
    parts.add(_shellQuote('${entry.key}: ${entry.value}'));
  }
  final String body = values['body'] ?? '';
  if (body.isNotEmpty) {
    parts.add('--data-raw');
    parts.add(_shellQuote(body));
  }
  parts.add(_shellQuote(url));
  return ToolResult(
      title: 'cURL 命令已生成',
      panels: <ToolPanel>[ToolPanel(title: '命令', text: parts.join(' '))]);
}

Future<ToolResult> _runIpMembership(Map<String, String> values) async {
  final String ip = requireValue(values['ip'] ?? '', field: 'IPv4 地址');
  final String cidr = requireValue(values['cidr'] ?? '', field: 'CIDR 网段');
  final Ipv4RangeInfo range = ipv4Range(cidr);
  final bool included = ipv4InCidr(ip, cidr);
  return ToolResult(
    title: included ? '地址属于网段' : '地址不属于网段',
    ok: included,
    rows: <ResultRow>[
      ResultRow('地址', IPv4Address.parse(ip).dotted),
      ResultRow('网段', cidr),
      ResultRow('网络地址', range.network),
      ResultRow('广播地址', range.broadcast),
    ],
  );
}

Future<ToolResult> _runIpRange(Map<String, String> values) async {
  final Ipv4RangeInfo range = ipv4Range(values['cidr'] ?? '');
  return ToolResult(
    title: 'IPv4 范围计算完成',
    rows: <ResultRow>[
      ResultRow('网络地址', range.network),
      ResultRow('广播地址', range.broadcast),
      ResultRow('首个主机', range.firstHost),
      ResultRow('最后主机', range.lastHost),
      ResultRow('可用主机数', '${range.hostCount}'),
    ],
  );
}

Future<ToolResult> _runReverseDns(Map<String, String> values) async {
  return ToolResult(
    title: '反向 DNS 名称已生成',
    rows: <ResultRow>[
      ResultRow('IP 地址', requireValue(values['ip'] ?? '', field: 'IP 地址')),
      ResultRow('PTR 名称', reverseDnsName(values['ip'] ?? '')),
    ],
  );
}

Future<ToolResult> _runDnsName(Map<String, String> values) async {
  final DnsNameInfo info = inspectDnsName(values['name'] ?? '');
  return ToolResult(
    title: 'DNS 名称有效',
    rows: <ResultRow>[
      ResultRow('规范化名称', info.name),
      ResultRow('标签数量', '${info.labels.length}'),
      ResultRow('完全限定名称', info.isFullyQualified ? '是' : '否'),
      ResultRow('标签', info.labels.join(' / '), mono: false),
    ],
  );
}

Future<ToolResult> _runQueryParser(Map<String, String> values) async {
  final List<QueryParameter> parameters =
      parseQueryString(values['query'] ?? '');
  return ToolResult(
    title: '查询字符串解析完成',
    summary: '${parameters.length} 个参数',
    rows: parameters
        .map((QueryParameter item) =>
            ResultRow(item.key, item.value, mono: false))
        .toList(),
  );
}

Future<ToolResult> _runQueryBuilder(Map<String, String> values) async {
  return ToolResult(
    title: '查询字符串已生成',
    panels: <ToolPanel>[
      ToolPanel(
          title: '结果', text: buildQueryString(values['parameters'] ?? '')),
    ],
  );
}

Future<ToolResult> _runHttpContentType(Map<String, String> values) async {
  final ContentTypeInfo info = inspectContentType(values['contentType'] ?? '');
  return ToolResult(
    title: 'Content-Type 解析完成',
    rows: <ResultRow>[
      ResultRow('媒体类型', info.mediaType),
      ResultRow('字符集', info.charset ?? '(未声明)'),
      ResultRow('参数数量', '${info.parameters.length}'),
    ],
    panels: <ToolPanel>[
      ToolPanel(
        title: '参数',
        text: info.parameters.isEmpty
            ? '(无)'
            : info.parameters
                .map((HeaderPair item) => '${item.name}=${item.value}')
                .join('\n'),
      ),
    ],
  );
}

Future<ToolResult> _runHttpCacheControl(Map<String, String> values) async {
  final List<HeaderPair> directives = parseCacheControl(values['header'] ?? '');
  return ToolResult(
    title: 'Cache-Control 解析完成',
    rows: directives
        .map((HeaderPair item) => ResultRow(
            item.name, item.value.isEmpty ? '(无值)' : item.value,
            mono: false))
        .toList(),
  );
}

Future<ToolResult> _runHttpDate(Map<String, String> values) async {
  final DateTime date = parseHttpDate(values['date'] ?? '');
  return ToolResult(
    title: 'HTTP 日期解析完成',
    rows: <ResultRow>[
      ResultRow('UTC ISO-8601', date.toIso8601String()),
      ResultRow('Unix 秒', '${date.millisecondsSinceEpoch ~/ 1000}'),
    ],
  );
}

Future<ToolResult> _runBasicAuth(Map<String, String> values) async {
  return ToolResult(
    title: 'Basic 认证头已生成',
    panels: <ToolPanel>[
      ToolPanel(
        title: 'Authorization',
        text:
            basicAuthHeader(values['username'] ?? '', values['password'] ?? ''),
      ),
    ],
  );
}

Future<ToolResult> _runTimestamp(Map<String, String> values) async {
  final TimestampInfo info = parseUnixTimestamp(values['timestamp'] ?? '');
  return ToolResult(
    title: '时间戳转换完成',
    rows: <ResultRow>[
      ResultRow('识别单位', info.unit),
      ResultRow('UTC ISO-8601', info.dateTime.toIso8601String()),
      ResultRow('Unix 秒', '${info.seconds}'),
      ResultRow('Unix 毫秒', '${info.milliseconds}'),
    ],
  );
}

Future<ToolResult> _runPrefixMask(Map<String, String> values) async {
  final MaskInfo info = maskFromPrefix(values['prefix'] ?? '');
  return ToolResult(
    title: '前缀转换完成',
    rows: <ResultRow>[
      ResultRow('前缀', '/${info.prefix}'),
      ResultRow('子网掩码', info.mask),
      ResultRow('通配符掩码', info.wildcard),
    ],
  );
}

Future<ToolResult> _runMaskPrefix(Map<String, String> values) async {
  final MaskInfo info = prefixFromMask(values['mask'] ?? '');
  return ToolResult(
    title: '子网掩码有效',
    rows: <ResultRow>[
      ResultRow('子网掩码', info.mask),
      ResultRow('前缀', '/${info.prefix}'),
      ResultRow('通配符掩码', info.wildcard),
    ],
  );
}

Future<ToolResult> _runPortRange(Map<String, String> values) async {
  final PortRangeInfo info = parsePortRange(values['ports'] ?? '');
  return ToolResult(
    title: '端口范围有效',
    rows: <ResultRow>[
      ResultRow('起始端口', '${info.start}'),
      ResultRow('结束端口', '${info.end}'),
      ResultRow('端口数量', '${info.count}'),
    ],
  );
}

Future<ToolResult> _runIpv4Classifier(Map<String, String> values) async {
  final Ipv4Classification info = classifyIpv4(values['ip'] ?? '');
  return ToolResult(
    title: 'IPv4 分类完成',
    rows: <ResultRow>[
      ResultRow('规范化地址', info.address),
      ResultRow('传统地址类', info.className),
      ResultRow('地址范围', info.scope, mono: false),
    ],
  );
}

Future<ToolResult> _runIpv4Scope(Map<String, String> values) async {
  final Ipv4Classification info = classifyIpv4(values['ip'] ?? '');
  return ToolResult(
    title: 'IPv4 地址范围已识别',
    rows: <ResultRow>[
      ResultRow('地址', info.address),
      ResultRow('范围', info.scope, mono: false),
    ],
  );
}

Future<ToolResult> _runCookieParser(Map<String, String> values) async {
  final List<HeaderPair> cookies = parseCookieHeader(values['cookie'] ?? '');
  return ToolResult(
    title: 'Cookie 解析完成',
    summary: '${cookies.length} 个 Cookie',
    rows: cookies
        .map((HeaderPair item) => ResultRow(item.name, item.value, mono: false))
        .toList(),
  );
}

Future<ToolResult> _runUrlJoin(Map<String, String> values) async {
  return ToolResult(
    title: 'URL 拼接完成',
    panels: <ToolPanel>[
      ToolPanel(
        title: '结果',
        text: joinHttpUrl(values['base'] ?? '', values['path'] ?? ''),
      ),
    ],
  );
}

Future<ToolResult> _runHttpMethod(Map<String, String> values) async {
  final String method = (values['method'] ?? '').trim().toUpperCase();
  const Set<String> methods = <String>{
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
    'TRACE',
  };
  if (!methods.contains(method)) throw ToolException('error_http_method');
  const Set<String> safe = <String>{'GET', 'HEAD', 'OPTIONS', 'TRACE'};
  const Set<String> idempotent = <String>{
    'GET',
    'HEAD',
    'PUT',
    'DELETE',
    'OPTIONS',
    'TRACE'
  };
  return ToolResult(
    title: '$method 方法参考',
    rows: <ResultRow>[
      ResultRow('安全方法', safe.contains(method) ? '是' : '否'),
      ResultRow('幂等方法', idempotent.contains(method) ? '是' : '否'),
      ResultRow('通常有请求体',
          <String>{'POST', 'PUT', 'PATCH'}.contains(method) ? '是' : '否'),
    ],
  );
}

Future<ToolResult> _runDnsLabel(Map<String, String> values) async {
  final DnsNameInfo info = inspectDnsName(values['label'] ?? '');
  if (info.labels.length != 1 || info.isFullyQualified) {
    throw ToolException('error_dns_single_label');
  }
  return ToolResult(
    title: 'DNS 标签有效',
    rows: <ResultRow>[
      ResultRow('规范化标签', info.labels.single),
      ResultRow('长度', '${info.labels.single.length}'),
    ],
  );
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _httpStatusAdvice(int code) {
  if (code >= 500) return '检查上游服务、应用日志、依赖和超时。';
  if (code >= 400) return '检查请求路径、参数、认证和权限。';
  if (code >= 300) return '检查 Location、缓存和重定向策略。';
  if (code >= 200) return '请求通常已成功，继续核对响应体和业务语义。';
  return '检查协议协商和客户端是否正确处理临时响应。';
}

const Map<int, String> _httpStatusDescriptions = <int, String>{
  100: 'Continue',
  101: 'Switching Protocols',
  200: 'OK',
  201: 'Created',
  202: 'Accepted',
  204: 'No Content',
  206: 'Partial Content',
  301: 'Moved Permanently',
  302: 'Found',
  304: 'Not Modified',
  307: 'Temporary Redirect',
  308: 'Permanent Redirect',
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  405: 'Method Not Allowed',
  408: 'Request Timeout',
  409: 'Conflict',
  413: 'Payload Too Large',
  429: 'Too Many Requests',
  500: 'Internal Server Error',
  501: 'Not Implemented',
  502: 'Bad Gateway',
  503: 'Service Unavailable',
  504: 'Gateway Timeout',
};

const Map<int, String> _commonPorts = <int, String>{
  20: 'FTP data',
  21: 'FTP',
  22: 'SSH',
  23: 'Telnet',
  25: 'SMTP',
  53: 'DNS',
  67: 'DHCP server',
  68: 'DHCP client',
  80: 'HTTP',
  110: 'POP3',
  123: 'NTP',
  143: 'IMAP',
  161: 'SNMP',
  389: 'LDAP',
  443: 'HTTPS',
  445: 'SMB',
  514: 'Syslog',
  587: 'SMTP submission',
  636: 'LDAPS',
  853: 'DNS over TLS',
  993: 'IMAPS',
  995: 'POP3S',
  1433: 'Microsoft SQL Server',
  1883: 'MQTT',
  3306: 'MySQL',
  3389: 'RDP',
  5432: 'PostgreSQL',
  6379: 'Redis',
  8080: 'HTTP alternate',
  8443: 'HTTPS alternate',
};

import 'package:flutter/material.dart';

import 'batch2_address_service.dart';
import 'batch2_models.dart';

/// The 13 address and subnet tools of the netrix port (batch 2).
///
/// Each entry copies `netrix/lib/core/registry.dart` verbatim: same id, same
/// Chinese/English titles, same description, same icon, same fields (ids,
/// labels, hints, defaults, keyboard type, option order) and the same runner
/// output rows.

final List<NetrixToolDefinition> batch2AddressTools = <NetrixToolDefinition>[
  NetrixToolDefinition(
    id: 'subnet-calculator',
    title: 'IPv4 子网计算',
    titleEn: 'IPv4 CIDR Calculator',
    description: '计算网络地址、掩码、广播地址和可用主机范围。',
    category: NetrixToolCategory.address,
    icon: Icons.account_tree_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(
        id: 'cidr',
        label: 'CIDR 地址',
        initialValue: '192.168.1.42/24',
      ),
    ],
    run: _runSubnet,
  ),
  NetrixToolDefinition(
    id: 'subnet-splitter',
    title: '子网拆分规划',
    titleEn: 'Subnet Splitter',
    description: '把一个 IPv4 CIDR 按新前缀拆成等大小子网，最多生成 256 段。',
    category: NetrixToolCategory.address,
    icon: Icons.call_split_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'cidr', label: '父网段', initialValue: '10.0.0.0/16'),
      NetrixToolField(
        id: 'prefix',
        label: '新前缀',
        initialValue: '24',
        keyboardType: TextInputType.number,
      ),
    ],
    run: _runSubnetSplitter,
  ),
  NetrixToolDefinition(
    id: 'range-to-cidr',
    title: 'IP 范围转 CIDR',
    titleEn: 'Range to CIDR',
    description: '把起止 IPv4 地址转换为不重叠的最小 CIDR 列表。',
    category: NetrixToolCategory.address,
    icon: Icons.swap_calls_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'start', label: '起始地址', initialValue: '192.168.1.10'),
      NetrixToolField(id: 'end', label: '结束地址', initialValue: '192.168.1.31'),
    ],
    run: _runRangeToCidr,
  ),
  NetrixToolDefinition(
    id: 'cidr-aggregate',
    title: 'CIDR 聚合',
    titleEn: 'CIDR Aggregator',
    description: '合并输入中连续且对齐的相邻网段，减少路由条目数量。',
    category: NetrixToolCategory.address,
    icon: Icons.merge_type_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(
        id: 'cidrs',
        label: 'CIDR 列表',
        type: NetrixToolFieldType.multiline,
        initialValue: '10.0.0.0/25\n10.0.0.128/25',
      ),
    ],
    run: _runCidrAggregate,
  ),
  NetrixToolDefinition(
    id: 'ip-converter',
    title: 'IPv4 进制转换',
    titleEn: 'IPv4 Converter',
    description: '查看 IPv4 的十进制整数、二进制和十六进制表示。',
    category: NetrixToolCategory.address,
    icon: Icons.calculate_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'ip', label: 'IPv4 地址', initialValue: '192.168.1.1'),
    ],
    run: _runIpConverter,
  ),
  NetrixToolDefinition(
    id: 'wildcard-mask',
    title: '通配符掩码',
    titleEn: 'Wildcard Mask',
    description: '根据 CIDR 前缀计算 ACL/OSPF 常用的反掩码。',
    category: NetrixToolCategory.address,
    icon: Icons.filter_alt_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(
        id: 'prefix',
        label: '前缀长度',
        initialValue: '24',
        keyboardType: TextInputType.number,
      ),
    ],
    run: _runWildcardMask,
  ),
  NetrixToolDefinition(
    id: 'ip-inspector',
    title: 'IPv4 / IPv6 查看',
    titleEn: 'IP Inspector',
    description: '识别地址族、规范化地址并查看原始字节。',
    category: NetrixToolCategory.address,
    icon: Icons.account_tree_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'ip', label: 'IP 地址', initialValue: '2001:db8::1'),
    ],
    run: _runIpInspector,
  ),
  NetrixToolDefinition(
    id: 'ip-membership',
    title: 'IPv4 网段归属',
    titleEn: 'IPv4 CIDR Membership',
    description: '判断 IPv4 地址是否属于指定 CIDR 网段。',
    category: NetrixToolCategory.address,
    icon: Icons.account_tree_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'ip', label: 'IPv4 地址', initialValue: '192.168.1.42'),
      NetrixToolField(id: 'cidr', label: 'CIDR 网段', initialValue: '192.168.1.0/24'),
    ],
    run: _runIpMembership,
  ),
  NetrixToolDefinition(
    id: 'ip-range',
    title: 'IPv4 地址范围',
    titleEn: 'IPv4 Range',
    description: '查看 CIDR 的网络、广播和首尾主机地址。',
    category: NetrixToolCategory.address,
    icon: Icons.swap_calls_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'cidr', label: 'CIDR 网段', initialValue: '10.0.0.0/24'),
    ],
    run: _runIpRange,
  ),
  NetrixToolDefinition(
    id: 'prefix-mask',
    title: '前缀转子网掩码',
    titleEn: 'Prefix to Netmask',
    description: '把 IPv4 CIDR 前缀转换为子网掩码和通配符掩码。',
    category: NetrixToolCategory.address,
    icon: Icons.filter_alt_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(
        id: 'prefix',
        label: '前缀长度',
        initialValue: '24',
        keyboardType: TextInputType.number,
      ),
    ],
    run: _runPrefixMask,
  ),
  NetrixToolDefinition(
    id: 'mask-prefix',
    title: '子网掩码转前缀',
    titleEn: 'Netmask to Prefix',
    description: '校验连续 IPv4 子网掩码并转换为 CIDR 前缀。',
    category: NetrixToolCategory.address,
    icon: Icons.compare_arrows_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'mask', label: '子网掩码', initialValue: '255.255.255.0'),
    ],
    run: _runMaskPrefix,
  ),
  NetrixToolDefinition(
    id: 'ipv4-classifier',
    title: 'IPv4 分类查看',
    titleEn: 'IPv4 Classifier',
    description: '查看 IPv4 的传统地址类和常见用途范围。',
    category: NetrixToolCategory.address,
    icon: Icons.category_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'ip', label: 'IPv4 地址', initialValue: '192.168.1.1'),
    ],
    run: _runIpv4Classifier,
  ),
  NetrixToolDefinition(
    id: 'ipv4-scope',
    title: 'IPv4 地址范围',
    titleEn: 'IPv4 Scope',
    description: '识别回环、私有、链路本地、组播和共享地址空间。',
    category: NetrixToolCategory.address,
    icon: Icons.public_outlined,
    fields: <NetrixToolField>[
      NetrixToolField(id: 'ip', label: 'IPv4 地址', initialValue: '10.0.0.1'),
    ],
    run: _runIpv4Scope,
  ),
];

Future<NetrixToolResult> _runSubnet(Map<String, String> values) async {
  final SubnetInfo info = calculateSubnet(values['cidr'] ?? '');
  return NetrixToolResult(
    title: '子网计算完成',
    rows: <NetrixResultRow>[
      NetrixResultRow('网络地址', info.network),
      NetrixResultRow('前缀长度', '/${info.prefix}'),
      NetrixResultRow('子网掩码', info.mask),
      NetrixResultRow('广播地址', info.broadcast),
      NetrixResultRow('首个主机', info.firstHost),
      NetrixResultRow('最后主机', info.lastHost),
      NetrixResultRow('可用主机数', '${info.hostCount}'),
    ],
  );
}

Future<NetrixToolResult> _runSubnetSplitter(Map<String, String> values) async {
  final int? prefix = int.tryParse(values['prefix']?.trim() ?? '');
  if (prefix == null) throw NetrixToolException('error_prefix_integer');
  final List<SubnetInfo> subnets = splitSubnet(values['cidr'] ?? '', prefix);
  return NetrixToolResult(
    title: '子网拆分完成',
    summary: '生成 ${subnets.length} 个 /$prefix 子网',
    rows: <NetrixResultRow>[
      NetrixResultRow('首个子网', '${subnets.first.network}/$prefix'),
      NetrixResultRow('最后子网', '${subnets.last.network}/$prefix'),
      NetrixResultRow('每段可用主机', '${subnets.first.hostCount}'),
    ],
    panels: <NetrixToolPanel>[
      NetrixToolPanel(
        title: '子网列表',
        text: subnets
            .map((SubnetInfo subnet) => '${subnet.network}/$prefix')
            .join('\n'),
      ),
    ],
  );
}

Future<NetrixToolResult> _runRangeToCidr(Map<String, String> values) async {
  final List<String> cidrs =
      rangeToCidrs(values['start'] ?? '', values['end'] ?? '');
  return NetrixToolResult(
    title: '范围转换完成',
    summary: '生成 ${cidrs.length} 个 CIDR',
    panels: <NetrixToolPanel>[
      NetrixToolPanel(title: 'CIDR 列表', text: cidrs.join('\n')),
    ],
  );
}

Future<NetrixToolResult> _runCidrAggregate(Map<String, String> values) async {
  final List<String> cidrs = aggregateCidrs(values['cidrs'] ?? '');
  return NetrixToolResult(
    title: 'CIDR 聚合完成',
    summary: '聚合后 ${cidrs.length} 个网段',
    panels: <NetrixToolPanel>[
      NetrixToolPanel(title: '聚合结果', text: cidrs.join('\n')),
    ],
  );
}

Future<NetrixToolResult> _runIpConverter(Map<String, String> values) async {
  final IPv4Address address = IPv4Address.parse(values['ip'] ?? '');
  return NetrixToolResult(
    title: 'IPv4 转换完成',
    rows: <NetrixResultRow>[
      NetrixResultRow('点分十进制', address.dotted),
      NetrixResultRow('无符号整数', '${address.value}'),
      NetrixResultRow('十六进制', '0x${ipv4Hex(address.dotted)}'),
      NetrixResultRow('二进制', ipv4Binary(address.dotted)),
    ],
  );
}

Future<NetrixToolResult> _runWildcardMask(Map<String, String> values) async {
  final int? prefix = int.tryParse(values['prefix']?.trim() ?? '');
  if (prefix == null) throw NetrixToolException('error_prefix_integer');
  return NetrixToolResult(
    title: '通配符掩码',
    rows: <NetrixResultRow>[
      NetrixResultRow('前缀', '/$prefix'),
      NetrixResultRow('通配符掩码', wildcardMaskForPrefix(prefix)),
    ],
  );
}

Future<NetrixToolResult> _runIpInspector(Map<String, String> values) async {
  final IpAddressInfo info = inspectIpAddress(values['ip'] ?? '');
  return NetrixToolResult(
    title: '${info.type} 地址',
    rows: <NetrixResultRow>[
      NetrixResultRow('规范化地址', info.address),
      NetrixResultRow('地址族', info.type),
      NetrixResultRow('字节数', '${info.byteCount}'),
      NetrixResultRow('原始字节', info.bytes),
    ],
  );
}

Future<NetrixToolResult> _runIpMembership(Map<String, String> values) async {
  final String ip = requireValue(values['ip'] ?? '', field: 'IPv4 地址');
  final String cidr = requireValue(values['cidr'] ?? '', field: 'CIDR 网段');
  final Ipv4RangeInfo range = ipv4Range(cidr);
  final bool included = ipv4InCidr(ip, cidr);
  return NetrixToolResult(
    title: included ? '地址属于网段' : '地址不属于网段',
    ok: included,
    rows: <NetrixResultRow>[
      NetrixResultRow('地址', IPv4Address.parse(ip).dotted),
      NetrixResultRow('网段', cidr),
      NetrixResultRow('网络地址', range.network),
      NetrixResultRow('广播地址', range.broadcast),
    ],
  );
}

Future<NetrixToolResult> _runIpRange(Map<String, String> values) async {
  final Ipv4RangeInfo range = ipv4Range(values['cidr'] ?? '');
  return NetrixToolResult(
    title: 'IPv4 范围计算完成',
    rows: <NetrixResultRow>[
      NetrixResultRow('网络地址', range.network),
      NetrixResultRow('广播地址', range.broadcast),
      NetrixResultRow('首个主机', range.firstHost),
      NetrixResultRow('最后主机', range.lastHost),
      NetrixResultRow('可用主机数', '${range.hostCount}'),
    ],
  );
}

Future<NetrixToolResult> _runPrefixMask(Map<String, String> values) async {
  final MaskInfo info = maskFromPrefix(values['prefix'] ?? '');
  return NetrixToolResult(
    title: '前缀转换完成',
    rows: <NetrixResultRow>[
      NetrixResultRow('前缀', '/${info.prefix}'),
      NetrixResultRow('子网掩码', info.mask),
      NetrixResultRow('通配符掩码', info.wildcard),
    ],
  );
}

Future<NetrixToolResult> _runMaskPrefix(Map<String, String> values) async {
  final MaskInfo info = prefixFromMask(values['mask'] ?? '');
  return NetrixToolResult(
    title: '子网掩码有效',
    rows: <NetrixResultRow>[
      NetrixResultRow('子网掩码', info.mask),
      NetrixResultRow('前缀', '/${info.prefix}'),
      NetrixResultRow('通配符掩码', info.wildcard),
    ],
  );
}

Future<NetrixToolResult> _runIpv4Classifier(Map<String, String> values) async {
  final Ipv4Classification info = classifyIpv4(values['ip'] ?? '');
  return NetrixToolResult(
    title: 'IPv4 分类完成',
    rows: <NetrixResultRow>[
      NetrixResultRow('规范化地址', info.address),
      NetrixResultRow('传统地址类', info.className),
      NetrixResultRow('地址范围', info.scope, mono: false),
    ],
  );
}

Future<NetrixToolResult> _runIpv4Scope(Map<String, String> values) async {
  final Ipv4Classification info = classifyIpv4(values['ip'] ?? '');
  return NetrixToolResult(
    title: 'IPv4 地址范围已识别',
    rows: <NetrixResultRow>[
      NetrixResultRow('地址', info.address),
      NetrixResultRow('范围', info.scope, mono: false),
    ],
  );
}

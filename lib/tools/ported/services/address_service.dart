import 'dart:io';

import '../models.dart';

class IPv4Address {
  const IPv4Address(this.value);

  final int value;

  factory IPv4Address.parse(String raw) {
    final List<String> parts = raw.trim().split('.');
    if (parts.length != 4) throw ToolException('error_ipv4_segments');
    int value = 0;
    for (final String part in parts) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) {
        throw ToolException('error_invalid_ipv4');
      }
      final int octet = int.parse(part);
      if (octet > 255) throw ToolException('error_ipv4_octet');
      value = (value << 8) | octet;
    }
    return IPv4Address(value);
  }

  String get dotted {
    return '${(value >> 24) & 255}.${(value >> 16) & 255}.'
        '${(value >> 8) & 255}.${value & 255}';
  }

  @override
  String toString() => dotted;
}

class SubnetInfo {
  const SubnetInfo({
    required this.input,
    required this.prefix,
    required this.network,
    required this.broadcast,
    required this.firstHost,
    required this.lastHost,
    required this.hostCount,
    required this.mask,
  });

  final String input;
  final int prefix;
  final String network;
  final String broadcast;
  final String firstHost;
  final String lastHost;
  final int hostCount;
  final String mask;
}

class CidrBlock {
  const CidrBlock({required this.network, required this.prefix});

  final IPv4Address network;
  final int prefix;

  int get size => 1 << (32 - prefix);
  int get broadcastValue => network.value + size - 1;
  String get notation => '${network.dotted}/$prefix';
}

class IpAddressInfo {
  const IpAddressInfo({
    required this.address,
    required this.type,
    required this.byteCount,
    required this.bytes,
  });

  final String address;
  final String type;
  final int byteCount;
  final String bytes;
}

CidrBlock parseCidr(String raw) {
  final String input = requireValue(raw, field: 'CIDR');
  final List<String> parts = input.split('/');
  if (parts.length != 2) throw ToolException('error_cidr_format');
  final IPv4Address address = IPv4Address.parse(parts[0]);
  final int? prefix = int.tryParse(parts[1]);
  if (prefix == null || prefix < 0 || prefix > 32) {
    throw ToolException('error_ipv4_prefix');
  }
  final int mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  return CidrBlock(network: IPv4Address(address.value & mask), prefix: prefix);
}

SubnetInfo calculateSubnet(String raw) {
  final CidrBlock block = parseCidr(raw);
  final int prefix = block.prefix;
  final int network = block.network.value;
  final int broadcast = block.broadcastValue;
  final int total = block.size;
  final int hostCount = prefix >= 31 ? total : total - 2;
  final int first = prefix >= 31 ? network : network + 1;
  final int last = prefix >= 31 ? broadcast : broadcast - 1;
  final int mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;

  return SubnetInfo(
    input: raw.trim(),
    prefix: prefix,
    network: IPv4Address(network).dotted,
    broadcast: IPv4Address(broadcast).dotted,
    firstHost: IPv4Address(first).dotted,
    lastHost: IPv4Address(last).dotted,
    hostCount: hostCount,
    mask: IPv4Address(mask).dotted,
  );
}

List<SubnetInfo> splitSubnet(String raw, int targetPrefix, {int limit = 256}) {
  final CidrBlock parent = parseCidr(raw);
  if (targetPrefix < parent.prefix || targetPrefix > 32) {
    throw ToolException('error_subnet_prefix_range');
  }
  final int count = 1 << (targetPrefix - parent.prefix);
  if (count > limit) throw ToolException('error_subnet_limit');
  final int size = 1 << (32 - targetPrefix);
  return List<SubnetInfo>.generate(
    count,
    (int index) => calculateSubnet(
      '${IPv4Address(parent.network.value + index * size).dotted}/$targetPrefix',
    ),
  );
}

String wildcardMaskForPrefix(int prefix) {
  if (prefix < 0 || prefix > 32) throw ToolException('error_ipv4_prefix');
  final int mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  return IPv4Address(~mask & 0xffffffff).dotted;
}

List<String> rangeToCidrs(String startRaw, String endRaw, {int limit = 256}) {
  final int start = IPv4Address.parse(startRaw).value;
  final int end = IPv4Address.parse(endRaw).value;
  if (start > end) throw ToolException('error_range_order');
  final List<String> result = <String>[];
  int current = start;
  while (current <= end) {
    int prefix = current == 0 ? 0 : 32 - _trailingZeroBits(current);
    while (prefix < 32) {
      final int size = 1 << (32 - prefix);
      if (current + size - 1 <= end) break;
      prefix++;
    }
    result.add('${IPv4Address(current).dotted}/$prefix');
    if (result.length > limit) throw ToolException('error_cidr_result_limit');
    current += 1 << (32 - prefix);
  }
  return result;
}

int _trailingZeroBits(int value) {
  int zeros = 0;
  int current = value;
  while ((current & 1) == 0) {
    zeros++;
    current >>= 1;
  }
  return zeros;
}

List<String> aggregateCidrs(String raw, {int limit = 256}) {
  final List<CidrBlock> blocks = raw
      .split(RegExp(r'[\s,]+'))
      .where((String item) => item.isNotEmpty)
      .map(parseCidr)
      .toList();
  if (blocks.isEmpty) throw ToolException('error_no_cidr');
  if (blocks.length > limit) throw ToolException('error_cidr_limit');
  blocks.sort(
      (CidrBlock a, CidrBlock b) => a.network.value.compareTo(b.network.value));
  bool changed = true;
  while (changed) {
    changed = false;
    for (int i = 0; i < blocks.length - 1; i++) {
      final CidrBlock left = blocks[i];
      final CidrBlock right = blocks[i + 1];
      final int size = left.size;
      final bool pair = left.prefix == right.prefix &&
          left.prefix > 0 &&
          right.network.value == left.network.value + size &&
          left.network.value % (size * 2) == 0;
      if (pair) {
        blocks[i] = CidrBlock(network: left.network, prefix: left.prefix - 1);
        blocks.removeAt(i + 1);
        changed = true;
        break;
      }
    }
  }
  return blocks.map((CidrBlock block) => block.notation).toList();
}

String ipv4Binary(String raw) {
  final int value = IPv4Address.parse(raw).value;
  return List<String>.generate(
      32, (int index) => ((value >> (31 - index)) & 1).toString()).join();
}

String ipv4Hex(String raw) =>
    IPv4Address.parse(raw).value.toRadixString(16).padLeft(8, '0');

IpAddressInfo inspectIpAddress(String raw) {
  final String input = requireValue(raw, field: 'IP 地址');
  final InternetAddress? parsed = InternetAddress.tryParse(input);
  if (parsed == null) throw ToolException('error_invalid_ip');
  final List<int> bytes = parsed.rawAddress;
  return IpAddressInfo(
    address: parsed.address,
    type: parsed.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6',
    byteCount: bytes.length,
    bytes: bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':'),
  );
}

String normalizeMac(String raw) {
  final String value = requireValue(raw, field: 'MAC 地址')
      .replaceAll(RegExp(r'[:.\-\s]'), '')
      .toLowerCase();
  if (value.length != 12 || !RegExp(r'^[0-9a-f]{12}$').hasMatch(value)) {
    throw ToolException('error_mac_format');
  }
  return List<String>.generate(
      6, (int index) => value.substring(index * 2, index * 2 + 2)).join(':');
}

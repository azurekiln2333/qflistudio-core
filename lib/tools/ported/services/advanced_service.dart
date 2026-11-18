import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'address_service.dart';

class Ipv4RangeInfo {
  const Ipv4RangeInfo({
    required this.network,
    required this.broadcast,
    required this.firstHost,
    required this.lastHost,
    required this.hostCount,
  });

  final String network;
  final String broadcast;
  final String firstHost;
  final String lastHost;
  final int hostCount;
}

class DnsNameInfo {
  const DnsNameInfo({
    required this.name,
    required this.labels,
    required this.isFullyQualified,
  });

  final String name;
  final List<String> labels;
  final bool isFullyQualified;
}

class QueryParameter {
  const QueryParameter(this.key, this.value);

  final String key;
  final String value;
}

class HeaderPair {
  const HeaderPair(this.name, this.value);

  final String name;
  final String value;
}

class ContentTypeInfo {
  const ContentTypeInfo({
    required this.mediaType,
    required this.parameters,
  });

  final String mediaType;
  final List<HeaderPair> parameters;

  String? get charset {
    for (final HeaderPair parameter in parameters) {
      if (parameter.name == 'charset') return parameter.value;
    }
    return null;
  }
}

class TimestampInfo {
  const TimestampInfo({
    required this.dateTime,
    required this.unit,
    required this.seconds,
    required this.milliseconds,
  });

  final DateTime dateTime;
  final String unit;
  final int seconds;
  final int milliseconds;
}

class MaskInfo {
  const MaskInfo({
    required this.prefix,
    required this.mask,
    required this.wildcard,
  });

  final int prefix;
  final String mask;
  final String wildcard;
}

class Ipv4Classification {
  const Ipv4Classification({
    required this.address,
    required this.className,
    required this.scope,
  });

  final String address;
  final String className;
  final String scope;
}

class PortRangeInfo {
  const PortRangeInfo({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;

  int get count => end - start + 1;
}

Ipv4RangeInfo ipv4Range(String raw) {
  final SubnetInfo subnet = calculateSubnet(raw);
  return Ipv4RangeInfo(
    network: subnet.network,
    broadcast: subnet.broadcast,
    firstHost: subnet.firstHost,
    lastHost: subnet.lastHost,
    hostCount: subnet.hostCount,
  );
}

bool ipv4InCidr(String ipRaw, String cidrRaw) {
  final int address = IPv4Address.parse(ipRaw).value;
  final CidrBlock block = parseCidr(cidrRaw);
  return address >= block.network.value && address <= block.broadcastValue;
}

String reverseDnsName(String raw) {
  final String input = requireValue(raw, field: 'IP 地址');
  final InternetAddress? address = InternetAddress.tryParse(input);
  if (address == null) throw ToolException('error_invalid_ip');
  if (address.type == InternetAddressType.IPv4) {
    return '${address.address.split('.').reversed.join('.')}.in-addr.arpa';
  }
  final String hex = address.rawAddress
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.split('').reversed.join('.')}.ip6.arpa';
}

DnsNameInfo inspectDnsName(String raw) {
  final String input = requireValue(raw, field: 'DNS 名称');
  final bool fullyQualified = input.endsWith('.');
  final String name =
      fullyQualified ? input.substring(0, input.length - 1) : input;
  if (name.isEmpty || name.length > 253) {
    throw ToolException('error_dns_name_length');
  }
  final List<String> labels = name.split('.');
  if (labels.length > 127) throw ToolException('error_dns_label_count');
  for (final String label in labels) {
    if (label.isEmpty ||
        label.length > 63 ||
        !RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$')
            .hasMatch(label)) {
      throw ToolException('error_dns_label_invalid');
    }
  }
  return DnsNameInfo(
    name: '${name.toLowerCase()}${fullyQualified ? '.' : ''}',
    labels: labels.map((String label) => label.toLowerCase()).toList(),
    isFullyQualified: fullyQualified,
  );
}

List<QueryParameter> parseQueryString(
  String raw, {
  int maxLength = 4096,
  int maxParameters = 128,
}) {
  String query = requireValue(raw, field: '查询字符串');
  if (query.startsWith('?')) query = query.substring(1);
  if (query.length > maxLength) throw ToolException('error_query_length');
  final List<QueryParameter> result = <QueryParameter>[];
  for (final String pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final int separator = pair.indexOf('=');
    final String encodedKey =
        separator < 0 ? pair : pair.substring(0, separator);
    final String encodedValue =
        separator < 0 ? '' : pair.substring(separator + 1);
    try {
      final String key = Uri.decodeComponent(encodedKey.replaceAll('+', ' '));
      final String value =
          Uri.decodeComponent(encodedValue.replaceAll('+', ' '));
      if (key.isEmpty) throw ToolException('error_query_key_required');
      result.add(QueryParameter(key, value));
    } on FormatException {
      throw ToolException('error_percent_encoding');
    } on ArgumentError {
      throw ToolException('error_percent_encoding');
    }
    if (result.length > maxParameters) {
      throw ToolException('error_query_parameter_limit');
    }
  }
  if (result.isEmpty) throw ToolException('error_no_query_parameters');
  return result;
}

String buildQueryString(
  String raw, {
  int maxLength = 4096,
  int maxParameters = 128,
}) {
  final String input = requireValue(raw, field: '查询参数');
  if (input.length > maxLength) throw ToolException('error_query_length');
  final List<QueryParameter> parameters = <QueryParameter>[];
  for (final String line in input.split(RegExp(r'[\r\n]+'))) {
    if (line.trim().isEmpty) continue;
    final int separator = line.indexOf('=');
    if (separator <= 0) throw ToolException('error_query_parameter_format');
    final String key =
        requireValue(line.substring(0, separator), field: '参数名称');
    final String value = line.substring(separator + 1);
    parameters.add(QueryParameter(key, value));
    if (parameters.length > maxParameters) {
      throw ToolException('error_query_parameter_limit');
    }
  }
  if (parameters.isEmpty) throw ToolException('error_no_query_parameters');
  return parameters
      .map((QueryParameter item) =>
          '${Uri.encodeComponent(item.key)}=${Uri.encodeComponent(item.value)}')
      .join('&');
}

ContentTypeInfo inspectContentType(String raw) {
  final String input = requireValue(raw, field: 'Content-Type');
  final List<String> parts = input.split(';');
  final String mediaType = parts.first.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$').hasMatch(mediaType)) {
    throw ToolException('error_content_type');
  }
  final List<HeaderPair> parameters =
      _parseDelimitedPairs(parts.skip(1), 'Content-Type');
  return ContentTypeInfo(mediaType: mediaType, parameters: parameters);
}

List<HeaderPair> parseCacheControl(String raw) {
  final String input = requireValue(raw, field: 'Cache-Control');
  if (input.length > 4096) throw ToolException('error_cache_control_length');
  final List<String> parts = input.split(',');
  if (parts.length > 32) throw ToolException('error_cache_control_limit');
  return parts.map((String part) {
    final String value = part.trim();
    if (value.isEmpty) throw ToolException('error_empty_directive');
    final int separator = value.indexOf('=');
    if (separator < 0) {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
        throw ToolException('error_directive_invalid');
      }
      return HeaderPair(value.toLowerCase(), '');
    }
    final String name = value.substring(0, separator).trim().toLowerCase();
    final String directiveValue = value.substring(separator + 1).trim();
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name) || directiveValue.isEmpty) {
      throw ToolException('error_directive_invalid');
    }
    return HeaderPair(name, _unquote(directiveValue));
  }).toList();
}

List<HeaderPair> parseCookieHeader(String raw) {
  final String input = requireValue(raw, field: 'Cookie');
  if (input.length > 4096) throw ToolException('error_cookie_length');
  final List<String> parts = input.split(';');
  if (parts.length > 64) throw ToolException('error_cookie_limit');
  return parts.map((String part) {
    final int separator = part.indexOf('=');
    if (separator <= 0) throw ToolException('error_cookie_format');
    final String name = part.substring(0, separator).trim();
    final String value = part.substring(separator + 1).trim();
    if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name)) {
      throw ToolException('error_cookie_name');
    }
    return HeaderPair(name, value);
  }).toList();
}

String basicAuthHeader(String username, String password) {
  final String user = requireValue(username, field: '用户名');
  if (user.contains(':')) throw ToolException('error_username_colon');
  final String secret = requireValue(password, field: '密码');
  if (user.length > 256 || secret.length > 256) {
    throw ToolException('error_credentials_length');
  }
  return 'Basic ${base64Encode(utf8.encode('$user:$secret'))}';
}

TimestampInfo parseUnixTimestamp(String raw) {
  final String input = requireValue(raw, field: '时间戳');
  final int? number = int.tryParse(input);
  if (number == null) throw ToolException('error_timestamp_integer');
  final bool milliseconds = number.abs() >= 100000000000;
  final int minimum = milliseconds ? -2208988800000 : -2208988800;
  final int maximum = milliseconds ? 4102444800000 : 4102444800;
  if (number < minimum || number > maximum) {
    throw ToolException('error_timestamp_range');
  }
  final int value = milliseconds ? number : number * 1000;
  final DateTime dateTime;
  try {
    dateTime = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  } on RangeError {
    throw ToolException('error_timestamp_conversion');
  }
  if (dateTime.year < 1900 || dateTime.year > 2100) {
    throw ToolException('error_timestamp_range');
  }
  return TimestampInfo(
    dateTime: dateTime,
    unit: milliseconds ? 'milliseconds' : 'seconds',
    seconds: dateTime.millisecondsSinceEpoch ~/ 1000,
    milliseconds: dateTime.millisecondsSinceEpoch,
  );
}

MaskInfo maskFromPrefix(String raw) {
  final int? prefix = int.tryParse(requireValue(raw, field: '前缀长度'));
  if (prefix == null || prefix < 0 || prefix > 32) {
    throw ToolException('error_ipv4_prefix');
  }
  return MaskInfo(
    prefix: prefix,
    mask: _maskForPrefix(prefix),
    wildcard: wildcardMaskForPrefix(prefix),
  );
}

MaskInfo prefixFromMask(String raw) {
  final int value = IPv4Address.parse(requireValue(raw, field: '子网掩码')).value;
  final int inverted = (~value) & 0xffffffff;
  if ((inverted & (inverted + 1)) != 0) {
    throw ToolException('error_non_contiguous_mask');
  }
  int hostBits = 0;
  int remaining = inverted;
  while (remaining > 0) {
    hostBits++;
    remaining >>= 1;
  }
  final int prefix = 32 - hostBits;
  return MaskInfo(
    prefix: prefix,
    mask: IPv4Address(value).dotted,
    wildcard: IPv4Address(inverted).dotted,
  );
}

PortRangeInfo parsePortRange(String raw) {
  final String input = requireValue(raw, field: '端口范围');
  final List<String> parts = input.split('-');
  if (parts.length > 2) throw ToolException('error_port_range_format');
  final int start = requirePort(parts.first);
  final int end = parts.length == 1 ? start : requirePort(parts.last);
  if (start > end) throw ToolException('error_port_range_order');
  if (end - start > 4095) throw ToolException('error_port_range_limit');
  return PortRangeInfo(start: start, end: end);
}

Ipv4Classification classifyIpv4(String raw) {
  final IPv4Address address =
      IPv4Address.parse(requireValue(raw, field: 'IPv4 地址'));
  final int first = (address.value >> 24) & 255;
  final String className = first < 128
      ? 'A'
      : first < 192
          ? 'B'
          : first < 224
              ? 'C'
              : first < 240
                  ? 'D'
                  : 'E';
  return Ipv4Classification(
    address: address.dotted,
    className: className,
    scope: _ipv4Scope(address.value),
  );
}

DateTime parseHttpDate(String raw) {
  final String input = requireValue(raw, field: 'HTTP 日期');
  try {
    return HttpDate.parse(input).toUtc();
  } on FormatException {
    throw ToolException('error_http_date');
  }
}

String joinHttpUrl(String base, String path) {
  final String baseValue = requireValue(base, field: '基础 URL');
  final String pathValue = requireValue(path, field: '路径');
  if (baseValue.length > 2048 || pathValue.length > 2048) {
    throw ToolException('error_url_length');
  }
  final Uri? baseUri = Uri.tryParse(baseValue);
  if (baseUri == null ||
      baseUri.host.isEmpty ||
      !<String>{'http', 'https'}.contains(baseUri.scheme.toLowerCase())) {
    throw ToolException('error_http_base_url');
  }
  final Uri? pathUri = Uri.tryParse(pathValue);
  if (pathUri == null) throw ToolException('error_path_format');
  return baseUri.resolve(pathUri.toString()).toString();
}

List<HeaderPair> _parseDelimitedPairs(Iterable<String> rawParts, String field) {
  if (rawParts.length > 16) throw ToolException('error_field_limit');
  return rawParts.map((String part) {
    final int separator = part.indexOf('=');
    if (separator <= 0) throw ToolException('error_field_format');
    final String name = part.substring(0, separator).trim().toLowerCase();
    final String value = part.substring(separator + 1).trim();
    if (!RegExp(r'^[a-z0-9!#$&^_.+-]+$').hasMatch(name) || value.isEmpty) {
      throw ToolException('error_field_invalid');
    }
    return HeaderPair(name, _unquote(value));
  }).toList();
}

String _unquote(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _maskForPrefix(int prefix) {
  final int mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  return IPv4Address(mask).dotted;
}

String _ipv4Scope(int value) {
  final int first = (value >> 24) & 255;
  final int second = (value >> 16) & 255;
  if (value == 0) return '未指定';
  if (first == 127) return '回环';
  if (first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168)) {
    return '私有地址';
  }
  if (first == 169 && second == 254) return '链路本地';
  if (first >= 224 && first <= 239) return '组播';
  if (first == 100 && second >= 64 && second <= 127) return '共享地址空间';
  if (first == 192 && second == 0) return '文档或协议保留';
  return '公网或其他';
}

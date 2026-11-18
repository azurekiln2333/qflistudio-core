import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models.dart';
import 'address_service.dart';

class TcpProbe {
  const TcpProbe(
      {required this.host,
      required this.port,
      required this.elapsed,
      this.address});

  final String host;
  final int port;
  final Duration elapsed;
  final String? address;
}

class PortProbe {
  const PortProbe(
      {required this.port, required this.open, required this.elapsed});

  final int port;
  final bool open;
  final Duration elapsed;
}

class HostProbe {
  const HostProbe({
    required this.host,
    required this.port,
    required this.open,
    required this.elapsed,
  });

  final String host;
  final int port;
  final bool open;
  final Duration elapsed;
}

class DnsRecordResult {
  const DnsRecordResult(
      {required this.name, required this.type, required this.records});

  final String name;
  final String type;
  final List<String> records;
}

class HttpResultData {
  const HttpResultData({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.reasonPhrase,
    required this.elapsed,
    required this.headers,
    required this.body,
    required this.truncated,
  });

  final String method;
  final String url;
  final int statusCode;
  final String? reasonPhrase;
  final Duration elapsed;
  final Map<String, String> headers;
  final String body;
  final bool truncated;
}

class LocalInterfaceInfo {
  const LocalInterfaceInfo({required this.name, required this.addresses});

  final String name;
  final List<String> addresses;

  List<String> get ipv4Addresses => _addressesOfType(InternetAddressType.IPv4);

  List<String> get ipv6Addresses => _addressesOfType(InternetAddressType.IPv6);

  List<String> _addressesOfType(InternetAddressType type) => addresses
      .where((String value) => InternetAddress.tryParse(value)?.type == type)
      .toList();
}

class DnsResolverResult {
  const DnsResolverResult({
    required this.resolver,
    required this.records,
    this.error,
  });

  final String resolver;
  final List<String> records;
  final String? error;
}

class RdapResult {
  const RdapResult({
    required this.target,
    required this.kind,
    required this.name,
    required this.handle,
    required this.status,
    required this.events,
    required this.body,
  });

  final String target;
  final String kind;
  final String? name;
  final String? handle;
  final List<String> status;
  final List<String> events;
  final String body;
}

class TlsInfo {
  const TlsInfo({
    required this.host,
    required this.port,
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.derLength,
  });

  final String host;
  final int port;
  final String subject;
  final String issuer;
  final DateTime? validFrom;
  final DateTime? validTo;
  final int derLength;
}

/// Network operations with bounded timeouts and user-facing failures.
class NetworkService {
  const NetworkService();

  Future<List<InternetAddress>> resolveHost(String rawHost) async {
    final String host = hostFromInput(rawHost);
    try {
      final List<InternetAddress> addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 8));
      final Map<String, InternetAddress> unique = <String, InternetAddress>{
        for (final InternetAddress address in addresses)
          address.address: address,
      };
      if (unique.isEmpty) throw ToolException('error_host_unresolved');
      return unique.values.toList()
        ..sort((InternetAddress a, InternetAddress b) =>
            a.address.compareTo(b.address));
    } on ToolException {
      rethrow;
    } on TimeoutException {
      throw ToolException('error_dns_timeout');
    } on SocketException {
      throw ToolException('error_dns_failed');
    }
  }

  Future<TcpProbe> tcpProbe(
      {required String rawHost, required int port}) async {
    final String host = hostFromInput(rawHost);
    final Stopwatch stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      return TcpProbe(
        host: host,
        port: port,
        elapsed: stopwatch.elapsed,
        address: socket.remoteAddress.address,
      );
    } on TimeoutException {
      throw ToolException('error_connection_timeout');
    } on SocketException {
      throw ToolException('error_connection_failed');
    } finally {
      stopwatch.stop();
      socket?.destroy();
    }
  }

  Future<PortProbe> checkPort(
      {required String rawHost, required int port}) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      await tcpProbe(rawHost: rawHost, port: port);
      return PortProbe(port: port, open: true, elapsed: stopwatch.elapsed);
    } on ToolException {
      return PortProbe(port: port, open: false, elapsed: stopwatch.elapsed);
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<PortProbe>> scanPorts(
      {required String rawHost, required List<int> ports}) async {
    if (ports.isEmpty || ports.length > 256) {
      throw ToolException('error_port_scan_limit');
    }
    final List<PortProbe> results = <PortProbe>[];
    for (int offset = 0; offset < ports.length; offset += 12) {
      final int end = (offset + 12).clamp(0, ports.length);
      final List<PortProbe> batch = await Future.wait(
        ports
            .sublist(offset, end)
            .map((int port) => checkPort(rawHost: rawHost, port: port)),
      );
      results.addAll(batch);
    }
    return results
      ..sort((PortProbe a, PortProbe b) => a.port.compareTo(b.port));
  }

  Future<List<HostProbe>> scanHosts({
    required String rawCidr,
    required List<int> ports,
  }) async {
    if (ports.isEmpty || ports.length > 16) {
      throw ToolException('error_host_port_limit');
    }
    final CidrBlock block = parseCidr(rawCidr);
    if (block.size > 256) {
      throw ToolException('error_host_limit');
    }
    if (!_isPrivateBlock(block)) {
      throw ToolException('error_private_network_only');
    }

    final int first =
        block.prefix >= 31 ? block.network.value : block.network.value + 1;
    final int last =
        block.prefix >= 31 ? block.broadcastValue : block.broadcastValue - 1;
    final List<String> hosts = <String>[
      for (int value = first; value <= last; value++) IPv4Address(value).dotted,
    ];
    final List<HostProbe> results = <HostProbe>[];
    for (int offset = 0; offset < hosts.length; offset += 12) {
      final int end = (offset + 12).clamp(0, hosts.length);
      final List<List<HostProbe>> batch = await Future.wait(
        hosts.sublist(offset, end).map(
          (String host) async {
            final List<HostProbe> hostResults = <HostProbe>[];
            for (final int port in ports) {
              final Stopwatch stopwatch = Stopwatch()..start();
              final PortProbe probe =
                  await checkPort(rawHost: host, port: port);
              stopwatch.stop();
              hostResults.add(
                HostProbe(
                  host: host,
                  port: port,
                  open: probe.open,
                  elapsed: stopwatch.elapsed,
                ),
              );
            }
            return hostResults;
          },
        ),
      );
      results.addAll(batch.expand((List<HostProbe> item) => item));
    }
    return results;
  }

  bool _isPrivateBlock(CidrBlock block) {
    final int value = block.network.value;
    final bool is10 = (value & 0xff000000) == 0x0a000000;
    final bool is172 = (value & 0xfff00000) == 0xac100000;
    final bool is192 = (value & 0xffff0000) == 0xc0a80000;
    return is10 || is172 || is192;
  }

  Future<DnsRecordResult> dnsOverHttps(
      {required String rawName, required String type}) async {
    final String name = requireHost(rawName, field: '域名');
    final String recordType = type.toUpperCase();
    const Set<String> supported = <String>{
      'A',
      'AAAA',
      'CNAME',
      'MX',
      'NS',
      'TXT',
      'PTR'
    };
    if (!supported.contains(recordType)) {
      throw ToolException('error_dns_record_type');
    }
    final Uri uri =
        Uri.https('cloudflare-dns.com', '/dns-query', <String, String>{
      'name': name,
      'type': recordType,
    });
    final http.Client client = http.Client();
    try {
      final http.Response response =
          await client.get(uri, headers: <String, String>{
        'accept': 'application/dns-json',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw ToolException('error_dns_http');
      }
      if (response.body.length > 256 * 1024) {
        throw ToolException('error_dns_response_large');
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw ToolException('error_dns_response_format');
      }
      final List<String> records = <String>[];
      final Object? answer = decoded['Answer'];
      if (answer is List<Object?>) {
        for (final Object? item in answer) {
          if (item is Map<String, dynamic> && item['data'] is String) {
            records.add(item['data'] as String);
          }
        }
      }
      return DnsRecordResult(name: name, type: recordType, records: records);
    } on TimeoutException {
      throw ToolException('error_dns_timeout');
    } on FormatException {
      throw ToolException('error_dns_json');
    } on SocketException {
      throw ToolException('error_dns_failed');
    } finally {
      client.close();
    }
  }

  Future<String> publicIp() async {
    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .get(Uri.https(
              'api.ipify.org', '/', <String, String>{'format': 'json'}))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw ToolException('error_public_ip_http');
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ip'] is! String) {
        throw ToolException('error_public_ip_format');
      }
      return decoded['ip'] as String;
    } on TimeoutException {
      throw ToolException('error_public_ip_timeout');
    } on FormatException {
      throw ToolException('error_public_ip_json');
    } on SocketException {
      throw ToolException('error_public_ip_failed');
    } finally {
      client.close();
    }
  }

  Future<List<DnsResolverResult>> dnsPropagation({
    required String rawName,
    required String type,
  }) async {
    final String name = requireHost(rawName, field: '域名');
    final String recordType = type.toUpperCase();
    const Map<String, String> resolvers = <String, String>{
      'Cloudflare': 'cloudflare-dns.com',
      'Google': 'dns.google',
      'AdGuard': 'dns.adguard-dns.com',
    };
    final http.Client client = http.Client();
    try {
      return await Future.wait(
        resolvers.entries.map(
          (MapEntry<String, String> entry) => _queryResolver(
            client,
            label: entry.key,
            host: entry.value,
            name: name,
            type: recordType,
          ),
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<DnsResolverResult> _queryResolver(
    http.Client client, {
    required String label,
    required String host,
    required String name,
    required String type,
  }) async {
    try {
      final Uri uri = Uri.https(host, '/dns-query', <String, String>{
        'name': name,
        'type': type,
      });
      final http.Response response =
          await client.get(uri, headers: <String, String>{
        'accept': 'application/dns-json',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return DnsResolverResult(
          resolver: label,
          records: const <String>[],
          error: 'HTTP ${response.statusCode}',
        );
      }
      if (response.body.length > 256 * 1024) {
        return DnsResolverResult(
            resolver: label, records: const <String>[], error: '响应过大');
      }
      final Object? decoded = jsonDecode(response.body);
      final List<String> records = <String>[];
      if (decoded is Map<String, dynamic> &&
          decoded['Answer'] is List<Object?>) {
        for (final Object? item in decoded['Answer'] as List<Object?>) {
          if (item is Map<String, dynamic> && item['data'] is String) {
            records.add(item['data'] as String);
          }
        }
      }
      return DnsResolverResult(resolver: label, records: records);
    } on TimeoutException {
      return DnsResolverResult(
          resolver: label, records: const <String>[], error: '查询超时');
    } on Object catch (error) {
      return DnsResolverResult(
          resolver: label, records: const <String>[], error: error.toString());
    }
  }

  Future<RdapResult> rdapLookup(String rawTarget) async {
    final String target = requireValue(rawTarget, field: 'IP 或域名');
    final InternetAddress? ip = InternetAddress.tryParse(target);
    final String kind = ip == null ? 'domain' : 'ip';
    final Uri uri =
        Uri.https('rdap.org', '/$kind/${Uri.encodeComponent(target)}');
    final http.Client client = http.Client();
    try {
      final http.Response response =
          await client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ToolException('error_rdap_http');
      }
      if (response.body.length > 512 * 1024) {
        throw ToolException('error_rdap_response_large');
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw ToolException('error_rdap_response_format');
      }
      final List<String> status = decoded['status'] is List<Object?>
          ? (decoded['status'] as List<Object?>).whereType<String>().toList()
          : <String>[];
      final List<String> events = <String>[];
      if (decoded['events'] is List<Object?>) {
        for (final Object? item in decoded['events'] as List<Object?>) {
          if (item is Map<String, dynamic>) {
            events.add(
                '${item['eventAction'] ?? 'event'}: ${item['eventDate'] ?? '-'}');
          }
        }
      }
      return RdapResult(
        target: target,
        kind: kind,
        name: decoded['name'] as String?,
        handle: decoded['handle'] as String?,
        status: status,
        events: events,
        body: const JsonEncoder.withIndent('  ').convert(decoded),
      );
    } on TimeoutException {
      throw ToolException('error_rdap_timeout');
    } on FormatException {
      throw ToolException('error_rdap_json');
    } on SocketException {
      throw ToolException('error_rdap_failed');
    } finally {
      client.close();
    }
  }

  Future<TlsInfo> inspectTls(
      {required String rawHost, required int port}) async {
    final String host = hostFromInput(rawHost);
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
        onBadCertificate: (_) => true,
      );
      final X509Certificate? certificate = socket.peerCertificate;
      if (certificate == null) throw ToolException('error_tls_certificate');
      return TlsInfo(
        host: host,
        port: port,
        subject: certificate.subject,
        issuer: certificate.issuer,
        validFrom: certificate.startValidity,
        validTo: certificate.endValidity,
        derLength: certificate.der.length,
      );
    } on TimeoutException {
      throw ToolException('error_tls_timeout');
    } on SocketException {
      throw ToolException('error_tls_failed');
    } finally {
      await socket?.close();
    }
  }

  Future<List<LocalInterfaceInfo>> localInterfaces() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: true,
        includeLinkLocal: true,
      );
      return interfaces
          .map((NetworkInterface item) => LocalInterfaceInfo(
                name: item.name,
                addresses: item.addresses
                    .map((InternetAddress address) => address.address)
                    .toList(),
              ))
          .toList();
    } on SocketException {
      throw ToolException('error_local_interfaces');
    }
  }

  Future<HttpResultData> httpRequest({
    required String method,
    required String rawUrl,
    String rawHeaders = '',
    String body = '',
  }) async {
    final Uri? uri = Uri.tryParse(requireValue(rawUrl, field: 'URL'));
    if (uri == null || !<String>{'http', 'https'}.contains(uri.scheme)) {
      throw ToolException('error_http_url');
    }
    final String normalizedMethod = method.toUpperCase();
    const Set<String> methods = <String>{
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'HEAD'
    };
    if (!methods.contains(normalizedMethod)) {
      throw ToolException('error_http_method');
    }
    final Map<String, String> headers = parseHeaders(rawHeaders);
    if (body.length > 1024 * 1024) throw ToolException('error_http_body');
    final http.Client client = http.Client();
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final http.Request request = http.Request(normalizedMethod, uri)
        ..headers.addAll(headers)
        ..body = body;
      final http.StreamedResponse response =
          await client.send(request).timeout(const Duration(seconds: 15));
      final List<int> bytes = <int>[];
      bool truncated = false;
      await for (final List<int> chunk in response.stream) {
        final int remaining = 256 * 1024 - bytes.length;
        if (remaining <= 0) {
          truncated = true;
          break;
        }
        if (chunk.length > remaining) {
          bytes.addAll(chunk.take(remaining));
          truncated = true;
          break;
        }
        bytes.addAll(chunk);
      }
      return HttpResultData(
        method: normalizedMethod,
        url: uri.toString(),
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        elapsed: stopwatch.elapsed,
        headers: response.headers,
        body: utf8.decode(bytes, allowMalformed: true),
        truncated: truncated,
      );
    } on TimeoutException {
      throw ToolException('error_http_timeout');
    } on SocketException {
      throw ToolException('error_http_failed');
    } finally {
      stopwatch.stop();
      client.close();
    }
  }

  Future<String> webSocketProbe(
      {required String rawUrl, String message = ''}) async {
    final Uri? uri = Uri.tryParse(requireValue(rawUrl, field: 'WebSocket URL'));
    if (uri == null || !<String>{'ws', 'wss'}.contains(uri.scheme)) {
      throw ToolException('error_websocket_url');
    }
    WebSocketChannel? channel;
    try {
      final WebSocketChannel connected = WebSocketChannel.connect(uri);
      channel = connected;
      await connected.ready.timeout(const Duration(seconds: 8));
      if (message.isNotEmpty) connected.sink.add(message);
      final Object? response =
          await connected.stream.first.timeout(const Duration(seconds: 8));
      return response?.toString() ?? '(空消息)';
    } on TimeoutException {
      throw ToolException('error_websocket_timeout');
    } on Object {
      throw ToolException('error_websocket_failed');
    } finally {
      await channel?.sink.close();
    }
  }
}

Map<String, String> parseHeaders(String raw) {
  final Map<String, String> headers = <String, String>{};
  for (final String line in raw.split('\n')) {
    final String value = line.trim();
    if (value.isEmpty) continue;
    final int separator = value.indexOf(':');
    if (separator <= 0) throw ToolException('error_header_format');
    final String name = value.substring(0, separator).trim();
    final String content = value.substring(separator + 1).trim();
    if (name.isEmpty || content.isEmpty) {
      throw ToolException('error_header_required');
    }
    headers[name] = content;
  }
  return headers;
}

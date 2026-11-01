/// 联网检索工具：`web_search` 与 `web_fetch`。
///
/// 优先走 [ApiClient] 的中转接口；中转未部署（404）或不可用时，
/// 设备端直连搜索源/目标站点兜底，摘要上标明“直连”。
/// 两条链路共用同一套解析、SSRF 防护与大小、超时上限。
/// 离线专属产品在构造请求前就被拒绝。工具结果只作为模型反馈，
/// 从不伪造成功，也不把网页内容当成本地文件。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/api_client.dart';
import '../services/studio_profile.dart';
import 'vibe_tools.dart';

/// 联网工具名集合；控制器据此决定工具卡片文案。
const Set<String> kVibeWebToolNames = {'web_search', 'web_fetch'};

/// 单次检索返回条数上限，避免把长列表塞回模型上下文。
const int kVibeWebMaxResults = 8;

/// `web_fetch` 保留的正文上限（UTF-16 字符）。
const int kVibeWebMaxFetchChars = 20000;

/// 直连搜索源：与服务端同一个 Bing RSS 端点。
const String kVibeDirectSearchEndpoint = 'https://www.bing.com/search';

/// 直连抓取的响应体上限（字节），与服务端一致。
const int kVibeWebMaxBodyBytes = 512 * 1024;

/// 直连请求总超时，与服务端一致。
const Duration kVibeWebTimeout = Duration(seconds: 15);

/// 直连最多跟随的跳转次数，与服务端一致。
/// 直连最多跟随的跳转次数。fetch 和 search 共用同一预算。
const int kVibeWebMaxRedirects = 3;

/// Bing 拒绝默认脚本 UA，直连也要带常规浏览器 UA。
const String _browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

/// 只接受这些内容类型，避免把二进制当正文解析。
const Set<String> _allowedContentTypes = {
  'text/html',
  'text/plain',
  'application/xhtml+xml',
};

/// 当前产品是否允许联网工具。
///
/// 只有明确标记为离线专属时才禁用；未设置档位（根工程）保持可用。
bool get vibeWebToolsAvailable => !offlineOnlyProduct();

/// 离线专属产品的判定，与 `ApiClient._requireOnline` 同一真相源。
bool offlineOnlyProduct() => StudioProfile.current?.offlineOnly == true;

/// 一次联网工具的真实结果。
class VibeWebToolResult {
  const VibeWebToolResult({
    required this.ok,
    required this.summary,
    required this.modelText,
    this.direct = false,
  });

  /// 失败时也返回模型可读文本，让模型能改用别的办法。
  final bool ok;

  /// 工具卡片上的一行摘要；直连兜底时带“直连”标注。
  final String summary;

  /// 回传给模型的内容。
  final String modelText;

  /// 是否由设备端直连完成（中转不可用时的兜底）。
  final bool direct;

  VibeWebToolResult.failure(String code, String message, {this.direct = false})
    : ok = false,
      summary = message,
      modelText = 'error($code): $message';
}

/// OpenAI 兼容工具定义，与 [vibeToolSpecs] 同形状，可直接拼接。
List<Map<String, dynamic>> vibeWebToolSpecs() => [
  {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description':
          '在互联网上搜索资料，返回标题、链接和摘要。需要外部事实、最新信息或引用来源时使用。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索关键词，可为中文或英文'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'web_fetch',
      'description':
          '抓取一个公开网页并返回去掉标签的正文。用于阅读搜索结果里的具体页面。',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': '要以 http 或 https 开头的完整网址'},
        },
        'required': ['url'],
        'additionalProperties': false,
      },
    },
  },
];

/// 是否为联网工具名。
bool isVibeWebTool(String name) => kVibeWebToolNames.contains(name);

/// 执行一次联网工具。
///
/// [name] 不是联网工具时返回 null，调用方继续走本地工具分支。
/// 所有失败都以 [VibeWebToolResult.failure] 返回，不抛出异常。
Future<VibeWebToolResult?> executeVibeWebTool({
  required String name,
  required Map<String, dynamic> arguments,
  required ApiClient api,
  required String token,
  bool Function()? onlineAllowed,
  http.Client? directClient,
  bool allowDirectFallback = true,
}) async {
  if (!isVibeWebTool(name)) return null;
  // 产品开关与 offlineOnly 档位任一为假都在本地拒绝：
  // 不依赖 ApiClient 的策略反抛，那样错误码会变成泛化的 network。
  if (onlineAllowed?.call() == false || offlineOnlyProduct()) {
    return VibeWebToolResult.failure('OFFLINE_ONLY', '当前产品为离线模式，不能访问网络');
  }
  if (token.isEmpty) {
    return VibeWebToolResult.failure('auth', '需要登录后才能使用联网工具');
  }
  final validation = _validateArguments(name, arguments);
  if (validation != null) return validation;

  String? relayMessage;
  try {
    return switch (name) {
      'web_search' => await _search(arguments, api, token),
      _ => await _fetch(arguments, api, token),
    };
  } on ApiException catch (error) {
    // 策略拒绝必须保留原错误码，便于控制器区分“不能上网”和“网络故障”。
    if (error.details['code'] == 'OFFLINE_ONLY') {
      return VibeWebToolResult.failure('OFFLINE_ONLY', error.message);
    }
    if (!_isRelayUnavailable(error) || !allowDirectFallback) {
      return VibeWebToolResult.failure('network', error.message);
    }
    relayMessage = error.message;
  }

  // 中转不可用：设备端直连，沿用同一套解析与防护。
  final client = directClient ?? http.Client();
  final owned = directClient == null;
  try {
    return switch (name) {
      'web_search' => await _directSearch(
        arguments['query'] as String,
        client,
        relayMessage,
      ),
      _ => await _directFetch(
        Uri.parse(arguments['url'] as String),
        client,
        relayMessage,
      ),
    };
  } on _DirectFailure catch (error) {
    return VibeWebToolResult.failure(error.code, error.message, direct: true);
  } finally {
    if (owned) client.close();
  }
}

/// 中转是否“不可用”而不是“业务拒绝”。
///
/// 404 = 端点未部署，5xx = 服务故障，无状态码 = 根本没连上。
/// 429、401、400 是明确的业务答复，直连也得不到不同结果，因此不回退。
bool _isRelayUnavailable(ApiException error) {
  final status = error.statusCode;
  if (status == null) return true;
  return status == 404 || status >= 500;
}

/// 参数校验；返回 null 表示通过。
VibeWebToolResult? _validateArguments(
  String name,
  Map<String, dynamic> arguments,
) {
  if (name == 'web_search') {
    final query = arguments['query'];
    if (query is! String || query.trim().isEmpty) {
      return VibeWebToolResult.failure('error', 'query 必须是非空字符串');
    }
    if (query.length > 200) {
      return VibeWebToolResult.failure('error', 'query 超过 200 字符');
    }
    return null;
  }
  final raw = arguments['url'];
  if (raw is! String || raw.trim().isEmpty) {
    return VibeWebToolResult.failure('error', 'url 必须是非空字符串');
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasAuthority) {
    return VibeWebToolResult.failure('error', 'url 不是有效网址');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return VibeWebToolResult.failure('ssrf', '只允许 http 或 https 网址');
  }
  if (uri.userInfo.isNotEmpty) {
    return VibeWebToolResult.failure('ssrf', '网址不能包含用户名或密码');
  }
  // 中转侧还有一层校验；这里先挡掉明显的内网地址，省一次往返。
  if (_isBlockedAddress(uri.host)) {
    return VibeWebToolResult.failure('ssrf', '拒绝访问本机或内网地址');
  }
  return null;
}

Future<VibeWebToolResult> _search(
  Map<String, dynamic> arguments,
  ApiClient api,
  String token,
) async {
  final query = arguments['query'];
  if (query is! String || query.trim().isEmpty) {
    return VibeWebToolResult.failure('error', 'query 必须是非空字符串');
  }
  if (query.length > 200) {
    return VibeWebToolResult.failure('error', 'query 超过 200 字符');
  }
  final data = await api.aiWebSearch(
    token,
    query.trim(),
    limit: kVibeWebMaxResults,
  );
  final results = data['results'];
  if (results is! List || results.isEmpty) {
    return VibeWebToolResult(
      ok: true,
      summary: '没有结果',
      modelText: '没有找到相关结果，可以换关键词再试。',
    );
  }
  final lines = <String>[];
  var index = 0;
  for (final item in results) {
    if (item is! Map) continue;
    final title = item['title'] is String ? item['title'] as String : '';
    final url = item['url'] is String ? item['url'] as String : '';
    final snippet = item['snippet'] is String
        ? item['snippet'] as String
        : '';
    if (url.isEmpty) continue;
    index++;
    lines.add(
      '$index. ${title.isEmpty ? url : title}\n'
      '   $url\n'
      '${snippet.isEmpty ? '' : '   $snippet\n'}',
    );
    if (index >= kVibeWebMaxResults) break;
  }
  if (lines.isEmpty) {
    return const VibeWebToolResult(
      ok: true,
      summary: '没有可用结果',
      modelText: '没有找到可直接引用的结果。',
    );
  }
  return VibeWebToolResult(
    ok: true,
    summary: '$index 条结果',
    modelText: '搜索结果（引用时请给出链接）：\n${lines.join()}',
  );
}

Future<VibeWebToolResult> _fetch(
  Map<String, dynamic> arguments,
  ApiClient api,
  String token,
) async {
  final raw = arguments['url'];
  if (raw is! String || raw.trim().isEmpty) {
    return VibeWebToolResult.failure('error', 'url 必须是非空字符串');
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasAuthority) {
    return VibeWebToolResult.failure('error', 'url 不是有效网址');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return VibeWebToolResult.failure('ssrf', '只允许 http 或 https 网址');
  }
  if (uri.userInfo.isNotEmpty) {
    return VibeWebToolResult.failure('ssrf', '网址不能包含用户名或密码');
  }
  // 中转侧还有一层校验；这里先挡掉明显的内网地址，省一次往返。
  if (_isBlockedAddress(uri.host)) {
    return VibeWebToolResult.failure('ssrf', '拒绝访问本机或内网地址');
  }
  final data = await api.aiWebFetch(token, uri.toString());
  final text = data['text'] is String ? data['text'] as String : '';
  final title = data['title'] is String ? data['title'] as String : '';
  if (text.trim().isEmpty) {
    return VibeWebToolResult(
      ok: true,
      summary: '页面没有正文',
      modelText: '抓取成功，但没有提取到正文：$uri',
    );
  }
  final bounded = text.length > kVibeWebMaxFetchChars
      ? '${text.substring(0, kVibeWebMaxFetchChars)}\n…（已截断）'
      : text;
  final truncated = data['truncated'] == true;
  return VibeWebToolResult(
    ok: true,
    summary: '${bounded.length} 字符${truncated ? '（已截断）' : ''}',
    modelText:
        '网页：${title.isEmpty ? uri.toString() : title}\n'
        '${uri.toString()}\n\n$bounded',
  );
}

/// 本机、私网、链路本地与保留地址的快速判断。
///
/// 与中转侧的完整校验互补：这里只挡字面量，不发起 DNS 解析。
@visibleForTesting
bool isBlockedFetchHost(String host) => _isBlockedAddress(host);

bool _isBlockedAddress(String host) {
  var value = host.trim().toLowerCase();
  if (value.startsWith('[') && value.endsWith(']')) {
    value = value.substring(1, value.length - 1);
  }
  if (value.isEmpty) return true;
  if (value == 'localhost' || value.endsWith('.localhost')) return true;
  final address = InternetAddress.tryParse(value);
  if (address == null) return false;
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  return switch (address.type) {
    InternetAddressType.IPv4 => _isBlockedV4(address.rawAddress),
    InternetAddressType.IPv6 => _isBlockedV6(address.rawAddress),
    _ => true,
  };
}

bool _isBlockedV4(List<int> bytes) {
  if (bytes.length != 4) return true;
  final a = bytes[0];
  final b = bytes[1];
  if (a == 0 || a == 10 || a == 127) return true;
  if (a == 169 && b == 254) return true; // 链路本地
  if (a == 172 && b >= 16 && b <= 31) return true; // 私网
  if (a == 192 && b == 168) return true; // 私网
  if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT
  if (a >= 224) return true; // 组播与保留
  return false;
}

bool _isBlockedV6(List<int> bytes) {
  if (bytes.length != 16) return true;
  // IPv4 映射地址 ::ffff:a.b.c.d 按 IPv4 规则判断。
  final mapped =
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (mapped) return _isBlockedV4(bytes.sublist(12));
  final unspecified = bytes.every((byte) => byte == 0);
  if (unspecified) return true;
  // fc00::/7 唯一本地地址。
  if ((bytes[0] & 0xfe) == 0xfc) return true;
  // fe80::/10 链路本地。
  if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;
  // ff00::/8 组播。
  if (bytes[0] == 0xff) return true;
  return false;
}

/// 直连搜索入口：失败时补上中转原因，便于定位是哪条链路没通。
Future<VibeWebToolResult> _directSearch(
  String query,
  http.Client client,
  String relayMessage,
) async {
  try {
    return await _directSearchImpl(query.trim(), client);
  } on _DirectFailure catch (error) {
    throw _DirectFailure(
      error.code,
      '直连也失败：${error.message}（中转：$relayMessage）',
    );
  }
}

/// 直连抓取入口，同上。
Future<VibeWebToolResult> _directFetch(
  Uri uri,
  http.Client client,
  String relayMessage,
) async {
  try {
    return await _directFetchImpl(uri, client);
  } on _DirectFailure catch (error) {
    throw _DirectFailure(
      error.code,
      '直连也失败：${error.message}（中转：$relayMessage）',
    );
  }
}

/// 直连跟随跳转的最大跳数。上一跳不算作一次跳转。
///
/// 与 [kVibeWebMaxRedirects] 同值，保留独立名字便于搜索源单独收紧。
const int kVibeDirectMaxRedirects = kVibeWebMaxRedirects;

/// 直连搜索：请求 Bing RSS 并解析，规则与服务端 `web-search.js` 一致。
Future<VibeWebToolResult> _directSearchImpl(
  String query,
  http.Client client,
) async {
  final url = Uri.parse(kVibeDirectSearchEndpoint).replace(
    queryParameters: {
      'q': query,
      'format': 'rss',
      'count': '$kVibeWebMaxResults',
    },
  );
  final html = await _directGet(
    client,
    url,
    accept: 'application/rss+xml, application/xml',
  );
  final results = parseBingRss(html, kVibeWebMaxResults);
  if (results.isEmpty) {
    return const VibeWebToolResult(
      ok: true,
      direct: true,
      summary: '直连：没有结果',
      modelText: '没有找到相关结果，可以换关键词再试。',
    );
  }
  final formatted = _formatResults(results);
  return VibeWebToolResult(
    ok: true,
    direct: true,
    summary: '直连：${formatted.summary}',
    modelText: formatted.modelText,
  );
}

/// 直连抓取：SSRF 校验（含真实 DNS 解析）、逐跳校验跳转、大小与超时上限。
Future<VibeWebToolResult> _directFetchImpl(
  Uri start,
  http.Client client,
) async {
  var current = start;
  for (var hop = 0; hop <= kVibeWebMaxRedirects; hop++) {
    if (current.scheme != 'http' && current.scheme != 'https') {
      throw const _DirectFailure('ssrf', '只允许 http 或 https 网址');
    }
    if (current.userInfo.isNotEmpty) {
      throw const _DirectFailure('ssrf', '网址不能包含用户名或密码');
    }
    await assertPublicHost(current.host);

    final response = await _directSend(
      client,
      current,
      accept: 'text/html,application/xhtml+xml,text/plain;q=0.9',
    );
    if (response.isRedirect) {
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        throw const _DirectFailure('network', '跳转缺少目标地址');
      }
      current = current.resolve(location);
      continue;
    }
    if (!response.isSuccess) {
      throw _DirectFailure('network', '目标站点返回 ${response.statusCode}');
    }
    final type = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (type.isNotEmpty && !_allowedContentTypes.contains(type)) {
      throw _DirectFailure('unsupported', '不支持的内容类型：$type');
    }

    final extracted = extractPageText(response.body);
    final text = extracted.text;
    if (text.trim().isEmpty) {
      return VibeWebToolResult(
        ok: true,
        direct: true,
        summary: '直连：页面没有正文',
        modelText: '抓取成功，但没有提取到正文：$current',
      );
    }
    final formatted = _formatPage(
      uri: current,
      title: extracted.title,
      text: text,
      truncated: response.truncated || text.length > kVibeWebMaxFetchChars,
      direct: true,
    );
    return VibeWebToolResult(
      ok: true,
      direct: true,
      summary: '直连：${formatted.summary}',
      modelText: formatted.modelText,
    );
  }
  throw const _DirectFailure('network', '跳转次数过多');
}

/// 直连 GET，带总超时、响应体上限与浏览器 UA。
///
/// 搜索源会先 302 到区域站点（实测 `www.bing.com` → `cn.bing.com`），
/// 所以必须手动跟随：每一跳都重新做 SSRF 校验，协议只允许 http/https。
Future<String> _directGet(
  http.Client client,
  Uri url, {
  required String accept,
}) async {
  var current = url;
  for (var hop = 0; hop <= kVibeDirectMaxRedirects; hop++) {
    _requireFetchableUri(current);
    await assertPublicHost(current.host);

    final response = await _directSend(client, current, accept: accept);
    if (response.isRedirect) {
      final location = response.headers['location'];
      if (location == null || location.trim().isEmpty) {
        throw const _DirectFailure('network', '跳转缺少目标地址');
      }
      final next = current.resolve(location.trim());
      // 降级到 file/ftp 等协议必须在这里就拒掉，不能等下一次请求。
      if (next.scheme != 'http' && next.scheme != 'https') {
        throw const _DirectFailure('ssrf', '跳转目标不是 http 或 https');
      }
      current = next;
      continue;
    }
    if (!response.isSuccess) {
      throw _DirectFailure('network', '目标站点返回 ${response.statusCode}');
    }
    return response.body;
  }
  throw const _DirectFailure(
    'network',
    '跳转次数超过 $kVibeDirectMaxRedirects 次',
  );
}

/// 协议与凭据的即时校验；跳转后也要重新调用。
void _requireFetchableUri(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const _DirectFailure('ssrf', '只允许 http 或 https 网址');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const _DirectFailure('ssrf', '网址不能包含用户名或密码');
  }
  if (_isBlockedAddress(uri.host)) {
    throw const _DirectFailure('ssrf', '拒绝访问本机或内网地址');
  }
}

class _DirectResponse {
  const _DirectResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.truncated,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final bool truncated;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isRedirect => statusCode >= 300 && statusCode < 400;
}

/// 一次真实的直连请求。超时与尺寸上限在读取前就生效。
Future<_DirectResponse> _directSend(
  http.Client client,
  Uri url, {
  required String accept,
}) async {
  try {
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers.addAll({
        'user-agent': _browserUserAgent,
        'accept': accept,
      });
    final streamed = await client.send(request).timeout(kVibeWebTimeout);
    final bytes = await streamed.stream
        .fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
          if (builder.length < kVibeWebMaxBodyBytes) builder.add(chunk);
          return builder;
        })
        .timeout(kVibeWebTimeout);
    final captured = bytes.takeBytes();
    return _DirectResponse(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      body: utf8.decode(captured, allowMalformed: true),
      truncated: captured.length >= kVibeWebMaxBodyBytes,
    );
  } on TimeoutException {
    throw const _DirectFailure('timeout', '请求超时');
  } on SocketException {
    throw const _DirectFailure('network', '无法连接目标站点');
  } on HandshakeException {
    throw const _DirectFailure('network', '无法建立安全连接');
  } on http.ClientException {
    throw const _DirectFailure('network', '无法连接目标站点');
  } on FormatException {
    throw const _DirectFailure('network', '目标站点返回了无法解析的内容');
  }
}

/// 直连失败；只在模块内部抛出，对外统一转成 [VibeWebToolResult.failure]。
class _DirectFailure implements Exception {
  const _DirectFailure(this.code, this.message);

  final String code;
  final String message;

  /// 没有这个覆盖，错误会显示成 `Instance of '_DirectFailure'`。
  @override
  String toString() => message;
}

/// 两条链路共用的结果格式化：标题、链接、摘要。
VibeWebToolResult _formatResults(List<Object?> results) {
  final lines = <String>[];
  var index = 0;
  for (final item in results) {
    if (item is! Map) continue;
    final title = item['title'] is String ? item['title'] as String : '';
    final url = item['url'] is String ? item['url'] as String : '';
    final snippet = item['snippet'] is String ? item['snippet'] as String : '';
    if (url.isEmpty) continue;
    index++;
    lines.add(
      '$index. ${title.isEmpty ? url : title}\n'
      '   $url\n'
      "${snippet.isEmpty ? '' : '   $snippet\n'}",
    );
    if (index >= kVibeWebMaxResults) break;
  }
  if (lines.isEmpty) {
    return const VibeWebToolResult(
      ok: true,
      summary: '没有可用结果',
      modelText: '没有找到可直接引用的结果。',
    );
  }
  return VibeWebToolResult(
    ok: true,
    summary: '$index 条结果',
    modelText: '搜索结果（引用时请给出链接）：\n${lines.join()}',
  );
}

/// 两条链路共用的页面结果格式化，含长度上限。
VibeWebToolResult _formatPage({
  required Uri uri,
  required String title,
  required String text,
  required bool truncated,
  bool direct = false,
}) {
  final clipped = text.length > kVibeWebMaxFetchChars;
  final bounded = clipped
      ? '${text.substring(0, kVibeWebMaxFetchChars)}\n…（已截断）'
      : text;
  return VibeWebToolResult(
    ok: true,
    direct: direct,
    summary: '${bounded.length} 字符${truncated || clipped ? '（已截断）' : ''}',
    modelText:
        '网页：${title.isEmpty ? uri.toString() : title}\n'
        '${uri.toString()}\n\n$bounded',
  );
}

/// 解析 Bing RSS。与服务端 `parseRss` 同一规则：
/// 先去标签再解实体（CDATA 必须先展开），只接受 http/https 链接。
@visibleForTesting
List<Map<String, String>> parseBingRss(String xml, int limit) {
  final results = <Map<String, String>>[];
  for (final chunk in xml.split(RegExp(r'<item>', caseSensitive: false)).skip(1)) {
    final item = chunk.split(RegExp(r'</item>', caseSensitive: false)).first;
    final title = _stripTags(_pickTag(item, 'title'));
    final link = _decodeEntities(_pickTag(item, 'link')).trim();
    final snippet = _stripTags(_pickTag(item, 'description'));
    if (link.isEmpty) continue;
    final uri = Uri.tryParse(link);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      continue;
    }
    if (title.isEmpty && snippet.isEmpty) continue;
    results.add({
      'title': title.isEmpty ? uri.toString() : title,
      'url': uri.toString(),
      'snippet': snippet,
    });
    if (results.length >= limit) break;
  }
  return results;
}

String _pickTag(String item, String tag) {
  // 模板字符串里反斜杠原样保留：写成 [\\s\\S] 会让整个正则失效。
  final match = RegExp(
    '<$tag[^>]*>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(item);
  return match?.group(1) ?? '';
}

String _decodeEntities(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

String _stripTags(String value) {
  final expanded = value.replaceAllMapped(
    RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'),
    (match) => match.group(1) ?? '',
  );
  return _decodeEntities(
    _decodeEntities(expanded).replaceAll(RegExp('<[^>]*>'), ' '),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 提取标题与正文。与服务端 `extractText` + `normalizeText` 同一规则。
@visibleForTesting
({String title, String text}) extractPageText(String html) {
  final titleMatch = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(html);
  final title = titleMatch == null
      ? ''
      : _decodeEntities(titleMatch.group(1) ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
  // 标题只算元数据，不能混进正文；head 里的剩余内容也一并去掉。
  final withoutHead = html.replaceAll(
    RegExp(r'<head[\s\S]*?</head>', caseSensitive: false),
    ' ',
  );
  final body = withoutHead
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<noscript[\s\S]*?</noscript>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
      .replaceAll(
        RegExp(r'</(p|div|li|h[1-6]|tr|br)>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp('<[^>]*>'), ' ');
  return (title: title, text: normalizePageText(_decodeEntities(body)));
}

/// 去空行、压缩行内空白。与服务端 `normalizeText` 一致。
@visibleForTesting
String normalizePageText(String value) => value
    .split('\n')
    .map((line) => line.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trim())
    .where((line) => line.isNotEmpty)
    .join('\n');

/// 直连前的完整 SSRF 校验：字面量 + 真实 DNS 解析结果全部必须为公网地址。
///
/// 与只用字面量判断的 [_isBlockedAddress] 互补：域名可以解析到内网，
/// 因此这里必须先解析再判断，任一记录命中内网就整体拒绝。
@visibleForTesting
Future<List<String>> assertPublicHost(
  String host, {
  Future<List<String>> Function(String host)? resolve,
}) async {
  final value = host.trim().toLowerCase();
  final bare = value.startsWith('[') && value.endsWith(']')
      ? value.substring(1, value.length - 1)
      : value;
  if (bare.isEmpty) throw const _DirectFailure('ssrf', '网址缺少主机名');
  if (bare == 'localhost' || bare.endsWith('.localhost')) {
    throw const _DirectFailure('ssrf', '拒绝访问本机地址');
  }
  if (InternetAddress.tryParse(bare) != null) {
    if (_isBlockedAddress(bare)) {
      throw const _DirectFailure('ssrf', '拒绝访问本机或内网地址');
    }
    return [bare];
  }
  final List<String> addresses;
  try {
    addresses = resolve != null
        ? await resolve(bare)
        : [
            for (final entry in await InternetAddress.lookup(bare))
              entry.address,
          ];
  } on SocketException {
    throw const _DirectFailure('network', '无法解析主机名');
  }
  if (addresses.isEmpty) {
    throw const _DirectFailure('network', '无法解析主机名');
  }
  for (final address in addresses) {
    if (_isBlockedAddress(address)) {
      throw const _DirectFailure('ssrf', '拒绝访问本机或内网地址');
    }
  }
  return addresses;
}

/// 直连搜索的可测入口：供实时验收直接调用真实网络链路。
///
/// 生产调用走 [executeVibeWebTool]；这里只暴露同一实现，避免测试重写解析逻辑。
@visibleForTesting
Future<List<Map<String, String>>> fetchDirectRssForTest(
  String query,
  http.Client client,
) async {
  final url = Uri.parse(kVibeDirectSearchEndpoint).replace(
    queryParameters: {
      'q': query,
      'format': 'rss',
      'count': '$kVibeWebMaxResults',
    },
  );
  // 与生产路径同一条实现，包含手动跟随 302。
  final xml = await _directGet(
    client,
    url,
    accept: 'application/rss+xml, application/xml',
  );
  return parseBingRss(xml, kVibeWebMaxResults);
}
/// 直连抓取的可测入口：返回真实提取出的标题与正文。
@visibleForTesting
Future<({String title, String text})> fetchDirectPageForTest(
  Uri uri,
  http.Client client,
) async {
  await assertPublicHost(uri.host);
  final response = await _directSend(
    client,
    uri,
    accept: 'text/html,application/xhtml+xml,text/plain;q=0.9',
  );
  if (!response.isSuccess) {
    throw StateError('目标站点返回 ${response.statusCode}');
  }
  return extractPageText(response.body);
}

/// 供控制器拼接工具列表：本地工具加上联网工具。
///
/// 离线专属产品不暴露联网工具，模型也就不会尝试调用它们。
List<Map<String, dynamic>> vibeToolSpecsWithWeb() => [
  ...vibeToolSpecs(),
  ...vibeWebToolSpecs(),
];

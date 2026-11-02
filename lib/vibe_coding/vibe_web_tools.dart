/// 联网抓取工具：`web_fetch`。
///
/// 只经 [ApiClient] 的服务端中转：服务端做 SSRF 校验、跳转逐跳校验、大小与
/// 超时上限，正文提取也在服务端完成。客户端不再有任何直连分支。
///
/// 为什么删掉直连回退（整改任务书 §1、§3-W3）：
/// - `web_search` 的唯一实现是设备直连 `www.bing.com` 的 RSS，Bing 不在
///   已披露的第三方清单里（只有华为、深度求索、阿里云/腾讯云/京东云），
///   所以搜索下线，直连搜索一起删掉。
/// - `web_fetch` 的直连分支同样会把用户请求发给任意未披露站点，并且绕过了
///   服务端的 SSRF 校验与审计。中转可用时两者行为一致，中转不可用时
///   “抓不到”比“偷偷直连”更符合承诺，因此直连抓取也一并删除。
///
/// 工具结果只作为模型反馈，从不伪造成功，也不把网页内容当成本地文件。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/api_client.dart';
import '../services/studio_profile.dart';
import 'vibe_tools.dart';

/// 联网工具名集合；控制器据此决定工具卡片文案。
const Set<String> kVibeWebToolNames = {'web_fetch'};

/// `web_fetch` 保留的正文上限（UTF-16 字符）。
const int kVibeWebMaxFetchChars = 20000;

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
  });

  /// 失败时也返回模型可读文本，让模型能改用别的办法。
  final bool ok;

  /// 工具卡片上的一行摘要。
  final String summary;

  /// 回传给模型的内容。
  final String modelText;

  VibeWebToolResult.failure(String code, String message)
    : ok = false,
      summary = message,
      modelText = 'error($code): $message';
}

/// OpenAI 兼容工具定义，与 [vibeToolSpecs] 同形状，可直接拼接。
List<Map<String, dynamic>> vibeWebToolSpecs() => [
  {
    'type': 'function',
    'function': {
      'name': 'web_fetch',
      'description': '抓取一个公开网页并返回去掉标签的正文。用于阅读已知网址的具体页面。',
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

  try {
    return await _fetch(arguments, api, token);
  } on ApiException catch (error) {
    // 策略拒绝必须保留原错误码，便于控制器区分“不能上网”和“网络故障”。
    if (error.details['code'] == 'OFFLINE_ONLY') {
      return VibeWebToolResult.failure('OFFLINE_ONLY', error.message);
    }
    return VibeWebToolResult.failure('network', error.message);
  }
}

/// 参数校验；返回 null 表示通过。
VibeWebToolResult? _validateArguments(
  String name,
  Map<String, dynamic> arguments,
) {
  if (!isVibeWebTool(name)) {
    return VibeWebToolResult.failure('error', '未知联网工具：$name');
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
  // 只有字面量地址在本地判断；域名交给服务端解析后再判断，
  // 客户端不承担 DNS（也就不存在“解析后直连”的旁路）。
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

/// 供控制器拼接工具列表：本地工具加上联网工具。
///
/// 离线专属产品不暴露联网工具，模型也就不会尝试调用它们。
/// `web_search` 已下线（§3-W3），这里只剩下 `web_fetch`。
List<Map<String, dynamic>> vibeToolSpecsWithWeb() => [
  ...vibeToolSpecs(),
  ...vibeWebToolSpecs(),
];

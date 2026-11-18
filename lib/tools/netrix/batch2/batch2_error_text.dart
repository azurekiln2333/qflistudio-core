/// Error text for the ported netrix batch 2 tools.
///
/// 1:1 port of `netrix/lib/core/localization.dart`: `errorMessage` only gives
/// distinct text to the handful of keys in [exactErrorText]; every other
/// `error_*` key falls back to the invalid-input or timeout sentence, and a
/// non-tool error falls back to [genericErrorText]. The three shipped languages
/// match the host application's set (zh-CN, zh-TW, en); netrix's ja / ko
/// catalogues are intentionally not ported.
library;

/// Sentence shown for errors that are not netrix tool errors.
const String genericErrorText = '操作失败，请检查输入后重试。';
const String genericErrorTextEn =
    'The operation failed. Check the input and try again.';
const String genericErrorTextZhTw = '操作失敗，請檢查輸入後再試。';

/// Sentence shown for input errors without a dedicated message.
const String invalidInputText = '输入无效，请检查后重试。';
const String invalidInputTextEn = 'The input is invalid. Check it and try again.';
const String invalidInputTextZhTw = '輸入無效，請檢查後再試。';

/// Sentence shown for the timeout error keys.
const String timeoutText = '操作超时，请稍后重试。';
const String timeoutTextEn = 'The operation timed out. Try again later.';
const String timeoutTextZhTw = '操作逾時，請稍後再試。';

/// Error keys that netrix renders with their own sentence.
const Map<String, String> exactErrorText = <String, String>{
  'error_ipv4_segments': 'IPv4 地址必须包含四段。',
  'error_ipv4_prefix': 'IPv4 前缀必须是 0-32。',
  'error_cidr_format': 'CIDR 格式应为 192.168.1.0/24。',
  'error_port_range': '端口必须是 1-65535 之间的整数。',
  'error_invalid_json': 'JSON 格式无效。',
  'error_unsupported_algorithm': '不支持的摘要算法。',
  'error_private_network_only': '主机扫描只允许私有 IPv4 网段。',
  'error_host_limit': '主机扫描网段不能超过 256 个地址。',
  'error_host_port_limit': '主机扫描端口必须在 1-16 个之间。',
};

const Map<String, String> exactErrorTextEn = <String, String>{
  'error_ipv4_segments': 'An IPv4 address must contain four segments.',
  'error_ipv4_prefix': 'The IPv4 prefix must be between 0 and 32.',
  'error_cidr_format': 'CIDR must look like 192.168.1.0/24.',
  'error_port_range': 'The port must be an integer from 1 to 65535.',
  'error_invalid_json': 'The JSON is invalid.',
  'error_unsupported_algorithm': 'The digest algorithm is unsupported.',
  'error_private_network_only': 'Host scanning only allows private IPv4 ranges.',
  'error_host_limit':
      'The host range cannot contain more than 256 addresses.',
  'error_host_port_limit': 'Host scanning accepts 1 to 16 ports.',
};

const Map<String, String> exactErrorTextZhTw = <String, String>{
  'error_ipv4_segments': 'IPv4 位址必須包含四段。',
  'error_ipv4_prefix': 'IPv4 前綴必須介於 0 到 32。',
  'error_cidr_format': 'CIDR 格式應為 192.168.1.0/24。',
  'error_port_range': '連接埠必須是 1 到 65535 之間的整數。',
  'error_invalid_json': 'JSON 格式無效。',
  'error_unsupported_algorithm': '不支援的摘要演算法。',
  'error_private_network_only': '主機掃描只允許私有 IPv4 網段。',
  'error_host_limit': '主機網段不能超過 256 個位址。',
  'error_host_port_limit': '主機掃描連接埠必須介於 1 到 16 個。',
};

/// Error keys netrix renders as a timeout.
const Set<String> timeoutErrorCodes = <String>{
  'error_connection_timeout',
  'error_dns_timeout',
  'error_http_timeout',
  'error_public_ip_timeout',
  'error_rdap_timeout',
  'error_tls_timeout',
  'error_websocket_timeout',
};

/// Which catalogue to use. The host application ships three languages.
enum NetrixErrorLanguage { zhCn, zhTw, en }

/// Renders one netrix error code exactly like `NetrixLocalizations.errorMessage`.
///
/// The raw code never reaches the user: an unknown `error_*` code becomes the
/// invalid-input sentence, and any other value becomes the generic sentence.
String netrixBatch2ErrorText(
  Object? error, {
  NetrixErrorLanguage language = NetrixErrorLanguage.zhCn,
}) {
  final Map<String, String> exact = switch (language) {
    NetrixErrorLanguage.zhCn => exactErrorText,
    NetrixErrorLanguage.zhTw => exactErrorTextZhTw,
    NetrixErrorLanguage.en => exactErrorTextEn,
  };
  final String invalid = switch (language) {
    NetrixErrorLanguage.zhCn => invalidInputText,
    NetrixErrorLanguage.zhTw => invalidInputTextZhTw,
    NetrixErrorLanguage.en => invalidInputTextEn,
  };
  final String timeout = switch (language) {
    NetrixErrorLanguage.zhCn => timeoutText,
    NetrixErrorLanguage.zhTw => timeoutTextZhTw,
    NetrixErrorLanguage.en => timeoutTextEn,
  };
  final String generic = switch (language) {
    NetrixErrorLanguage.zhCn => genericErrorText,
    NetrixErrorLanguage.zhTw => genericErrorTextZhTw,
    NetrixErrorLanguage.en => genericErrorTextEn,
  };

  if (error is! String) return generic;
  final String? exactMessage = exact[error];
  if (exactMessage != null) return exactMessage;
  if (error.startsWith('error_')) {
    return timeoutErrorCodes.contains(error) ? timeout : invalid;
  }
  return generic;
}

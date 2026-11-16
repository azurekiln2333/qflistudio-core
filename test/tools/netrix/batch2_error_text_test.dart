import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_error_text.dart';

/// Ported from the `errorMessage` behaviour of
/// `netrix/lib/core/localization.dart` and its `widget_test.dart` locale check.
void main() {
  test('uses the dedicated sentence for the mapped keys', () {
    expect(
      netrixBatch2ErrorText('error_cidr_format'),
      'CIDR 格式应为 192.168.1.0/24。',
    );
    expect(
      netrixBatch2ErrorText('error_private_network_only'),
      '主机扫描只允许私有 IPv4 网段。',
    );
  });

  test('uses the timeout sentence for timeout keys', () {
    for (final String code in timeoutErrorCodes) {
      expect(
        netrixBatch2ErrorText(code),
        '操作超时，请稍后重试。',
        reason: code,
      );
    }
  });

  test('hides unmapped error codes behind the invalid-input sentence', () {
    expect(netrixBatch2ErrorText('error_mac_format'), '输入无效，请检查后重试。');
    expect(
      netrixBatch2ErrorText('error_something_new'),
      '输入无效，请检查后重试。',
    );
  });

  test('falls back to the generic sentence for non-tool errors', () {
    expect(netrixBatch2ErrorText('boom'), '操作失败，请检查输入后重试。');
    expect(netrixBatch2ErrorText(Object()), '操作失败，请检查输入后重试。');
  });

  test('renders English and Traditional Chinese like netrix', () {
    expect(
      netrixBatch2ErrorText(
        'error_port_range',
        language: NetrixErrorLanguage.en,
      ),
      'The port must be an integer from 1 to 65535.',
    );
    expect(
      netrixBatch2ErrorText(
        'error_tls_timeout',
        language: NetrixErrorLanguage.en,
      ),
      'The operation timed out. Try again later.',
    );
    expect(
      netrixBatch2ErrorText(
        'error_http_url',
        language: NetrixErrorLanguage.zhTw,
      ),
      '輸入無效，請檢查後再試。',
    );
  });
}

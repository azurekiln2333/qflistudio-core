import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_widgets.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_tools.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_web_tools.dart';

/// 中文：含 CJK 统一表意文字。
final _cjk = RegExp(r'[\u4e00-\u9fff]');

List<String> _toolNames(List<Map<String, dynamic>> specs) => [
  for (final spec in specs)
    ((spec['function'] as Map?)?['name'] as String?) ?? '',
];

void main() {
  group('工具中文标签', () {
    test('vibe_tools.dart 注册的每个工具都有中文标签', () {
      final names = _toolNames(vibeToolSpecs());
      expect(names, isNotEmpty);

      for (final name in names) {
        final label = vibeToolLabel(name);
        expect(label, isNot(name), reason: '$name 没有中文标签');
        expect(_cjk.hasMatch(label), isTrue, reason: '$name 的标签不是中文：$label');
      }
    });

    test('带网页工具时也全部有中文标签', () {
      for (final name in _toolNames(vibeToolSpecsWithWeb())) {
        final label = vibeToolLabel(name);
        expect(label, isNot(name), reason: '$name 没有中文标签');
        expect(_cjk.hasMatch(label), isTrue, reason: '$name 的标签不是中文：$label');
      }
    });

    test('search_text 显示为「搜索文本」', () {
      expect(vibeToolLabel('search_text'), '搜索文本');
    });

    test('未知工具回退到原名，不隐藏', () {
      expect(vibeToolLabel('future_tool'), 'future_tool');
    });
  });
}

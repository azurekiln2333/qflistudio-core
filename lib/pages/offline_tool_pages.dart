import 'package:flutter/material.dart';

import '../tools/offline_tools.dart';
import '../widgets/tool_widgets.dart';

class UnicodeToolPage extends StatefulWidget {
  const UnicodeToolPage({super.key});

  static const String title = '字符/Unicode';
  static const String description =
      '查看一个字符的码点、Unicode \\uXXXX 转义与 UTF-8 / UTF-16 字节。';

  @override
  State<UnicodeToolPage> createState() => _UnicodeToolPageState();
}

class _UnicodeToolPageState extends State<UnicodeToolPage> {
  final _input = TextEditingController(text: '中');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? error;
    UnicodeInfo? info;
    final text = _input.text;
    if (text.isNotEmpty) {
      final runes = text.runes.toList();
      if (runes.length != 1) {
        error = '请输入恰好一个字符（当前 ${runes.length} 个）';
      } else {
        info = UnicodeInfo(runes.first);
      }
    }
    return ToolScaffold(
      title: UnicodeToolPage.title,
      description: UnicodeToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: '字符',
          onChanged: (_) => setState(() {}),
        ),
        ToolError(error),
        const SizedBox(height: 16),
        if (info != null)
          ToolResultCard(
            title: '编码',
            children: [
              ResultRow(label: '码点', value: info.hex),
              ResultRow(label: '十进制', value: '${info.codePoint}'),
              ResultRow(label: 'Unicode 转义', value: info.unicodeEscape),
              ResultRow(label: 'UTF-8', value: info.utf8BytesHex),
              ResultRow(label: 'UTF-16', value: info.utf16UnitsHex),
              ResultRow(
                label: 'UTF-16 单元数',
                value: '${info.utf16Units.length}',
              ),
            ],
          )
        else
          const Text('输入一个字符以查看它的码点与编码'),
      ],
    );
  }
}

class TimestampToolPage extends StatefulWidget {
  const TimestampToolPage({super.key});

  static const String title = '时间戳';
  static const String description = '毫秒/秒时间戳与本地日期时间互转。';

  @override
  State<TimestampToolPage> createState() => _TimestampToolPageState();
}

class _TimestampToolPageState extends State<TimestampToolPage> {
  final _epoch = TextEditingController(
    text: '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
  );
  final _local = TextEditingController();
  var _seconds = true;

  @override
  void dispose() {
    _epoch.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? error;
    String? localText;
    String? epochText;
    final raw = _epoch.text.trim();
    if (raw.isNotEmpty) {
      final value = int.tryParse(raw);
      if (value == null) {
        error = '时间戳必须是整数';
      } else {
        localText = OfflineTimestamp.toLocal(
          DateTime.fromMillisecondsSinceEpoch(_seconds ? value * 1000 : value),
          milliseconds: !_seconds,
        );
      }
    }
    final localInput = _local.text.trim();
    if (localInput.isNotEmpty) {
      final parsed = OfflineTimestamp.parseLocal(localInput);
      if (parsed == null) {
        error = '日期格式应为 yyyy-MM-dd HH:mm:ss';
      } else {
        epochText = _seconds
            ? '${parsed.millisecondsSinceEpoch ~/ 1000}'
            : '${parsed.millisecondsSinceEpoch}';
      }
    }
    return ToolScaffold(
      title: TimestampToolPage.title,
      description: TimestampToolPage.description,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('秒')),
            ButtonSegment(value: false, label: Text('毫秒')),
          ],
          selected: {_seconds},
          onSelectionChanged: (selection) =>
              setState(() => _seconds = selection.first),
        ),
        ToolField(
          controller: _epoch,
          label: '时间戳',
          onChanged: (_) => setState(() {}),
        ),
        ToolField(
          controller: _local,
          label: '本地日期时间',
          hint: 'yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd',
          onChanged: (_) => setState(() {}),
        ),
        ToolError(error),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '结果',
          children: [
            if (localText != null) ResultRow(label: '本地时间', value: localText),
            if (epochText != null) ResultRow(label: '时间戳', value: epochText),
            if (localText == null && epochText == null)
              const ResultRow(label: '提示', value: '输入任一字段即可换算'),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Base64
// ---------------------------------------------------------------------------

class Base64ToolPage extends StatefulWidget {
  const Base64ToolPage({super.key});

  static const String title = 'Base64';
  static const String description = '标准与 URL-safe 两种字母表的 Base64 编解码。';

  @override
  State<Base64ToolPage> createState() => _Base64ToolPageState();
}

class _Base64ToolPageState extends State<Base64ToolPage> {
  final _plain = TextEditingController(text: 'hello');
  final _encoded = TextEditingController();
  var _urlSafe = false;

  @override
  void dispose() {
    _plain.dispose();
    _encoded.dispose();
    super.dispose();
  }

  String? _error;

  void _encode() {
    setState(() {
      _error = null;
      _encoded.text = _urlSafe
          ? OfflineBase64.encodeUrlSafe(_plain.text)
          : OfflineBase64.encode(_plain.text);
    });
  }

  void _decode() {
    setState(() {
      try {
        _plain.text = _urlSafe
            ? OfflineBase64.decodeUrlSafe(_encoded.text)
            : OfflineBase64.decode(_encoded.text);
        _error = null;
      } on FormatException catch (exception) {
        _error = '解码失败：${exception.message}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final output = _urlSafe
        ? OfflineBase64.encodeUrlSafe(_plain.text)
        : OfflineBase64.encode(_plain.text);
    return ToolScaffold(
      title: Base64ToolPage.title,
      description: Base64ToolPage.description,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('URL-safe 字母表（无填充）'),
          value: _urlSafe,
          onChanged: (value) => setState(() => _urlSafe = value),
        ),
        ToolField(
          controller: _plain,
          label: '原文',
          maxLines: 3,
          monospace: false,
          onChanged: (_) => setState(() {}),
        ),
        ToolField(
          controller: _encoded,
          label: 'Base64',
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        ToolError(_error),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _encode,
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: const Text('编码'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _decode,
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text('解码'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '即时结果',
          children: [ResultRow(label: 'Base64', value: output)],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// URL encoding
// ---------------------------------------------------------------------------

class UrlToolPage extends StatefulWidget {
  const UrlToolPage({super.key});

  static const String title = 'URL 编解码';
  static const String description = '表单风格百分号编解码，空格编码为 +。';

  @override
  State<UrlToolPage> createState() => _UrlToolPageState();
}

class _UrlToolPageState extends State<UrlToolPage> {
  final _plain = TextEditingController(text: '中 文 & a=1');
  String? _error;

  @override
  void dispose() {
    _plain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      title: UrlToolPage.title,
      description: UrlToolPage.description,
      children: [
        ToolField(
          controller: _plain,
          label: '文本',
          maxLines: 3,
          monospace: false,
          onChanged: (_) => setState(() => _error = null),
        ),
        ToolError(_error),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '结果',
          children: [
            ResultRow(label: '编码', value: OfflineUrlCodec.encode(_plain.text)),
            ResultRow(label: '解码', value: _decodedOrError()),
          ],
        ),
      ],
    );
  }

  String _decodedOrError() {
    try {
      return OfflineUrlCodec.decode(_plain.text);
    } on FormatException catch (error) {
      return '无法解码：${error.message}';
    }
  }
}

// ---------------------------------------------------------------------------
// Hashes
// ---------------------------------------------------------------------------

class HashToolPage extends StatefulWidget {
  const HashToolPage({super.key});

  static const String title = '哈希摘要';
  static const String description = 'MD5 / SHA-1 / SHA-256 摘要（纯 Dart 实现，用于校验）。';

  @override
  State<HashToolPage> createState() => _HashToolPageState();
}

class _HashToolPageState extends State<HashToolPage> {
  final _input = TextEditingController(text: 'abc');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digests = OfflineDigest.all(_input.text);
    return ToolScaffold(
      title: HashToolPage.title,
      description: HashToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: '输入',
          maxLines: 4,
          monospace: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '摘要',
          children: [
            for (final entry in digests.entries)
              ResultRow(label: entry.key, value: entry.value),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Regex tester
// ---------------------------------------------------------------------------

class RegexToolPage extends StatefulWidget {
  const RegexToolPage({super.key});

  static const String title = '正则测试';
  static const String description = '用 Dart RegExp 试跑正则，查看匹配和捕获分组。';

  @override
  State<RegexToolPage> createState() => _RegexToolPageState();
}

class _RegexToolPageState extends State<RegexToolPage> {
  final _pattern = TextEditingController(text: r'(\d+)-(\d+)');
  final _input = TextEditingController(text: 'a 12-34 b 56-78');
  var _multiLine = false;
  var _dotAll = false;
  var _caseSensitive = true;

  @override
  void dispose() {
    _pattern.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = OfflineRegex.test(
      _pattern.text,
      _input.text,
      multiLine: _multiLine,
      dotAll: _dotAll,
      caseSensitive: _caseSensitive,
    );
    return ToolScaffold(
      title: RegexToolPage.title,
      description: RegexToolPage.description,
      children: [
        ToolField(
          controller: _pattern,
          label: '正则',
          onChanged: (_) => setState(() {}),
        ),
        ToolField(
          controller: _input,
          label: '测试文本',
          maxLines: 4,
          monospace: false,
          onChanged: (_) => setState(() {}),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('多行'),
              selected: _multiLine,
              onSelected: (value) => setState(() => _multiLine = value),
            ),
            FilterChip(
              label: const Text('点匹配换行'),
              selected: _dotAll,
              onSelected: (value) => setState(() => _dotAll = value),
            ),
            FilterChip(
              label: const Text('区分大小写'),
              selected: _caseSensitive,
              onSelected: (value) => setState(() => _caseSensitive = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!result.ok)
          ToolResultCard(
            title: '错误',
            children: [ResultRow(label: '原因', value: result.error ?? '')],
          )
        else
          ToolResultCard(
            title:
                '匹配 ${result.matches.length} 处'
                '${result.truncated ? '（已截断）' : ''}',
            children: result.matches.isEmpty
                ? const [ResultRow(label: '结果', value: '无匹配')]
                : [
                    for (var i = 0; i < result.matches.length; i++)
                      ResultRow(
                        label: '#${i + 1} @${result.matches[i].index}',
                        value: _describeMatch(result.matches[i]),
                      ),
                  ],
          ),
      ],
    );
  }

  String _describeMatch(OfflineRegexMatch match) {
    final buffer = StringBuffer('「${match.value}」');
    if (match.groups.isNotEmpty) {
      buffer.write('  组：${match.groups.map((g) => g ?? 'null').join(' | ')}');
    }
    if (match.namedGroups.isNotEmpty) {
      buffer.write(
        '  命名组：${match.namedGroups.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
      );
    }
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// Colour converter
// ---------------------------------------------------------------------------

class ColorToolPage extends StatefulWidget {
  const ColorToolPage({super.key});

  static const String title = '颜色转换';
  static const String description =
      '#RRGGBB / #AARRGGBB <-> Android、Kotlin 与 CSS 记法。';

  @override
  State<ColorToolPage> createState() => _ColorToolPageState();
}

class _ColorToolPageState extends State<ColorToolPage> {
  final _input = TextEditingController(text: '#336699');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    OfflineColorInfo? info;
    String? error;
    try {
      info = OfflineColorInfo.parse(_input.text);
    } on FormatException catch (exception) {
      error = exception.message;
    }
    return ToolScaffold(
      title: ColorToolPage.title,
      description: ColorToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: '颜色',
          hint: '#RGB、#RRGGBB 或 #AARRGGBB',
          onChanged: (_) => setState(() {}),
        ),
        ToolError(error),
        if (info != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Color(info.argb),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '预览',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ToolResultCard(
            title: '表示',
            children: [
              ResultRow(label: 'Android', value: info.hexArgb),
              ResultRow(label: 'RGB', value: info.hexRgb),
              ResultRow(label: 'Kotlin', value: info.kotlinHex),
              ResultRow(label: 'CSS', value: info.cssRgb),
              ResultRow(label: 'HSL', value: info.cssHsl),
              ResultRow(
                label: 'ARGB',
                value:
                    '${info.alpha}, ${info.red}, ${info.green}, ${info.blue}',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// UUID
// ---------------------------------------------------------------------------

class UuidToolPage extends StatefulWidget {
  const UuidToolPage({super.key});

  static const String title = 'UUID 生成';
  static const String description = '随机 v4，以及基于名称的确定性 v3（MD5）/ v5（SHA-1）。';

  @override
  State<UuidToolPage> createState() => _UuidToolPageState();
}

class _UuidToolPageState extends State<UuidToolPage> {
  final _name = TextEditingController(text: 'www.example.com');
  final _namespace = TextEditingController(
    text: '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
  );
  var _v4 = '';

  @override
  void initState() {
    super.initState();
    _v4 = OfflineUuid.v4();
  }

  @override
  void dispose() {
    _name.dispose();
    _namespace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      title: UuidToolPage.title,
      description: UuidToolPage.description,
      children: [
        ToolResultCard(
          title: '随机 UUID（v4）',
          children: [ResultRow(label: 'UUID', value: _v4)],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () => setState(() => _v4 = OfflineUuid.v4()),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新生成'),
          ),
        ),
        const SizedBox(height: 20),
        Text('基于名称（确定性）', style: Theme.of(context).textTheme.titleSmall),
        ToolField(
          controller: _name,
          label: '名称',
          onChanged: (_) => setState(() {}),
        ),
        ToolField(
          controller: _namespace,
          label: '命名空间 UUID',
          hint: '留空使用 DNS 命名空间',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        ToolResultCard(
          title: '结果',
          children: [
            ResultRow(
              label: 'v3 (MD5)',
              value: OfflineUuid.v3(_name.text, _namespace.text),
            ),
            ResultRow(
              label: 'v5 (SHA-1)',
              value: OfflineUuid.v5(_name.text, _namespace.text),
            ),
          ],
        ),
      ],
    );
  }
}

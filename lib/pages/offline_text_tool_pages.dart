import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tools/offline_text_tools.dart';
import '../widgets/tool_widgets.dart';

// ---------------------------------------------------------------------------
// Number base converter
// ---------------------------------------------------------------------------

class NumberBaseToolPage extends StatefulWidget {
  const NumberBaseToolPage({super.key});

  static const String title = '进制转换';
  static const String description = '二/八/十/十六进制互转，支持 0x、0b、0o 前缀、负数与任意大的整数。';

  @override
  State<NumberBaseToolPage> createState() => _NumberBaseToolPageState();
}

class _NumberBaseToolPageState extends State<NumberBaseToolPage> {
  final _input = TextEditingController(text: '255');
  var _radix = 10;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    OfflineNumberResult? result;
    String? error;
    try {
      result = OfflineNumberResult.parse(_input.text, radix: _radix);
    } on FormatException catch (exception) {
      error = exception.message;
    }
    return ToolScaffold(
      title: NumberBaseToolPage.title,
      description: NumberBaseToolPage.description,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 2, label: Text('二')),
            ButtonSegment(value: 8, label: Text('八')),
            ButtonSegment(value: 10, label: Text('十')),
            ButtonSegment(value: 16, label: Text('十六')),
          ],
          selected: {_radix},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _radix = selection.first),
        ),
        ToolField(
          controller: _input,
          label: '输入（$_radix 进制）',
          hint: '例如 255、0xFF、-0b1010、1_000',
          onChanged: (_) => setState(() {}),
        ),
        ToolError(error),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '结果',
          children: [
            if (result == null)
              const ResultRow(label: '提示', value: '输入一个整数即可查看各进制表示')
            else ...[
              ResultRow(label: '二进制', value: result.binary),
              ResultRow(label: '八进制', value: result.octal),
              ResultRow(label: '十进制', value: result.decimal),
              ResultRow(label: '十六进制', value: result.hexadecimal),
              ResultRow(label: '有效位数', value: '${result.bitLength} 位'),
              ResultRow(label: 'Base64（补码）', value: result.base64),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Password generator
// ---------------------------------------------------------------------------

class PasswordToolPage extends StatefulWidget {
  const PasswordToolPage({super.key});

  static const String title = '密码生成';
  static const String description = '在本机使用安全随机数生成密码，并估算字符池与暴力破解所需规模。';

  @override
  State<PasswordToolPage> createState() => _PasswordToolPageState();
}

class _PasswordToolPageState extends State<PasswordToolPage> {
  var _length = 16.0;
  var _lower = true;
  var _upper = true;
  var _digit = true;
  var _symbol = true;
  var _excludeAmbiguous = true;
  String? _lastError;
  OfflinePasswordResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _result = _generate();
    _error = _lastError;
  }

  OfflinePasswordResult? _generate() {
    try {
      final result = OfflinePassword.generate(
        length: _length.round(),
        lower: _lower,
        upper: _upper,
        digit: _digit,
        symbol: _symbol,
        excludeAmbiguous: _excludeAmbiguous,
      );
      _lastError = null;
      return result;
    } on ArgumentError catch (exception) {
      _lastError = '${exception.message}';
      return null;
    } on UnsupportedError {
      _lastError = '当前设备无法提供安全随机数，请稍后重试';
      return null;
    }
  }

  void _refresh() => setState(() {
    _result = _generate();
    _error = _lastError;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return ToolScaffold(
      title: PasswordToolPage.title,
      description: PasswordToolPage.description,
      children: [
        Text('长度 ${_length.round()}', style: theme.textTheme.titleSmall),
        Semantics(
          label: '密码长度',
          child: Slider(
            value: _length,
            min: 4,
            max: 64,
            divisions: 60,
            label: '${_length.round()}',
            onChanged: (value) {
              _length = value;
              _refresh();
            },
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('小写 a-z'),
              selected: _lower,
              onSelected: (value) {
                _lower = value;
                _refresh();
              },
            ),
            FilterChip(
              label: const Text('大写 A-Z'),
              selected: _upper,
              onSelected: (value) {
                _upper = value;
                _refresh();
              },
            ),
            FilterChip(
              label: const Text('数字 0-9'),
              selected: _digit,
              onSelected: (value) {
                _digit = value;
                _refresh();
              },
            ),
            FilterChip(
              label: const Text('符号'),
              selected: _symbol,
              onSelected: (value) {
                _symbol = value;
                _refresh();
              },
            ),
            FilterChip(
              label: const Text('排除易混淆 Il1O0o'),
              selected: _excludeAmbiguous,
              onSelected: (value) {
                _excludeAmbiguous = value;
                _refresh();
              },
            ),
          ],
        ),
        ToolError(_error),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新生成'),
          ),
        ),
        const SizedBox(height: 16),
        if (result != null)
          ToolResultCard(
            title: '结果',
            children: [
              ResultRow(label: '密码', value: result.value),
              ResultRow(
                label: '字符池',
                value: '${result.poolSize} 个字符',
                allowCopy: false,
              ),
              ResultRow(
                label: '熵',
                value:
                    '${result.entropyBits.toStringAsFixed(1)} bit'
                    '（${result.strength}）',
                allowCopy: false,
              ),
              ResultRow(
                label: '破解规模',
                value: _crackLabel(result.crackSeconds),
                allowCopy: false,
              ),
            ],
          ),
      ],
    );
  }

  /// Orders of magnitude rather than a fake precise duration.
  String _crackLabel(double seconds) {
    if (seconds < 1) return '小于 1 秒（按 10¹¹ 次/秒估算）';
    const units = <(double, String)>[
      (60, '分钟'),
      (3600, '小时'),
      (86400, '天'),
      (31557600, '年'),
    ];
    var value = seconds;
    var unit = '秒';
    for (final (factor, name) in units.reversed) {
      if (seconds >= factor) {
        value = seconds / factor;
        unit = name;
        break;
      }
    }
    if (unit == '年' && value > 1e6) {
      return '约 10^${(math.log(value) / math.ln10).floor()} 年（按 10¹¹ 次/秒估算）';
    }
    return '约 ${value.toStringAsPrecision(2)} $unit（按 10¹¹ 次/秒估算）';
  }
}

// ---------------------------------------------------------------------------
// Text statistics
// ---------------------------------------------------------------------------

class TextStatsToolPage extends StatefulWidget {
  const TextStatsToolPage({super.key});

  static const String title = '文本统计';
  static const String description =
      '统计字符（码点）、字节、行数、单词数，并按 ASCII / 中文 / 数字 / 空白 / 标点拆分。';

  @override
  State<TextStatsToolPage> createState() => _TextStatsToolPageState();
}

class _TextStatsToolPageState extends State<TextStatsToolPage> {
  final _input = TextEditingController(
    text: 'QFLIStudioN 多语言编辑器\nSecond line: 12345!',
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = OfflineTextStats.of(_input.text);
    String count(int value) => OfflineTextStats.grouped(value);
    return ToolScaffold(
      title: TextStatsToolPage.title,
      description: TextStatsToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: '文本',
          maxLines: 8,
          monospace: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '统计',
          children: [
            ResultRow(
              label: '字符（码点）',
              value: count(stats.codePoints),
              allowCopy: false,
            ),
            ResultRow(
              label: '不含空白',
              value: count(stats.charactersWithoutSpaces),
              allowCopy: false,
            ),
            ResultRow(
              label: 'UTF-16 单元',
              value: count(stats.codeUnits),
              allowCopy: false,
            ),
            ResultRow(
              label: 'UTF-8 字节',
              value: count(stats.utf8Bytes),
              allowCopy: false,
            ),
            ResultRow(
              label: 'UTF-16 字节',
              value: count(stats.utf16Bytes),
              allowCopy: false,
            ),
            ResultRow(
              label: '行数',
              value: '${count(stats.lines)}（非空 ${count(stats.nonEmptyLines)}）',
              allowCopy: false,
            ),
            ResultRow(
              label: '单词数',
              value: count(stats.words),
              allowCopy: false,
            ),
            ResultRow(
              label: '中文汉字',
              value: count(stats.cjkCharacters),
              allowCopy: false,
            ),
            ResultRow(
              label: '英文字母',
              value: count(stats.letters),
              allowCopy: false,
            ),
            ResultRow(
              label: '数字',
              value: count(stats.digits),
              allowCopy: false,
            ),
            ResultRow(
              label: '空白',
              value: count(stats.spaces),
              allowCopy: false,
            ),
            ResultRow(
              label: '其它符号',
              value: count(stats.punctuation),
              allowCopy: false,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Line processing (sort / dedupe / trim)
// ---------------------------------------------------------------------------

class TextLinesToolPage extends StatefulWidget {
  const TextLinesToolPage({super.key});

  static const String title = '行排序去重';
  static const String description = '按行排序、去重、去空白、删除空行并编号，结果可一键复制。';

  @override
  State<TextLinesToolPage> createState() => _TextLinesToolPageState();
}

class _TextLinesToolPageState extends State<TextLinesToolPage> {
  final _input = TextEditingController(
    text: '  banana\nApple\nbanana\n  apple \n\ncherry',
  );
  var _sort = OfflineLineSort.none;
  var _unique = true;
  var _trim = true;
  var _dropEmpty = true;
  var _ignoreCase = true;
  var _numbered = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputLines = OfflineLines.split(_input.text).length;
    final output = OfflineLines.process(
      _input.text,
      sort: _sort,
      unique: _unique,
      trim: _trim,
      dropEmpty: _dropEmpty,
      ignoreCase: _ignoreCase,
      numbered: _numbered,
    );
    final outputLines = OfflineLines.split(output).length;
    final duplicates = OfflineLines.duplicates(
      _input.text,
      ignoreCase: _ignoreCase,
    );
    return ToolScaffold(
      title: TextLinesToolPage.title,
      description: TextLinesToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: '输入（每行一条）',
          maxLines: 8,
          monospace: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<OfflineLineSort>(
            segments: const [
              ButtonSegment(value: OfflineLineSort.none, label: Text('原序')),
              ButtonSegment(
                value: OfflineLineSort.ascending,
                label: Text('升序'),
              ),
              ButtonSegment(
                value: OfflineLineSort.descending,
                label: Text('降序'),
              ),
              ButtonSegment(
                value: OfflineLineSort.lengthAscending,
                label: Text('短→长'),
              ),
              ButtonSegment(
                value: OfflineLineSort.lengthDescending,
                label: Text('长→短'),
              ),
            ],
            selected: {_sort},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _sort = selection.first),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('去重'),
              selected: _unique,
              onSelected: (value) => setState(() => _unique = value),
            ),
            FilterChip(
              label: const Text('去除首尾空白'),
              selected: _trim,
              onSelected: (value) => setState(() => _trim = value),
            ),
            FilterChip(
              label: const Text('删除空行'),
              selected: _dropEmpty,
              onSelected: (value) => setState(() => _dropEmpty = value),
            ),
            FilterChip(
              label: const Text('忽略大小写'),
              selected: _ignoreCase,
              onSelected: (value) => setState(() => _ignoreCase = value),
            ),
            FilterChip(
              label: const Text('添加行号'),
              selected: _numbered,
              onSelected: (value) => setState(() => _numbered = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ToolResultCard(
          title: '结果（输入 $inputLines 行，输出 $outputLines 行）',
          children: [
            ResultRow(label: '处理结果', value: output.isEmpty ? '（空）' : output),
            if (duplicates.isNotEmpty)
              ResultRow(
                label: '重复行',
                value: duplicates.entries
                    .map((entry) => '${entry.value}× ${entry.key}')
                    .join('\n'),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Case conversion
// ---------------------------------------------------------------------------

class CaseToolPage extends StatefulWidget {
  const CaseToolPage({super.key});

  static const String title = '命名风格';
  static const String description = '大小写、驼峰、下划线、短横线与全大写互转，适合变量名和文件名。';

  @override
  State<CaseToolPage> createState() => _CaseToolPageState();
}

class _CaseToolPageState extends State<CaseToolPage> {
  final _input = TextEditingController(text: 'user profile image URL');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _input.text;
    final variants = <String, String>{
      '大写': OfflineCasing.upper(text),
      '小写': OfflineCasing.lower(text),
      '标题': OfflineCasing.title(text),
      'camelCase': OfflineCasing.camel(text),
      'PascalCase': OfflineCasing.pascal(text),
      'snake_case': OfflineCasing.snake(text),
      'SCREAMING_SNAKE': OfflineCasing.screamingSnake(text),
      'kebab-case': OfflineCasing.kebab(text),
    };
    return ToolScaffold(
      title: CaseToolPage.title,
      description: CaseToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: '输入',
          maxLines: 3,
          monospace: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '转换结果',
          children: [
            for (final entry in variants.entries)
              ResultRow(
                label: entry.key,
                value: entry.value.isEmpty ? '（空）' : entry.value,
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HTML escaping
// ---------------------------------------------------------------------------

class HtmlEscapeToolPage extends StatefulWidget {
  const HtmlEscapeToolPage({super.key});

  static const String title = 'HTML 转义';
  static const String description =
      '把 < > & " \' 转成实体，或把实体还原为文本；可选非 ASCII 全部转实体。';

  @override
  State<HtmlEscapeToolPage> createState() => _HtmlEscapeToolPageState();
}

class _HtmlEscapeToolPageState extends State<HtmlEscapeToolPage> {
  final _input = TextEditingController(text: '<div class="a">中 & 文</div>');
  var _nonAscii = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final escaped = OfflineHtml.escape(_input.text, nonAscii: _nonAscii);
    return ToolScaffold(
      title: HtmlEscapeToolPage.title,
      description: HtmlEscapeToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: '输入',
          maxLines: 6,
          onChanged: (_) => setState(() {}),
        ),
        FilterChip(
          label: const Text('非 ASCII 字符转 &#x 实体'),
          selected: _nonAscii,
          onSelected: (value) => setState(() => _nonAscii = value),
        ),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '结果',
          children: [
            ResultRow(label: '转义', value: escaped),
            ResultRow(label: '还原', value: OfflineHtml.unescape(_input.text)),
            ResultRow(label: '还原已转义', value: OfflineHtml.unescape(escaped)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// JSON <-> CSV
// ---------------------------------------------------------------------------

class JsonCsvToolPage extends StatefulWidget {
  const JsonCsvToolPage({super.key});

  static const String title = 'JSON ⇄ CSV';
  static const String description =
      '把对象数组导出为 CSV（Excel 可打开的 CRLF 格式），或把 CSV 转回 JSON 数组。';

  @override
  State<JsonCsvToolPage> createState() => _JsonCsvToolPageState();
}

class _JsonCsvToolPageState extends State<JsonCsvToolPage> {
  final _input = TextEditingController(
    text:
        '[\n  {"id": 1, "name": "Alice", "tags": ["a"]},\n'
        '  {"id": 2, "name": "Bob, Jr.", "note": "say \\"hi\\""}\n]',
  );
  var _toCsv = true;
  var _inferTypes = true;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? output;
    String? error;
    try {
      output = _toCsv
          ? OfflineCsv.fromJson(_input.text)
          : OfflineCsv.fromCsv(_input.text, inferTypes: _inferTypes);
    } on FormatException catch (exception) {
      error = exception.message;
    }
    return ToolScaffold(
      title: JsonCsvToolPage.title,
      description: JsonCsvToolPage.description,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('JSON → CSV')),
            ButtonSegment(value: false, label: Text('CSV → JSON')),
          ],
          selected: {_toCsv},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => setState(() {
            _toCsv = selection.first;
            _input.text = _toCsv
                ? '[\n  {"id": 1, "name": "Alice", "tags": ["a"]},\n'
                      '  {"id": 2, "name": "Bob, Jr.", "note": "say \\"hi\\""}\n]'
                : 'id,name,note\n1,Alice,"say ""hi"""\n2,"Bob, Jr.",';
          }),
        ),
        ToolField(
          controller: _input,
          label: _toCsv ? 'JSON 输入' : 'CSV 输入',
          maxLines: 8,
          onChanged: (_) => setState(() {}),
        ),
        if (!_toCsv)
          FilterChip(
            label: const Text('数字/布尔自动识别类型'),
            selected: _inferTypes,
            onSelected: (value) => setState(() => _inferTypes = value),
          ),
        ToolError(error),
        const SizedBox(height: 16),
        ToolResultCard(
          title: '结果',
          children: [
            ResultRow(
              label: _toCsv ? 'CSV' : 'JSON',
              value: output ?? '（修正输入后可生成结果）',
              allowCopy: output != null,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// URL parser
// ---------------------------------------------------------------------------

class UrlParserToolPage extends StatefulWidget {
  const UrlParserToolPage({super.key});

  static const String title = 'URL 解析';
  static const String description = '拆解协议、主机、端口、路径与查询参数，编码参数会先解码再显示。';

  @override
  State<UrlParserToolPage> createState() => _UrlParserToolPageState();
}

class _UrlParserToolPageState extends State<UrlParserToolPage> {
  final _input = TextEditingController(
    text:
        'https://example.com:8443/a/b%20c?q=%E4%B8%AD%E6%96%87&tag=x&tag=y#top',
  );
  final _newKey = TextEditingController();
  final _newValue = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _newKey.dispose();
    _newValue.dispose();
    super.dispose();
  }

  OfflineUrlInfo? _parsed;
  String? _error;
  String? _rebuilt;

  void _parse() {
    try {
      final info = OfflineUrlInfo.parse(_input.text);
      setState(() {
        _parsed = info;
        _error = null;
        _rebuilt = null;
      });
    } on FormatException catch (exception) {
      setState(() {
        _parsed = null;
        _error = exception.message;
        _rebuilt = null;
      });
    }
  }

  void _addParameter() {
    final info = _parsed;
    if (info == null) return;
    final key = _newKey.text.trim();
    if (key.isEmpty) {
      setState(() => _error = '参数名不能为空');
      return;
    }
    final entries = <MapEntry<String, String?>>[
      ...info.parameters,
      MapEntry(key, _newValue.text),
    ];
    setState(() {
      _error = null;
      _rebuilt = info.withParameters(entries);
    });
  }

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  Widget build(BuildContext context) {
    final info = _parsed;
    return ToolScaffold(
      title: UrlParserToolPage.title,
      description: UrlParserToolPage.description,
      children: [
        ToolField(
          controller: _input,
          label: 'URL',
          maxLines: 3,
          onChanged: (_) => _parse(),
        ),
        ToolError(_error),
        const SizedBox(height: 16),
        if (info != null) ...[
          ToolResultCard(
            title: '组成',
            children: [
              for (final part in info.parts)
                ResultRow(label: part.label, value: part.value),
            ],
          ),
          const SizedBox(height: 12),
          ToolResultCard(
            title: '查询参数（已解码，${info.parameters.length} 个）',
            children: [
              if (info.parameters.isEmpty)
                const ResultRow(label: '提示', value: '该 URL 没有查询参数')
              else
                for (final parameter in info.parameters)
                  ResultRow(
                    label: parameter.key,
                    value: parameter.value ?? '（空值）',
                  ),
            ],
          ),
          const SizedBox(height: 12),
          Text('新增参数', style: Theme.of(context).textTheme.titleSmall),
          ToolField(controller: _newKey, label: '参数名', hint: '例如 page'),
          ToolField(controller: _newValue, label: '参数值', maxLines: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addParameter,
              icon: const Icon(Icons.add_link, size: 18),
              label: const Text('生成新 URL'),
            ),
          ),
          if (_rebuilt != null) ...[
            const SizedBox(height: 8),
            ToolResultCard(
              title: '新 URL',
              children: [ResultRow(label: 'URL', value: _rebuilt!)],
            ),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Line diff
// ---------------------------------------------------------------------------

class DiffToolPage extends StatefulWidget {
  const DiffToolPage({super.key});

  static const String title = '文本对比';
  static const String description = '按行比较两段文本，标出新增与删除的行，并按需忽略空白或大小写。';

  @override
  State<DiffToolPage> createState() => _DiffToolPageState();
}

class _DiffToolPageState extends State<DiffToolPage> {
  final _before = TextEditingController(text: 'alpha\nbeta\ngamma\ndelta');
  final _after = TextEditingController(
    text: 'alpha\nbeta changed\ngamma\ndelta\nepsilon',
  );
  var _ignoreWhitespace = false;
  var _ignoreCase = false;
  var _ignoreBlankLines = false;

  @override
  void dispose() {
    _before.dispose();
    _after.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diff = OfflineDiff.of(
      _before.text,
      _after.text,
      ignoreWhitespace: _ignoreWhitespace,
      ignoreCase: _ignoreCase,
      ignoreBlankLines: _ignoreBlankLines,
    );
    return ToolScaffold(
      title: DiffToolPage.title,
      description: DiffToolPage.description,
      children: [
        ToolField(
          controller: _before,
          label: '原文本',
          maxLines: 6,
          onChanged: (_) => setState(() {}),
        ),
        ToolField(
          controller: _after,
          label: '新文本',
          maxLines: 6,
          onChanged: (_) => setState(() {}),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('忽略空白差异'),
              selected: _ignoreWhitespace,
              onSelected: (value) => setState(() => _ignoreWhitespace = value),
            ),
            FilterChip(
              label: const Text('忽略大小写'),
              selected: _ignoreCase,
              onSelected: (value) => setState(() => _ignoreCase = value),
            ),
            FilterChip(
              label: const Text('忽略空行'),
              selected: _ignoreBlankLines,
              onSelected: (value) => setState(() => _ignoreBlankLines = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ToolResultCard(
          title: diff.identical
              ? '两段文本一致'
              : '删除 ${diff.removed} 行 · 新增 ${diff.added} 行'
                    '${diff.truncated ? '（内容过大，已改为整体替换视图）' : ''}',
          children: [
            ResultRow(label: '统一格式', value: diff.text),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 360),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in diff.lines)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        color: switch (line.kind) {
                          OfflineDiffKind.added =>
                            scheme.primaryContainer.withValues(alpha: 0.45),
                          OfflineDiffKind.removed =>
                            scheme.errorContainer.withValues(alpha: 0.45),
                          OfflineDiffKind.equal => Colors.transparent,
                        },
                        child: SelectableText(
                          '${line.prefix}${line.text}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.4,
                            color: switch (line.kind) {
                              OfflineDiffKind.added =>
                                scheme.onPrimaryContainer,
                              OfflineDiffKind.removed =>
                                scheme.onErrorContainer,
                              OfflineDiffKind.equal => scheme.onSurfaceVariant,
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

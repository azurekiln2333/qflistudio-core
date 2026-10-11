import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'editor_fonts.dart';

/// 各语言默认快捷符号（空格分隔，可多字符 token）。
const Map<String, List<String>> kDefaultSymbolSets = {
  'Java': [';', '{', '}', '(', ')', '[', ']', '"', "'", '<', '>', '='],
  'Python': [':', '(', ')', '[', ']', '"', "'", '#', '_', '='],
  'C': [';', '{', '}', '(', ')', '[', ']', '"', "'", '<', '>', '&', '*'],
  'C++': [';', '{', '}', '(', ')', '[', ']', '<', '>', '::', '"', "'"],
  'Web': ['<', '>', '/', '=', '"', ':', ';', '(', ')'],
  'Dart': [';', '{', '}', '(', ')', '[', ']', '"', "'", '<', '>', '=>', '_'],
  'Lua': ['(', ')', '[', ']', '{', '}', '"', "'", '=', '.', ':'],
  'JavaScript': [
    ';',
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '"',
    "'",
    '<',
    '>',
    '=',
    '=>',
  ],
  'TypeScript': [
    ';',
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '"',
    "'",
    '<',
    '>',
    '=',
    '=>',
  ],
  'Kotlin': [';', '{', '}', '(', ')', '[', ']', '"', "'", '=', '->', '?'],
  'Go': [';', '{', '}', '(', ')', '[', ']', '"', ':=', '<', '>', '&'],
  'Rust': [';', '{', '}', '(', ')', '[', ']', '"', '<', '>', '->', '::', '&'],
  'C#': [';', '{', '}', '(', ')', '[', ']', '"', "'", '<', '>', '=', '=>'],
  'PHP': [';', '{', '}', '(', ')', '[', ']', '"', "'", '<', '>', '=', '->'],
  'Ruby': ['(', ')', '[', ']', '{', '}', '"', "'", '#', '=', '|'],
  'JSON': ['{', '}', '[', ']', ':', ',', '"'],
  'HTML': ['<', '>', '/', '=', '"'],
};

/// 文件扩展名 → 语言名（与项目语言标注一致）。
String languageForFileName(String fileName) {
  final ext = fileName.contains('.')
      ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase()
      : '';
  const map = {
    '.py': 'Python',
    '.java': 'Java',
    '.c': 'C',
    '.h': 'C',
    '.cpp': 'C++',
    '.hpp': 'C++',
    '.cc': 'C++',
    '.html': 'Web',
    '.htm': 'Web',
    '.dart': 'Dart',
    '.lua': 'Lua',
    '.js': 'JavaScript',
    '.mjs': 'JavaScript',
    '.ts': 'TypeScript',
    '.tsx': 'TypeScript',
    '.kt': 'Kotlin',
    '.go': 'Go',
    '.rs': 'Rust',
    '.cs': 'C#',
    '.php': 'PHP',
    '.rb': 'Ruby',
    '.json': 'JSON',
  };
  return map[ext] ?? '';
}

/// 快捷符号栏：显示当前文件语言的常用符号，点击插入到光标处；
/// 长按任意符号进入快速编辑（增删改当前语言的符号集）。
class SymbolsBar extends StatelessWidget {
  const SymbolsBar({
    super.key,
    required this.language,
    required this.controller,
    required this.symbols,
    required this.onSymbolsEdited,
  });

  final String language;
  final CodeLineEditingController controller;
  final List<String> symbols;
  final ValueChanged<List<String>> onSymbolsEdited;

  void _insert(String symbol) {
    controller.replaceSelection(symbol);
  }

  Future<void> _editSymbols(BuildContext context) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SymbolEditorDialog(language: language, symbols: symbols),
    );
    if (result != null) {
      onSymbolsEdited(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (var i = 0; i < symbols.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Card.filled(
                        margin: EdgeInsets.zero,
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _insert(symbols[i]),
                          onLongPress: () => _editSymbols(context),
                          child: SizedBox(
                            height: 32,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Center(
                                child: Text(
                                  symbols[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: EditorFonts.bundledFamily,
                                    fontSize: 15,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: '编辑快捷符号',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
              onPressed: () => _editSymbols(context),
              icon: Icon(Icons.tune, size: 18, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SymbolEditorDialog extends StatefulWidget {
  const _SymbolEditorDialog({required this.language, required this.symbols});

  final String language;
  final List<String> symbols;

  @override
  State<_SymbolEditorDialog> createState() => _SymbolEditorDialogState();
}

class _SymbolEditorDialogState extends State<_SymbolEditorDialog> {
  late final List<String> _symbols = widget.symbols.toSet().toList();
  final _newSymbolController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _newSymbolController.dispose();
    super.dispose();
  }

  void _addSymbol() {
    final symbol = _newSymbolController.text.trim();
    if (symbol.isEmpty) return;
    if (symbol.contains(RegExp(r'\s'))) {
      setState(() => _error = '一次只能添加一个符号');
      return;
    }
    if (_symbols.contains(symbol)) {
      setState(() => _error = '该符号已存在');
      return;
    }
    setState(() {
      _symbols.add(symbol);
      _newSymbolController.clear();
      _error = null;
    });
  }

  Future<void> _renameSymbol(int index) async {
    final controller = TextEditingController(text: _symbols[index]);
    final renamed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('修改符号'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: const InputDecoration(labelText: '符号'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (renamed == null || !mounted) return;
    if (renamed.isEmpty || renamed.contains(RegExp(r'\s'))) {
      setState(() => _error = '请输入一个符号');
      return;
    }
    if (_symbols.asMap().entries.any(
      (entry) => entry.key != index && entry.value == renamed,
    )) {
      setState(() => _error = '该符号已存在');
      return;
    }
    setState(() {
      _symbols[index] = renamed;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 520
              ? constraints.maxWidth
              : 520.0;
          final height = constraints.maxHeight < 640
              ? constraints.maxHeight
              : 640.0;
          return SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '快捷符号 · ${widget.language}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _symbols.isEmpty
                        ? Center(
                            child: Text(
                              '暂无快捷符号',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            itemCount: _symbols.length,
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final symbol = _symbols.removeAt(oldIndex);
                                _symbols.insert(newIndex, symbol);
                              });
                            },
                            itemBuilder: (context, index) {
                              final symbol = _symbols[index];
                              return Padding(
                                key: ValueKey(symbol),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  clipBehavior: Clip.antiAlias,
                                  child: Row(
                                    children: [
                                      ReorderableDelayedDragStartListener(
                                        index: index,
                                        child: SizedBox(
                                          width: 48,
                                          height: 56,
                                          child: Tooltip(
                                            message: '拖动排序',
                                            child: Icon(
                                              Icons.drag_handle,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _renameSymbol(index),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            child: Text(
                                              symbol,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: scheme.primary,
                                                fontFamily:
                                                    EditorFonts.bundledFamily,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '修改符号',
                                        onPressed: () => _renameSymbol(index),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: '删除符号',
                                        onPressed: () => setState(
                                          () => _symbols.removeAt(index),
                                        ),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newSymbolController,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _addSymbol(),
                    decoration: InputDecoration(
                      labelText: '添加单个符号',
                      hintText: '如 =>',
                      errorText: _error,
                      suffixIcon: IconButton(
                        tooltip: '添加符号',
                        onPressed: _addSymbol,
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(_symbols),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

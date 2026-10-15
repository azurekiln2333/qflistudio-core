import 'package:flutter/material.dart';

import '../store/settings_store.dart';

/// 常用后缀（按类型分组的全集；项目语言相关的会排到最前）。
const List<String> kCommonFileExts = [
  '.py',
  '.java',
  '.c',
  '.h',
  '.cpp',
  '.hpp',
  '.html',
  '.css',
  '.js',
  '.ts',
  '.dart',
  '.lua',
  '.kt',
  '.go',
  '.rs',
  '.cs',
  '.php',
  '.rb',
  '.swift',
  '.json',
  '.xml',
  '.md',
  '.yaml',
  '.yml',
  '.toml',
  '.txt',
  '.sh',
  '.bat',
  '.sql',
  '.ini',
  '.vue',
];

/// 项目语言 → 优先后缀。
const Map<String, List<String>> kLanguageExts = {
  'Python': ['.py'],
  'Java': ['.java'],
  'C': ['.c', '.h'],
  'C++': ['.cpp', '.hpp', '.c'],
  'Web': ['.html', '.css', '.js'],
  'Dart': ['.dart'],
  'Lua': ['.lua'],
  'JavaScript': ['.js'],
  'TypeScript': ['.ts'],
  'Kotlin': ['.kt'],
  'Go': ['.go'],
  'Rust': ['.rs'],
  'C#': ['.cs'],
  'PHP': ['.php'],
  'Ruby': ['.rb'],
};

/// 后缀排序：项目语言后缀置顶 → 自定义后缀 → 其余常用后缀。
/// （导出供测试）
List<String> orderedExts({
  required String projectLanguage,
  required List<String> customExts,
}) {
  final priority = <String>[...?kLanguageExts[projectLanguage], ...customExts];
  final seen = <String>{};
  final result = <String>[];
  for (final ext in priority) {
    final normalized = ext.startsWith('.') ? ext : '.$ext';
    if (seen.add(normalized.toLowerCase())) result.add(normalized);
  }
  for (final ext in kCommonFileExts) {
    if (seen.add(ext.toLowerCase())) result.add(ext);
  }
  return result;
}

/// 新建文件对话框：输入名称 + 选择后缀类型。
/// 项目语言对应的后缀自动排在最上方；支持添加自定义后缀（持久化）。
/// 返回完整文件名（含后缀），取消返回 null。
Future<String?> showNewFileDialog(
  BuildContext context, {
  required SettingsStore settings,
  required String projectLanguage,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) =>
        _NewFileDialog(settings: settings, projectLanguage: projectLanguage),
  );
  final name = result?.trim() ?? '';
  if (name.isEmpty) return null;
  return name;
}

class _NewFileDialog extends StatefulWidget {
  const _NewFileDialog({required this.settings, required this.projectLanguage});

  final SettingsStore settings;
  final String projectLanguage;

  @override
  State<_NewFileDialog> createState() => _NewFileDialogState();
}

class _NewFileDialogState extends State<_NewFileDialog> {
  final _baseController = TextEditingController();
  late String _selectedExt;

  @override
  void initState() {
    super.initState();
    _selectedExt = orderedExts(
      projectLanguage: widget.projectLanguage,
      customExts: widget.settings.customFileExts,
    ).first;
  }

  @override
  void dispose() {
    // A dialog's result completes on pop, before its exit animation unmounts
    // the TextField. Keep its controller alive for that entire route lifetime.
    _baseController.dispose();
    super.dispose();
  }

  String _fullName() {
    final base = _baseController.text.trim();
    if (base.isEmpty) return '';
    return base.endsWith(_selectedExt) ? base : '$base$_selectedExt';
  }

  @override
  Widget build(BuildContext context) {
    final exts = orderedExts(
      projectLanguage: widget.projectLanguage,
      customExts: widget.settings.customFileExts,
    );

    return AlertDialog(
      scrollable: true,
      title: const Text('新建文件'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _baseController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '文件名（不含后缀）',
                prefixIcon: const Icon(Icons.edit_outlined),
                suffixText: _selectedExt,
                suffixStyle: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('文件类型', style: Theme.of(context).textTheme.labelMedium),
                const Spacer(),
                if (!exts.contains(_selectedExt))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text(_selectedExt),
                      onDeleted: () =>
                          setState(() => _selectedExt = exts.first),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final ext in exts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(ext),
                        selected: _selectedExt == ext,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _selectedExt = ext),
                      ),
                    ),
                  ActionChip(
                    label: const Text('+ 自定义'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final custom = await _askCustomExt(context);
                      if (custom == null || !mounted) return;
                      await widget.settings.addCustomFileExt(custom);
                      if (mounted) {
                        setState(
                          () => _selectedExt = custom.startsWith('.')
                              ? custom
                              : '.$custom',
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            if (_baseController.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '将创建：${_fullName()}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_fullName()),
          child: const Text('创建'),
        ),
      ],
    );
  }
}

Future<String?> _askCustomExt(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _CustomExtDialog(),
  );
}

class _CustomExtDialog extends StatefulWidget {
  const _CustomExtDialog();

  @override
  State<_CustomExtDialog> createState() => _CustomExtDialogState();
}

class _CustomExtDialogState extends State<_CustomExtDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('自定义后缀'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '后缀（如 md 或 .md）',
          prefixIcon: Icon(Icons.tag),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('添加'),
        ),
      ],
    );
  }
}

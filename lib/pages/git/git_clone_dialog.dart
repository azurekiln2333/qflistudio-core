import 'package:flutter/material.dart';

import '../../services/git_clone_service.dart';
import 'git_dialogs.dart';

/// Clone dialog for Home. Returns null when the user cancels.
Future<GitCloneRequest?> showGitCloneDialog(
  BuildContext context, {
  bool desktop = true,
}) {
  return showGitDialog<GitCloneRequest>(
    context: context,
    builder: (_) => _GitCloneDialog(desktop: desktop),
  );
}

class _GitCloneDialog extends StatefulWidget {
  const _GitCloneDialog({required this.desktop});

  final bool desktop;

  @override
  State<_GitCloneDialog> createState() => _GitCloneDialogState();
}

class _GitCloneDialogState extends State<_GitCloneDialog> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _token = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _username.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    final error = gitCloneUrlError(url, desktop: widget.desktop);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final name = _name.text.trim();
    if (name.isNotEmpty &&
        (name == '.' ||
            name == '..' ||
            RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name))) {
      setState(() => _error = '项目名称包含无效字符');
      return;
    }
    final token = _token.text;
    if (token.isNotEmpty && token.contains(RegExp(r'\s'))) {
      setState(() => _error = '令牌不能包含空白字符');
      return;
    }
    Navigator.of(context).pop(
      GitCloneRequest(
        url: url,
        name: name,
        username: _username.text.trim(),
        token: token,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      key: const ValueKey('git-clone-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('克隆 Git 仓库'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.desktop ? '克隆到应用项目目录，成功后注册项目。' : '移动端原生 Git 仅支持 HTTPS 地址。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('git-clone-url'),
            controller: _url,
            autofocus: widget.desktop,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '仓库地址',
              hintText: 'https://github.com/user/repo.git',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-clone-name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '项目名称',
              hintText: '留空则使用仓库名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('HTTPS 凭据（可选）', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            '仅用于本次克隆，不写入配置或日志。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-clone-username'),
            controller: _username,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-clone-token'),
            controller: _token,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '令牌',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('git-clone-error'),
              style: TextStyle(color: scheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('git-clone-confirm'),
          onPressed: _submit,
          child: const Text('克隆'),
        ),
      ],
    );
  }
}

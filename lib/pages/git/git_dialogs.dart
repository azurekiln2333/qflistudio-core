import 'package:flutter/material.dart';

import '../../git/git_backend.dart';
import '../../git/git_models.dart';
import '../../services/git_clone_service.dart';

/// Opens a Git dialog that stays usable when the keyboard shrinks the surface.
///
/// [AlertDialog] with `scrollable: true` owns the content scroll; this wrapper
/// lifts the dialog above the keyboard inset and animates the change so a field
/// under the cursor remains reachable on narrow devices.
Future<T?> showGitDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final insets = MediaQuery.viewInsetsOf(dialogContext);
      return AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: insets.bottom),
        child: builder(dialogContext),
      );
    },
  );
}

/// Small informational dialog with one clear dismissal.
Future<void> showGitAlert(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showGitDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// Returns a user-facing error for a branch name, or null when usable.
String? validateGitBranchName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return '请填写分支名';
  if (name.length > 200) return '分支名过长';
  if (name.startsWith('-') ||
      name.startsWith('/') ||
      name.endsWith('/') ||
      name.endsWith('.') ||
      name.contains('..') ||
      name.contains('//')) {
    return '分支名格式无效';
  }
  if (RegExp(r'[\x00-\x20\x7f~^:?*\[\\]').hasMatch(name)) {
    return '分支名不能包含空格或特殊字符';
  }
  return null;
}

/// Validated commit or merge-completion input.
class GitCommitInput {
  const GitCommitInput({required this.message, required this.identity});

  final String message;
  final GitIdentity identity;
}

/// Commit message plus explicit author identity.
///
/// The dialog makes the index-only rule visible instead of auto-staging.
Future<GitCommitInput?> showGitCommitDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required String note,
  GitIdentity? initialIdentity,
  String initialMessage = '',
}) {
  return showGitDialog<GitCommitInput>(
    context: context,
    builder: (_) => _GitCommitDialog(
      title: title,
      confirmLabel: confirmLabel,
      note: note,
      initialIdentity: initialIdentity,
      initialMessage: initialMessage,
    ),
  );
}

/// Standalone author identity prompt for merge and branch operations.
Future<GitIdentity?> showGitIdentityDialog(
  BuildContext context, {
  GitIdentity? initialIdentity,
}) {
  return showGitDialog<GitIdentity>(
    context: context,
    builder: (_) => _GitIdentityDialog(initialIdentity: initialIdentity),
  );
}

class _GitCommitDialog extends StatefulWidget {
  const _GitCommitDialog({
    required this.title,
    required this.confirmLabel,
    required this.note,
    required this.initialMessage,
    this.initialIdentity,
  });

  final String title;
  final String confirmLabel;
  final String note;
  final String initialMessage;
  final GitIdentity? initialIdentity;

  @override
  State<_GitCommitDialog> createState() => _GitCommitDialogState();
}

class _GitCommitDialogState extends State<_GitCommitDialog> {
  late final TextEditingController _message = TextEditingController(
    text: widget.initialMessage,
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.initialIdentity?.name ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.initialIdentity?.email ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final message = _message.text.trim();
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (message.isEmpty) {
      setState(() => _error = '请填写提交信息');
      return;
    }
    if (name.isEmpty || email.isEmpty || !_validEmail(email)) {
      setState(() => _error = '请填写提交作者和有效邮箱');
      return;
    }
    Navigator.of(context).pop(
      GitCommitInput(
        message: message,
        identity: GitIdentity(name: name, email: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('git-commit-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.title),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.note,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('git-commit-message'),
            controller: _message,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: '提交信息',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('提交作者', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-identity-name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '姓名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-identity-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '邮箱',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const ValueKey('git-commit-error'),
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
          key: const ValueKey('git-commit-confirm'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _GitIdentityDialog extends StatefulWidget {
  const _GitIdentityDialog({this.initialIdentity});

  final GitIdentity? initialIdentity;

  @override
  State<_GitIdentityDialog> createState() => _GitIdentityDialogState();
}

class _GitIdentityDialogState extends State<_GitIdentityDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialIdentity?.name ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.initialIdentity?.email ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty || !_validEmail(email)) {
      setState(() => _error = '请填写提交作者和有效邮箱');
      return;
    }
    Navigator.of(context).pop(GitIdentity(name: name, email: email));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('git-identity-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('设置提交作者'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('作者只用于本地提交签名，不上传服务器。'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('git-identity-name'),
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '姓名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-identity-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '邮箱',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          key: const ValueKey('git-identity-confirm'),
          onPressed: _submit,
          child: const Text('继续'),
        ),
      ],
    );
  }
}

class GitDiffDialog extends StatelessWidget {
  const GitDiffDialog({super.key, required this.path, required this.data});

  final String path;
  final GitDiffData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = <String>[
      if (data.binary) '二进制文件，无法显示文本差异',
      if (data.truncated) '差异过大，仅显示前一部分',
      if (!data.binary && data.patch.trim().isEmpty) '没有可显示的差异',
    ];
    return AlertDialog(
      key: const ValueKey('git-diff-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text('差异 · $path', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final note in notes) ...[
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
            const SizedBox(height: 8),
          ],
          if (!data.binary && data.patch.isNotEmpty)
            SelectableText(
              data.patch,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.45,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class GitHistoryDialog extends StatelessWidget {
  const GitHistoryDialog({super.key, required this.commits, this.error});

  final List<GitCommitInfo> commits;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      key: const ValueKey('git-history-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: const Text('提交历史'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            Text(error!, style: TextStyle(color: scheme.error)),
          if (error == null && commits.isEmpty) const Text('还没有提交'),
          for (final commit in commits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    commit.message.trim().split('\n').first,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_shortOid(commit.oid)} · ${commit.authorName} · '
                    '${_formatTime(commit.time)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// Branch selection action returned by [showGitBranchesDialog].
class GitBranchChoice {
  const GitBranchChoice.checkout(this.name) : create = false;
  const GitBranchChoice.create() : name = null, create = true;

  final String? name;
  final bool create;
}

Future<GitBranchChoice?> showGitBranchesDialog(
  BuildContext context, {
  required List<GitBranchInfo> branches,
  required String? current,
}) {
  return showGitDialog<GitBranchChoice>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final scheme = theme.colorScheme;
      final local = branches.where((branch) => !branch.remote).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final remote = branches.where((branch) => branch.remote).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return AlertDialog(
        key: const ValueKey('git-branches-dialog'),
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('分支'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current == null ? '当前没有提交（空仓库）' : '当前分支：$current',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final branch in local)
              ListTile(
                key: ValueKey('git-branch-${branch.name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  branch.current
                      ? Icons.check_circle_outline
                      : Icons.call_split_outlined,
                  size: 20,
                ),
                title: Text(branch.name),
                subtitle: branch.upstream == null
                    ? null
                    : Text('跟踪 ${branch.upstream}'),
                onTap: () => Navigator.of(
                  dialogContext,
                ).pop(GitBranchChoice.checkout(branch.name)),
              ),
            if (local.isEmpty) const Text('还没有本地分支'),
            if (remote.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('远端分支', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                '远端引用只用于合并，不能直接切换。需要跟踪时先新建本地分支。',
                key: const ValueKey('git-remote-branch-note'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final branch in remote)
                ListTile(
                  key: ValueKey('git-remote-branch-${branch.name}'),
                  dense: true,
                  enabled: false,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_outlined, size: 20),
                  title: Text(branch.name),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('git-branch-create'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(const GitBranchChoice.create()),
            child: const Text('新建分支'),
          ),
        ],
      );
    },
  );
}

Future<String?> showGitBranchNameDialog(BuildContext context) {
  return showGitDialog<String>(
    context: context,
    builder: (_) => const _GitTextPromptDialog(
      dialogKey: ValueKey('git-branch-name-dialog'),
      title: '新建分支',
      label: '分支名',
      confirmLabel: '创建',
      validator: validateGitBranchName,
    ),
  );
}

Future<String?> showGitMergeDialog(
  BuildContext context, {
  required List<GitBranchInfo> branches,
  required String? currentBranch,
}) {
  final candidates =
      branches
          .where((branch) => branch.remote || branch.upstream != null)
          .map((branch) => branch.name)
          .toSet()
          .toList()
        ..sort();
  final suggested = currentBranch == null ? null : 'origin/$currentBranch';
  return showGitDialog<String>(
    context: context,
    builder: (_) =>
        _GitMergeDialog(candidates: candidates, suggested: suggested),
  );
}

class _GitMergeDialog extends StatefulWidget {
  const _GitMergeDialog({required this.candidates, this.suggested});

  final List<String> candidates;
  final String? suggested;

  @override
  State<_GitMergeDialog> createState() => _GitMergeDialogState();
}

class _GitMergeDialogState extends State<_GitMergeDialog> {
  late final TextEditingController _ref = TextEditingController(
    text: widget.candidates.isNotEmpty
        ? widget.candidates.first
        : (widget.suggested ?? ''),
  );
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final ref = value.trim();
    final error = validateGitBranchName(ref);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      key: const ValueKey('git-merge-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('合并分支'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '先获取远端，再选择要合并的分支。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (widget.candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final name in widget.candidates)
              ListTile(
                key: ValueKey('git-merge-ref-$name'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                onTap: () => _submit(name),
              ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-merge-ref'),
            controller: _ref,
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
            decoration: const InputDecoration(
              labelText: '合并目标',
              border: OutlineInputBorder(),
              hintText: 'origin/main',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('git-merge-confirm'),
          onPressed: () => _submit(_ref.text),
          child: const Text('合并'),
        ),
      ],
    );
  }
}

/// Remote name and URL input.
class GitRemoteInput {
  const GitRemoteInput({required this.name, required this.url});

  final String name;
  final String url;
}

Future<GitRemoteInput?> showGitRemoteDialog(
  BuildContext context, {
  List<GitRemoteInfo> existing = const [],
}) {
  return showGitDialog<GitRemoteInput>(
    context: context,
    builder: (_) => _GitRemoteDialog(existing: existing),
  );
}

class _GitRemoteDialog extends StatefulWidget {
  const _GitRemoteDialog({required this.existing});

  final List<GitRemoteInfo> existing;

  @override
  State<_GitRemoteDialog> createState() => _GitRemoteDialogState();
}

class _GitRemoteDialogState extends State<_GitRemoteDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing.isEmpty ? 'origin' : widget.existing.first.name,
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.existing.isEmpty ? '' : widget.existing.first.url,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || RegExp(r'[\x00-\x20~^:?*\[\\@]').hasMatch(name)) {
      setState(() => _error = '远程名称无效');
      return;
    }
    final urlError = validateGitRemoteUrl(url);
    if (urlError != null) {
      setState(() => _error = urlError);
      return;
    }
    Navigator.of(context).pop(GitRemoteInput(name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('git-remote-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('远程仓库'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('地址不保存用户名或令牌。'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('git-remote-name'),
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-remote-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '仓库地址',
              hintText: 'https://github.com/user/repo.git',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('git-remote-save'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// Result of the HTTPS credential prompt.
///
/// `proceed == false` means the user cancelled the network operation.
class GitCredentialPrompt {
  const GitCredentialPrompt.cancelled() : proceed = false, credentials = null;
  const GitCredentialPrompt.anonymous() : proceed = true, credentials = null;

  const GitCredentialPrompt.credentials(this.credentials) : proceed = true;

  final bool proceed;
  final GitCredentials? credentials;
}

/// Collects an HTTPS username/token for exactly one page session.
///
/// The token field is masked and returned only in memory. The dialog never
/// writes to disk, a URL or the operation log.
Future<GitCredentialPrompt?> showGitCredentialsDialog(
  BuildContext context, {
  String initialUsername = '',
}) {
  return showGitDialog<GitCredentialPrompt>(
    context: context,
    builder: (_) => _GitCredentialsDialog(initialUsername: initialUsername),
  );
}

class _GitCredentialsDialog extends StatefulWidget {
  const _GitCredentialsDialog({required this.initialUsername});

  final String initialUsername;

  @override
  State<_GitCredentialsDialog> createState() => _GitCredentialsDialogState();
}

class _GitCredentialsDialogState extends State<_GitCredentialsDialog> {
  late final TextEditingController _username = TextEditingController(
    text: widget.initialUsername,
  );
  final TextEditingController _token = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final token = _token.text;
    if (token.isEmpty) {
      setState(() => _error = '请填写令牌，或选择匿名获取');
      return;
    }
    Navigator.of(context).pop(
      GitCredentialPrompt.credentials(
        GitCredentials(username: username, token: token),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('git-credentials-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('HTTPS 凭据'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('凭据只用于本次页面操作，不写入配置或日志。'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('git-credential-username'),
            controller: _username,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('git-credential-token'),
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
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const GitCredentialPrompt.cancelled()),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('git-credential-anonymous'),
          onPressed: () =>
              Navigator.of(context).pop(const GitCredentialPrompt.anonymous()),
          child: const Text('匿名'),
        ),
        FilledButton(
          key: const ValueKey('git-credential-use'),
          onPressed: _submit,
          child: const Text('使用'),
        ),
      ],
    );
  }
}

class _GitTextPromptDialog extends StatefulWidget {
  const _GitTextPromptDialog({
    required this.dialogKey,
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.validator,
  });

  final Key dialogKey;
  final String title;
  final String label;
  final String confirmLabel;
  final String? Function(String value) validator;

  @override
  State<_GitTextPromptDialog> createState() => _GitTextPromptDialogState();
}

class _GitTextPromptDialogState extends State<_GitTextPromptDialog> {
  final TextEditingController _value = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _value.text.trim();
    final error = widget.validator(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: widget.dialogKey,
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _value,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

bool _validEmail(String email) =>
    !email.contains(RegExp(r'\s')) &&
    RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(email);

String _shortOid(String oid) => oid.length <= 8 ? oid : oid.substring(0, 8);

String _formatTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

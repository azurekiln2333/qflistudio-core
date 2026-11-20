import 'dart:io';

import 'package:flutter/material.dart';

import '../editor/editor_fonts.dart';
import '../git/git_backend.dart';
import '../models/project.dart';
import '../services/api_client.dart';
import '../services/cloud_sync_service.dart';
import '../store/auth_store.dart';
import 'git/git_local_view.dart';
import 'git/git_worktree_guard.dart';

/// Git 页。
///
/// - 云端项目：沿用服务器 Git 操作（整目录暂存后提交）。
/// - 本地项目：使用 [GitBackend]（桌面 CLI / 移动原生插件）的真实仓库界面。
class GitPage extends StatefulWidget {
  const GitPage({
    super.key,
    required this.project,
    required this.auth,
    this.backend,
    this.beforeWorktreeChange,
    this.onWorktreeChanged,
  });

  final Project project;
  final AuthStore auth;

  /// Injected local backend; omitted in production so the factory selects the
  /// platform adapter. Cloud projects never create one.
  final GitBackend? backend;

  /// Editor hook: refuse checkout/merge/pull while affected buffers are dirty.
  final GitWorktreeGuard? beforeWorktreeChange;

  /// Editor hook: refresh tree and reload clean buffers after disk changes.
  final GitWorktreeChanged? onWorktreeChanged;

  @override
  State<GitPage> createState() => _GitPageState();
}

class _GitPageState extends State<GitPage> {
  CloudSyncService? _cloud;
  final List<_TermLine> _lines = [];
  final _listController = ScrollController();
  final _commitController = TextEditingController();
  final _remoteController = TextEditingController();
  bool _cloudBusy = false;

  GitBackend? _localBackend;
  String? _localSetupError;

  bool get _cloudMode => widget.project.isCloud;

  @override
  void initState() {
    super.initState();
    if (_cloudMode) return;
    if (widget.backend != null) {
      _localBackend = widget.backend;
      return;
    }
    try {
      _localBackend = GitBackendFactory.open(widget.project.path);
    } on GitOperationException catch (error) {
      _localSetupError = error.message;
    } on Object catch (error) {
      _localSetupError = '无法打开本地 Git：$error';
    }
  }

  @override
  void dispose() {
    _cloud?.dispose();
    _commitController.dispose();
    _remoteController.dispose();
    _listController.dispose();
    super.dispose();
  }

  void _append(String text, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _lines.add(_TermLine(text: text, isError: isError));
      if (_lines.length > 400) _lines.removeRange(0, _lines.length - 400);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listController.hasClients) return;
      _listController.jumpTo(_listController.position.maxScrollExtent);
    });
  }

  Future<void> _runCloud(String action, {String? message, String? url}) async {
    if (_cloudBusy) return;
    final token = widget.auth.token;
    if (token == null) {
      _append('云端 git 需要先登录', isError: true);
      return;
    }
    setState(() => _cloudBusy = true);
    final suffix = message == null ? '' : ' "$message"';
    _append('git $action$suffix');
    try {
      final cloud = _cloud ??= await CloudSyncService.open(
        cloudId: widget.project.cloudId!,
        cachePath: widget.project.path,
        name: widget.project.name,
      );
      final result = await cloud.git(token, action, message: message, url: url);
      if (!mounted) return;
      if (result.stdout.trim().isNotEmpty) _append(result.stdout.trimRight());
      if (result.stderr.trim().isNotEmpty) {
        _append(result.stderr.trimRight(), isError: true);
      }
      _append(result.exitCode == 0 ? '（完成）' : '（退出码 ${result.exitCode}）');
    } on ApiException catch (error) {
      if (mounted) _append(error.message, isError: true);
    } on FileSystemException catch (error) {
      if (mounted) _append('本地镜像打开失败：${error.message}', isError: true);
    } on Object catch (error) {
      if (mounted) _append('云端 git 失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _commitDialog() async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('提交到云端 Git'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('服务器会先暂存整个项目，再提交。'),
            const SizedBox(height: 12),
            TextField(
              controller: _commitController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '提交信息',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_commitController.text),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (message == null || message.trim().isEmpty || !mounted) return;
    await _runCloud('addAll');
    if (!mounted) return;
    await _runCloud('commit', message: message.trim());
    if (!mounted) return;
    _commitController.clear();
  }

  Future<void> _remoteDialog() async {
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('设置云端远程仓库'),
        content: TextField(
          controller: _remoteController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '仓库地址（https）',
            prefixIcon: Icon(Icons.link_outlined),
            hintText: 'https://github.com/user/repo.git',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_remoteController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    await _runCloud('remote', url: url.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Git · ${widget.project.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _cloudMode ? _buildCloudBody(context) : _buildLocalBody(context),
    );
  }

  Widget _buildLocalBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final setupError = _localSetupError;
    if (setupError != null || _localBackend == null) {
      return ListView(
        key: const ValueKey('git-local-unsupported'),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本地 Git 不可用',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    setupError ?? '当前平台无法创建本地 Git 后端',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '云端项目仍可使用服务器 Git。',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return GitLocalRepositoryView(
      project: widget.project,
      backend: _localBackend!,
      beforeWorktreeChange: widget.beforeWorktreeChange,
      onWorktreeChanged: widget.onWorktreeChanged,
    );
  }

  Widget _buildCloudBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '云端项目 · 服务器执行 git（整目录暂存后提交）',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('git-cloud-commit'),
                onPressed: _cloudBusy ? null : _commitDialog,
                icon: const Icon(Icons.commit_outlined, size: 18),
                label: const Text('提交'),
              ),
              OutlinedButton(
                key: const ValueKey('git-cloud-status'),
                onPressed: _cloudBusy ? null : () => _runCloud('status'),
                child: const Text('状态'),
              ),
              OutlinedButton(
                key: const ValueKey('git-cloud-log'),
                onPressed: _cloudBusy ? null : () => _runCloud('log'),
                child: const Text('历史'),
              ),
              OutlinedButton(
                key: const ValueKey('git-cloud-remote'),
                onPressed: _cloudBusy ? null : _remoteDialog,
                child: const Text('远程仓库'),
              ),
              OutlinedButton(
                key: const ValueKey('git-cloud-push'),
                onPressed: _cloudBusy ? null : () => _runCloud('push'),
                child: const Text('推送'),
              ),
              OutlinedButton(
                key: const ValueKey('git-cloud-pull'),
                onPressed: _cloudBusy ? null : () => _runCloud('pull'),
                child: const Text('拉取'),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        Expanded(
          child: _lines.isEmpty
              ? Center(
                  child: Text(
                    '选择上面的云端 git 操作，输出会显示在这里',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _listController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) => SelectableText(
                    _lines[index].text,
                    style: TextStyle(
                      fontFamily: EditorFonts.bundledFamily,
                      fontFamilyFallback: EditorFonts.fallbacks,
                      fontSize: 12.5,
                      height: 1.45,
                      color: _lines[index].isError
                          ? scheme.error
                          : scheme.onSurface,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TermLine {
  const _TermLine({required this.text, required this.isError});

  final String text;
  final bool isError;
}

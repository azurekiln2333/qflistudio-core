import 'package:flutter/material.dart';

import '../../chat/attachment_picker.dart';
import '../../chat/composer_card.dart';
import '../../chat/composer_draft.dart';
import '../../chat/composer_state.dart';
import '../../models/project.dart';
import '../../session/agent_session.dart';
import '../../shell/login_gate.dart';
import '../../store/auth_store.dart';
import '../../vibe_coding/vibe_agent_facade.dart';
import '../../workspace/workspace_store.dart';
import '../auth/login_page.dart';

/// 项目页：会话列表加底部输入卡片。
///
/// 发送第一条消息时创建会话，并把这条消息交给工作台执行，见 design.md §3。
class ProjectPage extends StatefulWidget {
  const ProjectPage({
    super.key,
    required this.project,
    required this.runtime,
    required this.auth,
    this.workspaces,
    this.composerDefaults,
    this.onOpenSession,
    this.onOpenEditor,
  });

  final Project project;
  final AgentRuntime runtime;
  final AuthStore auth;

  /// 工作区文件来源；为 null 时加号只提供项目文件。
  final WorkspaceStore? workspaces;

  /// 每个项目记住的输入卡片选择；为 null 时不持久化。
  final ComposerDefaultsStore? composerDefaults;

  /// 进入工作台打开该会话。返回 false 表示没有进入（消息保留在输入框）。
  final Future<bool> Function(String sessionId, ComposerDraft draft)?
  onOpenSession;

  /// 打开该项目的编辑器。
  final VoidCallback? onOpenEditor;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  late final ComposerState _composer;
  List<AgentModelOption> _models = const [];
  List<AgentSkillRef> _skills = const [];
  bool _loginRequired = false;
  bool _loadingOptions = false;

  @override
  void initState() {
    super.initState();
    _composer = ComposerState(
      defaults: widget.composerDefaults,
      projectId: widget.project.id,
      projectRoot: widget.project.path,
    );
    _composer.bindProject(widget.project.id, projectRoot: widget.project.path);
    widget.auth.addListener(_onAuthChanged);
    _loadOptions();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    _composer.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {});
    _loadOptions();
  }

  /// 模型与技能是登录后才有的能力；未登录时安静地停在引导态，不弹错误。
  Future<void> _loadOptions() async {
    if (!widget.auth.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _models = const [];
        _skills = const [];
        _loginRequired = true;
      });
      return;
    }
    setState(() => _loadingOptions = true);
    try {
      final models = await widget.runtime.models();
      final skills = await widget.runtime.skills(widget.project.id);
      if (!mounted) return;
      setState(() {
        _models = models;
        _skills = skills;
        _loginRequired = false;
        _loadingOptions = false;
      });
    } on AgentLoginRequired {
      if (!mounted) return;
      setState(() {
        _models = const [];
        _skills = const [];
        _loginRequired = true;
        _loadingOptions = false;
      });
    }
  }

  /// 已登录返回 true。没有 LoginGateScope 时直接打开登录页。
  Future<bool> _ensureLoggedIn() async {
    if (widget.auth.isLoggedIn) return true;
    if (LoginGateScope.maybeAuthOf(context) != null) {
      final ok = await ensureLoggedIn(context);
      if (ok) await _loadOptions();
      return ok;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginPage(auth: widget.auth)),
    );
    if (ok == true && widget.auth.isLoggedIn) {
      await _loadOptions();
      return true;
    }
    return false;
  }

  Future<bool> _send(String text, List<String> attachments) async {
    if (!await _ensureLoggedIn()) return false;
    final meta = await widget.runtime.sessions.create(widget.project.id);
    final open = widget.onOpenSession;
    final draft = ComposerDraft(text: text, attachments: attachments);
    if (open == null) {
      if (!mounted) return true;
      _snack('已创建会话「${meta.title}」，打开工作台即可继续发送。');
      return true;
    }
    return open(meta.id, draft);
  }

  Future<void> _openSession(String sessionId) async {
    if (!await _ensureLoggedIn()) return;
    await widget.onOpenSession?.call(sessionId, ComposerDraft.empty);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createSession() async {
    if (!await _ensureLoggedIn()) return;
    final meta = await widget.runtime.sessions.create(widget.project.id);
    if (!mounted) return;
    _snack('已创建「${meta.title}」');
  }

  Future<void> _rename(AgentSessionMeta meta) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialTitle: meta.title),
    );
    if (title == null || title.trim().isEmpty) return;
    await widget.runtime.sessions.rename(meta.id, title);
  }

  Future<void> _delete(AgentSessionMeta meta) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('「${meta.title}」的消息会一起删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('session-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.runtime.sessions.delete(meta.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.onOpenEditor != null)
            IconButton(
              tooltip: '编辑器',
              onPressed: widget.onOpenEditor,
              icon: const Icon(Icons.code),
            ),
          IconButton(
            tooltip: '新建会话',
            key: const ValueKey('project-new-session'),
            onPressed: widget.auth.isLoggedIn
                ? _createSession
                : _ensureLoggedIn,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !widget.auth.isLoggedIn || _loginRequired
                ? Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: LoginGuideCard(),
                      ),
                    ),
                  )
                : _buildSessionList(context, scheme),
          ),
          if (widget.auth.isLoggedIn && !_loginRequired)
            AnimatedBuilder(
              animation: widget.runtime.sessions,
              builder: (context, _) => ComposerCard(
                state: _composer,
                onSend: _send,
                models: _models,
                skills: _skills,
                enabled: !_loadingOptions,
                hintText: '描述要改什么。发送后进入工作台。',
                onPickAttachments: (source) => showAttachmentPicker(
                  context,
                  source: source,
                  projectRoot: widget.project.path,
                  workspaces: widget.workspaces ?? WorkspaceStore.instance,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionList(BuildContext context, ColorScheme scheme) {
    final store = widget.runtime.sessions;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final sessions = store.sessionsOf(widget.project.id);
        if (sessions.isEmpty) return _buildEmpty(context, scheme);
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final meta = sessions[index];
            return ListTile(
              key: ValueKey('session-${meta.id}'),
              minVerticalPadding: 12,
              leading: Icon(Icons.forum_outlined, color: scheme.primary),
              title: Text(
                meta.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _relativeTime(meta.updatedAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onTap: () => _openSession(meta.id),
              trailing: PopupMenuButton<String>(
                tooltip: '会话操作',
                key: ValueKey('session-menu-${meta.id}'),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'rename',
                    height: 44,
                    child: Text('重命名'),
                  ),
                  PopupMenuItem(value: 'delete', height: 44, child: Text('删除')),
                ],
                onSelected: (action) {
                  if (action == 'rename') _rename(meta);
                  if (action == 'delete') _delete(meta);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 30,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('这个项目还没有会话', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '在下面的输入卡片里描述要改什么，发送后会创建一个会话并进入工作台。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 相对时间，够近的用「刚刚 / N 分钟前」，更早显示日期。
  static String _relativeTime(DateTime time) {
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return '刚刚';
    if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
    if (delta.inDays < 1) return '${delta.inHours} 小时前';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }
}

/// 重命名会话。
///
/// 控制器由弹窗自己持有并释放：对话框在退场动画期间还在树上，
/// 在外面 await 完就 dispose 会撞上“已释放的控制器还在使用”。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名会话'),
      content: TextField(
        key: const ValueKey('session-rename-input'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '会话名称'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('session-rename-confirm'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../models/project.dart';
import '../session/agent_session.dart';
import 'share_inbox.dart';

/// 用户在选择面板里做的决定。
@immutable
sealed class ShareIntakeChoice {
  const ShareIntakeChoice();
}

/// 放进项目。
class ShareIntakeIntoProject extends ShareIntakeChoice {
  const ShareIntakeIntoProject(this.project);

  final Project project;
}

/// 附到会话。[sessionId] 为空表示新建会话。
class ShareIntakeIntoSession extends ShareIntakeChoice {
  const ShareIntakeIntoSession(this.project, this.sessionId);

  final Project project;
  final String? sessionId;
}

/// 打开选择面板。用户取消时返回 null。
Future<ShareIntakeChoice?> showShareIntakeSheet(
  BuildContext context, {
  required ShareInboxBatch batch,
  required List<Project> projects,
  required List<AgentSessionMeta> Function(String projectId) sessionsOf,
}) {
  return showModalBottomSheet<ShareIntakeChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ShareIntakeSheet(
      batch: batch,
      projects: projects,
      sessionsOf: sessionsOf,
    ),
  );
}

/// 选择面板：先选去处，再选项目，附到会话时再选会话。
class ShareIntakeSheet extends StatefulWidget {
  const ShareIntakeSheet({
    super.key,
    required this.batch,
    required this.projects,
    required this.sessionsOf,
  });

  final ShareInboxBatch batch;
  final List<Project> projects;
  final List<AgentSessionMeta> Function(String projectId) sessionsOf;

  @override
  State<ShareIntakeSheet> createState() => _ShareIntakeSheetState();
}

enum _Step { destination, project, session }

class _ShareIntakeSheetState extends State<ShareIntakeSheet> {
  _Step _step = _Step.destination;
  bool _intoSession = false;
  Project? _project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            key: const ValueKey('share-intake-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '收到 ${widget.batch.files.length} 个文件',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                _summary(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  String _summary() => [
    for (final file in widget.batch.files.take(4)) file.name,
    if (widget.batch.files.length > 4) '…',
  ].join('、');

  Widget _body(BuildContext context) {
    return switch (_step) {
      _Step.destination => _destinations(context),
      _Step.project => _projects(context),
      _Step.session => _sessions(context),
    };
  }

  Widget _destinations(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          key: const ValueKey('share-intake-into-project'),
          leading: const Icon(Icons.folder_outlined),
          title: const Text('放进项目'),
          subtitle: const Text('复制到项目的 inbox 目录'),
          onTap: () => setState(() {
            _intoSession = false;
            _step = _Step.project;
          }),
        ),
        ListTile(
          key: const ValueKey('share-intake-into-session'),
          leading: const Icon(Icons.chat_bubble_outline),
          title: const Text('附到 Agent 会话'),
          subtitle: const Text('打开编辑器，附件进入输入卡片'),
          onTap: () => setState(() {
            _intoSession = true;
            _step = _Step.project;
          }),
        ),
        ListTile(
          key: const ValueKey('share-intake-cancel'),
          leading: const Icon(Icons.close),
          title: const Text('取消'),
          subtitle: const Text('文件留在收件箱，7 天内可再处理'),
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _projects(BuildContext context) {
    if (widget.projects.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('还没有项目。先建一个项目，再分享文件。'),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final project in widget.projects)
          ListTile(
            key: ValueKey('share-intake-project-${project.id}'),
            leading: Icon(
              project.isCloud ? Icons.cloud_outlined : Icons.folder_outlined,
            ),
            title: Text(project.name),
            subtitle: Text(
              project.language.isEmpty ? project.type : project.language,
            ),
            onTap: () {
              _project = project;
              if (!_intoSession) {
                Navigator.of(context).pop(ShareIntakeIntoProject(project));
                return;
              }
              setState(() => _step = _Step.session);
            },
          ),
      ],
    );
  }

  Widget _sessions(BuildContext context) {
    final project = _project;
    if (project == null) return const SizedBox.shrink();
    final sessions = widget.sessionsOf(project.id);
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          key: const ValueKey('share-intake-new-session'),
          leading: const Icon(Icons.add_comment_outlined),
          title: const Text('新建会话'),
          onTap: () =>
              Navigator.of(context).pop(ShareIntakeIntoSession(project, null)),
        ),
        for (final session in sessions)
          ListTile(
            key: ValueKey('share-intake-session-${session.id}'),
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(session.title),
            subtitle: Text(session.preview.isEmpty ? '空会话' : session.preview),
            onTap: () => Navigator.of(
              context,
            ).pop(ShareIntakeIntoSession(project, session.id)),
          ),
      ],
    );
  }
}

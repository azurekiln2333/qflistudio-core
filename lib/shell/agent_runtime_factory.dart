import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../services/api_client.dart';
import '../services/app_paths.dart';
import '../session/agent_session.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import '../vibe_coding/vibe_agent_facade.dart';

AgentRuntime? _cached;

/// 应用级 [AgentRuntime] 单例。
///
/// 沿用现有 store 的构造注入风格：这里只做一次装配，界面层通过参数拿到。
/// 会话落在应用数据目录的 `agent_sessions/` 下。
Future<AgentRuntime> studioAgentRuntime({
  required AuthStore auth,
  required ProjectStore store,
  required SettingsStore settings,
}) async {
  if (_cached case final cached?) return cached;

  final base = await AppPaths.storageDirectory();
  final sessions = FileAgentSessionStore(
    root: Directory(
      base == null ? 'agent_sessions' : p.join(base, 'agent_sessions'),
    ),
  );
  await sessions.load();

  Project? find(String projectId) {
    for (final project in store.projects) {
      if (project.id == projectId) return project;
    }
    return null;
  }

  final runtime = VibeAgentRuntime(
    api: ApiClient.instance,
    tokenProvider: () => auth.token,
    sessions: sessions,
    projectRootOf: (projectId) => find(projectId)?.path ?? '',
    languageOf: (projectId) {
      final project = find(projectId);
      if (project == null) return '';
      return project.language.isNotEmpty ? project.language : project.type;
    },
    configuredModel: () => settings.aiModel,
  );
  _cached = runtime;
  return runtime;
}

/// 测试与重新登录后重置缓存。
void resetStudioAgentRuntime() => _cached = null;

/// 代理循环守卫：重复调用、无进展、先读后改和轮数预算。
///
/// 守卫只判断本机可观察的事实（工具名、参数、退出码、成功写入），
/// 不猜测模型意图。拒绝时返回给模型的原因为真实失败。
library;

import 'dart:convert';

/// 默认轮数；按任务规模放大后使用。
const int kVibeBaseRounds = 12;
const int kVibeMaxRoundBudget = 30;
const int kVibeRoundsPerExtraTask = 12;

/// 同一调用重复多少次后被拒绝。
const int kVibeRepeatLimit = 3;

/// 连续多少轮没有进展后停止。
const int kVibeNoProgressRounds = 2;

/// 前若干轮里，规划与看目录都算推进任务。
///
/// 模型常见节奏：先写 todo、再列目录、然后动手。若这几步就判无进展，
/// 会把正常开工的代理提前停掉。
const int kVibeSetupRounds = 3;

/// 按提示词规模计算本轮轮数预算。
int vibeRoundBudget(String prompt) {
  final lower = prompt.toLowerCase();
  const multiTaskHints = [
    '网站',
    '网页',
    '页面',
    '项目',
    '应用',
    '系统',
    '完整',
    'site',
    'website',
    'webpage',
    'app',
    'project',
    'application',
  ];
  final extra = multiTaskHints.any(lower.contains) ? 1 : 0;
  final budget = kVibeBaseRounds + extra * kVibeRoundsPerExtraTask;
  return budget > kVibeMaxRoundBudget ? kVibeMaxRoundBudget : budget;
}

/// 规范化工具参数，用于识别重复调用；键顺序不同视为同一调用。
String canonicalVibeCall(String name, String arguments) {
  Object? decoded;
  try {
    decoded = jsonDecode(arguments);
  } on FormatException {
    return '$name|$arguments';
  }
  return '$name|${jsonEncode(_sorted(decoded))}';
}

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}

/// 一轮工具执行后的事实，供守卫判定进展。
class VibeRoundFacts {
  int writes = 0;
  int reads = 0;
  int listings = 0;
  int planUpdates = 0;
  int newSources = 0;
  final List<int?> exitCodes = [];
  final List<String> errors = [];

  /// 本轮是否推动了任务：成功写入或读取文件，跑完命令，
  /// 或检索到新的网址、新的页面正文。
  ///
  /// 退出码非零同样算进展：模型看到了真实错误才能修复。
  /// 联网检索带回新信息也是进展，不能当成“什么都没发生”。
  bool get progressed =>
      writes > 0 ||
      reads > 0 ||
      newSources > 0 ||
      exitCodes.any((code) => code != null);

  /// 开工阶段的表现：更新计划或成功列出目录。
  ///
  /// 只在最初 [kVibeSetupRounds] 轮内算作进展，之后仍要求写入或命令结果。
  bool get settingUp => planUpdates > 0 || listings > 0;
}

/// 单次 send 内的循环守卫状态。
class VibeLoopGuard {
  final Map<String, int> _calls = {};
  final Map<String, int> _snapshot = {};
  final Set<String> _knownFiles = {};
  final Set<String> _writtenFiles = {};
  int _stalledRounds = 0;
  int _rounds = 0;

  /// 拒绝重复调用，并返回拒绝原因；null 表示应继续执行。
  ///
  /// 被拒的调用不再计入次数，只有真正执行的调用才累计。
  String? rejectRepeat(String name, String arguments) {
    final count = _calls[canonicalVibeCall(name, arguments)] ?? 0;
    if (count < kVibeRepeatLimit) return null;
    return '同一个调用已重复 $count 次，结果不会改变。换一个办法，'
        '或先 read_file 确认当前状态。';
  }

  /// 本次调用已真正发出，计数加一。
  void recordCall(String name, String arguments) {
    final key = canonicalVibeCall(name, arguments);
    _calls[key] = (_calls[key] ?? 0) + 1;
  }

  /// 登记进入本轮前已知的文件（已存在的磁盘文件）。
  void markKnown(Iterable<String> paths) => _knownFiles.addAll(paths);

  /// 项目快照：相对路径到字节数的映射，用于判断目标文件是否已存在。
  void markSnapshot(Map<String, int> snapshot) => _snapshot.addAll(snapshot);

  /// 目标文件在本次 send 开始时是否已存在。
  bool existedAtStart(String path) => _snapshot.containsKey(path);

  /// 是否已读取过该文件。
  bool hasRead(String path) => _knownFiles.contains(path);

  void markRead(String path) {
    _knownFiles.add(path);
    _writtenFiles.remove(path);
  }

  void markWritten(String path) => _writtenFiles.add(path);

  /// 先读后改：本次 send 创建的文件豁免。
  String? rejectUnreadWrite(String path) {
    if (_writtenFiles.contains(path)) return null;
    if (hasRead(path)) return null;
    return '$path 已存在且本轮未读取，先 read_file 再修改。';
  }

  /// 登记一轮结果，返回停止原因；null 表示继续。
  ///
  /// 写入被拒（冲突、先读后改、策略拒绝）算作真实进展：模型学到了新事实，
  /// 并会在下一轮改变做法，不能和"什么都没发生"混为一谈。
  String? endRound(VibeRoundFacts facts) {
    final informational = facts.errors.any(_isInformativeFailure);
    final settingUp = _rounds < kVibeSetupRounds && facts.settingUp;
    _rounds++;
    if (facts.progressed || informational || settingUp) {
      _stalledRounds = 0;
      return null;
    }
    _stalledRounds++;
    if (_stalledRounds < kVibeNoProgressRounds) return null;
    final detail = facts.errors.isEmpty
        ? '本轮没有成功写入文件，也没有取得命令结果。'
        : '最近失败：${facts.errors.last}';
    return '连续 $_stalledRounds 轮没有进展，已停止。$detail';
  }

  static bool _isInformativeFailure(String error) =>
      error.startsWith('rejected:') ||
      error.startsWith('conflict:') ||
      error.startsWith('unread:') ||
      error.startsWith('plan:');
}

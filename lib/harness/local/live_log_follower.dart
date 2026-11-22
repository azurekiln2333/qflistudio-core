/// 跟踪直播会话对应的日志文件。
///
/// 外部 harness 把结构化对话写进自己的日志，但启动时我们拿不到它的会话
/// id。因此这里按“工作目录一致、修改时间晚于启动时刻”找最近的日志文件，
/// 之后按尾部窗口增量读取。
///
/// 轮询间隔固定且不密集；[stop] 之后不再读盘。只读，不写日志。
library;

import 'dart:async';

import 'package:path/path.dart' as p;

import '../harness_host.dart';
import 'transcript_log_reader.dart';

/// 直播会话的日志跟随器。
class LiveLogFollower {
  LiveLogFollower({
    required this.reader,
    required this.workingDirectory,
    required this.since,
    this.pollInterval = const Duration(seconds: 2),
    this.maxEvents = 2000,
    this.matchWindow = const Duration(seconds: 5),
  });

  final TranscriptLogReader reader;
  final String workingDirectory;

  /// 会话启动时刻。早于该时刻的日志不属于这个会话。
  final DateTime since;
  final Duration pollInterval;
  final int maxEvents;

  /// 文件修改时间允许提前的量，用来容忍时钟偏差。
  final Duration matchWindow;

  final StreamController<TranscriptEvent> _events =
      StreamController<TranscriptEvent>.broadcast();
  Timer? _timer;
  String? _path;

  /// 上一次轮询窗口里已经推过的事件 id。
  ///
  /// 不用“事件条数”做游标：读取器只返回尾部窗口（还有条数上限），窗口
  /// 封顶后条数不再增长，条数游标会让推送永久停住。id 由字节偏移生成，
  /// 同一行在两次读取里 id 相同，用集合去重既不丢事件也不会重推。
  final Set<String> _deliveredIds = <String>{};
  int _delivered = 0;
  bool _polling = false;

  /// 已发现并跟随的日志文件；尚未发现时为 null。
  String? get logPath => _path;

  /// 增量事件流。广播流，只推送发现之后的新事件。
  Stream<TranscriptEvent> get events => _events.stream;

  /// 已推送的事件总数。
  int get delivered => _delivered;

  /// 开始轮询。
  void start() {
    _timer ??= Timer.periodic(pollInterval, (Timer _) => unawaited(poll()));
    unawaited(poll());
  }

  /// 立即读一次。测试直接调用它，不必等定时器。
  Future<void> poll() async {
    if (_polling || _events.isClosed) return;
    _polling = true;
    try {
      _path ??= await _findLogFile();
      final path = _path;
      if (path == null) return;
      final events = await reader.read(path, maxEvents: maxEvents);
      final windowIds = <String>{};
      for (final event in events) {
        windowIds.add(event.id);
        if (_deliveredIds.contains(event.id)) continue;
        if (_events.isClosed) return;
        _events.add(event);
        _delivered++;
      }
      // 只保留当前窗口内的 id：窗口滑走的事件不可能再被读到。
      _deliveredIds
        ..clear()
        ..addAll(windowIds);
    } on Object {
      // 读日志失败不应影响会话本身；下一轮再试。
    } finally {
      _polling = false;
    }
  }

  Future<String?> _findLogFile() async {
    final sessions = await reader.listSessions(maxSessions: 20);
    final earliest = since.subtract(matchWindow);
    for (final session in sessions) {
      if (session.updatedAt.isBefore(earliest)) continue;
      final cwd = session.workingDirectory;
      if (cwd != null &&
          workingDirectory.isNotEmpty &&
          !_sameDirectory(cwd, workingDirectory)) {
        continue;
      }
      return session.filePath;
    }
    return null;
  }

  static bool _sameDirectory(String left, String right) {
    final a = p.normalize(left.replaceAll('\\', '/')).toLowerCase();
    final b = p.normalize(right.replaceAll('\\', '/')).toLowerCase();
    return a == b;
  }

  /// 停止轮询并关闭事件流。
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (!_events.isClosed) await _events.close();
  }
}

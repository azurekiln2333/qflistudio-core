// 首页 Agents 列表的快照。
//
// 首屏先画上次的列表，网络回来再替换：手机上等一次配对连接要一两秒，空白
// 列表比旧列表更让人以为坏了。格式见 design.md §2.7。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../services/local_store_backend.dart';
import '../harness_host.dart';
import 'agents_index.dart';

/// 快照的默认后端。
///
/// 测试进程里给内存后端：一次运行写的快照不该污染下一次运行。
LocalStoreBackend defaultAgentsSnapshotBackend() {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return LocalMemoryBackend();
  }
  return const LocalFileBackend(AgentsSnapshotStore.fileName);
}

/// 首页 Agents 列表的快照存储。
class AgentsSnapshotStore {
  AgentsSnapshotStore({LocalStoreBackend? backend})
    : _backend = backend ?? defaultAgentsSnapshotBackend();

  /// 快照文件名。
  static const String fileName = 'home_agents_snapshot.json';

  /// 当前格式版本。读到别的版本就当没有快照。
  static const int schemaVersion = 1;

  /// 最多保留多少行。
  static const int maxRows = 100;

  final LocalStoreBackend _backend;

  /// 读快照。没有、坏了或版本不对都返回空表。
  Future<List<AgentsIndexRow>> load() async {
    final payload = await _backend.read();
    if (payload == null || payload.trim().isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map) return const [];
    if (decoded['version'] != schemaVersion) return const [];
    final rawRows = decoded['rows'];
    if (rawRows is! List) return const [];

    final rows = <AgentsIndexRow>[];
    for (final raw in rawRows) {
      final row = _rowFromJson(raw);
      if (row != null) rows.add(row);
      if (rows.length >= maxRows) break;
    }
    return List<AgentsIndexRow>.unmodifiable(rows);
  }

  /// 写快照。超过 [maxRows] 的部分按调用方给的顺序截断。
  Future<void> save(List<AgentsIndexRow> rows) async {
    final kept = rows.length > maxRows ? rows.sublist(0, maxRows) : rows;
    final payload = jsonEncode({
      'version': schemaVersion,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'rows': [for (final row in kept) _rowToJson(row)],
    });
    try {
      await _backend.write(payload);
    } on Object {
      // 快照只是首屏的加速，写不进去不影响功能。
    }
  }

  Map<String, Object?> _rowToJson(AgentsIndexRow row) => {
    'hostId': row.session.hostId,
    'hostLabel': row.hostLabel,
    'hostKind': row.hostKind.name,
    'sessionId': row.session.id,
    'providerId': row.session.providerId,
    'title': row.session.title,
    'status': row.session.status.name,
    'cwd': row.session.cwd,
    'updatedAt': row.session.updatedAt?.toUtc().toIso8601String(),
    'device': _deviceToJson(row.device),
  };

  static Map<String, Object?>? _deviceToJson(HarnessDeviceInfo? device) {
    if (device == null || device.isEmpty) return null;
    return {
      'hostName': device.hostName,
      'os': device.os.name,
      'osVersion': device.osVersion,
    };
  }

  static AgentsIndexRow? _rowFromJson(Object? raw) {
    if (raw is! Map) return null;
    final hostId = _string(raw['hostId']);
    final sessionId = _string(raw['sessionId']);
    if (hostId == null || sessionId == null) return null;
    final hostKind = _hostKind(raw['hostKind']);
    if (hostKind == null) return null;
    return AgentsIndexRow(
      session: HarnessSessionInfo(
        id: sessionId,
        hostId: hostId,
        providerId: _string(raw['providerId']) ?? '',
        title: _string(raw['title']) ?? '',
        status: _status(raw['status']),
        capabilities: const {},
        cwd: _string(raw['cwd']),
        updatedAt: DateTime.tryParse(_string(raw['updatedAt']) ?? ''),
      ),
      hostLabel: _string(raw['hostLabel']) ?? '',
      hostKind: hostKind,
      device: _deviceFromJson(raw['device']),
    );
  }

  static HarnessDeviceInfo? _deviceFromJson(Object? raw) {
    if (raw is! Map) return null;
    final info = HarnessDeviceInfo(
      hostName: _string(raw['hostName']),
      os: _os(raw['os']),
      osVersion: _string(raw['osVersion']),
    );
    return info.isEmpty ? null : info;
  }

  static HarnessHostKind? _hostKind(Object? raw) {
    final name = _string(raw);
    for (final kind in HarnessHostKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  static HarnessSessionStatus _status(Object? raw) {
    final name = _string(raw);
    for (final status in HarnessSessionStatus.values) {
      if (status.name == name) return status;
    }
    return HarnessSessionStatus.unknown;
  }

  static HarnessDeviceOs _os(Object? raw) {
    final name = _string(raw);
    for (final os in HarnessDeviceOs.values) {
      if (os.name == name) return os;
    }
    return HarnessDeviceOs.unknown;
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value is String ? value : value.toString();
    return text.isEmpty ? null : text;
  }
}

/// 首页用的防抖写快照。
///
/// 列表每帧都可能变，直接写会把盘写满。这里只保留最后一次，延迟 [delay] 后写。
class AgentsSnapshotWriter {
  AgentsSnapshotWriter({
    required this.store,
    this.delay = const Duration(seconds: 2),
  });

  final AgentsSnapshotStore store;
  final Duration delay;

  Timer? _timer;
  List<AgentsIndexRow>? _pending;

  /// 排一次写入。重复调用只保留最后一次的行。
  void schedule(List<AgentsIndexRow> rows) {
    _pending = rows;
    _timer?.cancel();
    _timer = Timer(delay, _flush);
  }

  /// 立刻写掉排着的行。
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final rows = _pending;
    _pending = null;
    if (rows == null) return;
    await store.save(rows);
  }

  /// 取消排着的写入。
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  void _flush() {
    _timer = null;
    final rows = _pending;
    _pending = null;
    if (rows == null) return;
    unawaited(store.save(rows));
  }
}

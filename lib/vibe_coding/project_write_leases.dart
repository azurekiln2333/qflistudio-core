/// 路径写租约：两个会话同时改同一个文件时，后到的得到冲突。
///
/// 租约属于「占用会话的这一轮」。本轮结束、取消或实例销毁时释放。
/// 只做进程内互斥：跨进程同时编辑不在本次范围内。
library;

import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

/// 一次申请的结果。
class ProjectWriteLease {
  /// 拿到了。
  const ProjectWriteLease.granted() : conflict = null;

  /// 被别的会话占着；[conflict] 是可直接显示的文案。
  const ProjectWriteLease.conflict({required String this.conflict});

  /// 冲突文案；为空表示已放行。
  final String? conflict;

  bool get granted => conflict == null;
}

class _Held {
  const _Held(this.sessionId, this.sessionLabel);

  final String sessionId;
  final String sessionLabel;
}

/// 进程内的写租约表。按项目根区分，路径统一规范化后再比较。
///
/// 大小写不敏感的平台（Windows、macOS、iOS）把 `a.txt` 和 `A.TXT` 当成
/// 同一个租约；Linux 上两者是两个文件。测试用 [caseInsensitive] 注入。
class ProjectWriteLeases {
  ProjectWriteLeases({this.projectRoot = '', bool? caseInsensitive})
    : caseInsensitive = caseInsensitive ?? defaultCaseInsensitive;

  /// 平台默认是否折叠大小写。
  static bool get defaultCaseInsensitive =>
      Platform.isWindows || Platform.isMacOS || Platform.isIOS;

  /// 项目根；只用于把绝对路径换成相对键，空串表示不分项目。
  final String projectRoot;

  /// 路径键是否折叠大小写。默认跟随平台。
  final bool caseInsensitive;

  final Map<String, _Held> _held = {};

  /// 当前被占用的路径数。
  int get heldCount => _held.length;

  /// 申请写某个路径。已被别的会话占用时返回冲突。
  ///
  /// 同一个会话重复申请同一路径直接放行（一轮里多次改同一个文件很常见）。
  ProjectWriteLease acquire({
    required String sessionId,
    required String sessionLabel,
    required String path,
  }) {
    final key = _keyOf(path);
    final current = _held[key];
    if (current == null || current.sessionId == sessionId) {
      _held[key] = _Held(sessionId, sessionLabel);
      return const ProjectWriteLease.granted();
    }
    return ProjectWriteLease.conflict(
      conflict: '文件正被会话「${current.sessionLabel}」修改，稍后再试',
    );
  }

  /// 释放某个会话对某路径的占用。
  void release(String sessionId, String path) {
    final key = _keyOf(path);
    if (_held[key]?.sessionId == sessionId) _held.remove(key);
  }

  /// 释放某个会话的全部占用（本轮结束、取消、销毁时调）。
  void releaseAll(String sessionId) {
    _held.removeWhere((_, held) => held.sessionId == sessionId);
  }

  /// 这个路径是否被别的会话占着。
  bool isHeldByOther(String sessionId, String path) {
    final current = _held[_keyOf(path)];
    return current != null && current.sessionId != sessionId;
  }

  /// 当前占用者的会话名；空闲返回 null。
  String? holderOf(String path) => _held[_keyOf(path)]?.sessionLabel;

  /// 这个会话占着的路径。
  Set<String> pathsOf(String sessionId) => {
    for (final entry in _held.entries)
      if (entry.value.sessionId == sessionId) entry.key,
  };

  String _keyOf(String path) {
    // 先把反斜杠统一成 `/`：Linux 的 `p` 不认反斜杠，Windows 两种都认。
    final root = projectRoot.replaceAll('\\', '/');
    final input = path.replaceAll('\\', '/');
    final absolute = p.isAbsolute(input)
        ? p.normalize(input)
        : p.normalize(p.join(root, input));
    var key = root.isEmpty
        ? absolute
        : (p.isWithin(root, absolute)
              ? p.relative(absolute, from: root)
              : absolute);
    key = key.replaceAll('\\', '/');
    while (key.startsWith('./')) {
      key = key.substring(2);
    }
    return caseInsensitive ? key.toLowerCase() : key;
  }
}

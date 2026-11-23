import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../store/project_store.dart';

/// Native bridge channel for directories dragged from Explorer.
const MethodChannel defaultDesktopFolderDropChannel = MethodChannel(
  'qflistudio/folder_drop',
);

/// Turns native folder-drop batches into opened projects.
///
/// The Windows runner queues batches until [start] calls `takePending`, so a
/// drop that happens during startup is not lost. Registration reuses
/// [ProjectStore.addExisting], which only records the project; opening is done
/// through [onOpen] so the caller keeps a single editor instance.
class DesktopFolderDrop {
  DesktopFolderDrop({
    required ProjectStore store,
    required Future<void> Function(Project) onOpen,
    required void Function(String) onError,
    MethodChannel? channel,
  }) : _store = store,
       _onOpen = onOpen,
       _onError = onError,
       _channel = channel ?? defaultDesktopFolderDropChannel;

  /// Batch ids kept for replay suppression. Bounded so a long session cannot
  /// grow the set without limit.
  static const int _maxRememberedBatchIds = 64;

  final ProjectStore _store;
  final Future<void> Function(Project) _onOpen;
  final void Function(String) _onError;
  final MethodChannel _channel;

  /// Recent batch ids, oldest first.
  final LinkedHashSet<String> _seenBatchIds = LinkedHashSet<String>();

  bool _listening = false;
  bool _disposed = false;

  /// True until the startup backlog has been handled. Live drops that arrive
  /// in the meantime wait so they cannot overtake the backlog.
  bool _drainingBacklog = false;
  final _earlyBatches = <Object?>[];
  Future<void>? _starting;

  /// Serialises batches so a fast second drop cannot interleave registration.
  Future<void> _queue = Future<void>.value();

  /// Subscribes to native drops and flushes anything queued before now.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    if (_disposed || _listening) return;
    _listening = true;
    _drainingBacklog = true;
    _channel.setMethodCallHandler(_handleCall);

    var pending = const <Object?>[];
    try {
      final raw = await _channel.invokeMethod<Object?>('takePending');
      // Validated rather than cast: a malformed reply must not throw here.
      if (raw is List) {
        pending = raw;
      } else if (raw != null) {
        _report('拖入的数据格式不正确');
      }
    } on MissingPluginException {
      // Not running on a platform with the native adapter.
    } on PlatformException catch (error) {
      _report(error.message ?? '无法接收拖入的文件夹');
    }

    if (_disposed) return;
    // Enqueue the backlog first, then release live drops behind it.
    for (final batch in pending) {
      _enqueue(batch);
    }
    for (final batch in _earlyBatches) {
      _enqueue(batch);
    }
    _earlyBatches.clear();
    _drainingBacklog = false;
    await _queue;
  }

  /// Stops delivering callbacks. Safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listening = false;
    _drainingBacklog = false;
    _seenBatchIds.clear();
    _earlyBatches.clear();
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (_disposed) return null;
    switch (call.method) {
      case 'incoming':
        if (_drainingBacklog) {
          _earlyBatches.add(call.arguments);
        } else {
          await _enqueue(call.arguments);
        }
        break;
      case 'rejected':
        final message = _messageOf(call.arguments);
        if (message != null) _report(message);
        break;
    }
    return null;
  }

  Future<void> _enqueue(Object? batch) {
    if (_disposed) return Future.value();
    // A failing batch must not poison the chain for later drops.
    _queue = _queue.then((_) => _handleBatch(batch)).catchError((Object error) {
      _report('处理拖入的文件夹失败：$error');
    });
    return _queue;
  }

  Future<void> _handleBatch(Object? raw) async {
    if (_disposed) return;
    final batch = _decodeBatch(raw);
    if (batch == null) {
      _report('拖入的数据格式不正确');
      return;
    }
    final id = batch.id;
    if (_seenBatchIds.contains(id)) return;
    _seenBatchIds.add(id);
    while (_seenBatchIds.length > _maxRememberedBatchIds) {
      _seenBatchIds.remove(_seenBatchIds.first);
    }

    // Deduplicate only within this batch. Repeating a drop of the same folder
    // later must still reopen that project.
    final normalized = <String>[];
    final localSeen = <String>{};
    for (final path in batch.paths) {
      final resolved = _normalize(path);
      if (resolved == null) {
        _report('无法打开拖入的路径：$path');
        continue;
      }
      if (!localSeen.add(_compareKey(resolved))) continue;
      normalized.add(resolved);
    }
    if (normalized.isEmpty) {
      _report('未找到可用的文件夹');
      return;
    }

    // Every successful directory opens in order; the last success becomes the
    // active project. A failure does not undo earlier successes.
    for (final path in normalized) {
      if (_disposed) return;
      final project = await _projectFor(path);
      if (project == null) continue;
      if (_disposed) return;
      try {
        await _onOpen(project);
      } catch (error) {
        // Keep the current project and the source directory untouched.
        _report('打开拖入的项目失败：$error');
      }
    }
  }

  /// Reuses an existing project for [path], otherwise registers it.
  ///
  /// A failed registration is not remembered, so dropping the same folder
  /// again retries it.
  Future<Project?> _projectFor(String path) async {
    final existing = _findExisting(path);
    if (existing != null) return existing;

    final ProjectResult result;
    try {
      result = await _store.addExisting(path);
    } catch (error) {
      _report('登记文件夹失败：$error');
      return null;
    }
    if (result.error != null) {
      _report(result.error!);
      return null;
    }
    return result.project;
  }

  Project? _findExisting(String path) {
    final target = _compareKey(path);
    for (final project in _store.projects) {
      if (!project.isCloud && _compareKey(project.path) == target) {
        return project;
      }
    }
    return null;
  }

  String _compareKey(String path) {
    final normalized = _normalize(path) ?? path;
    return _isWindowsAbsolute(normalized)
        ? normalized.toLowerCase()
        : normalized;
  }

  bool _isWindowsAbsolute(String path) =>
      p.windows.isAbsolute(path) && !p.windows.isRootRelative(path);

  /// Returns an absolute, normalized path or null when the input is unusable.
  ///
  /// UNC paths such as `\\server\share` are kept: they are normal absolute
  /// Windows paths, and rejecting them would drop reachable network folders.
  /// Do not trim a path supplied by the operating system.
  String? _normalize(String raw) {
    if (raw.isEmpty) return null;
    final pathContext = _isWindowsAbsolute(raw) ? p.windows : p.context;
    if (!pathContext.isAbsolute(raw) || pathContext.isRootRelative(raw)) {
      return null;
    }
    return pathContext.normalize(raw);
  }

  String? _messageOf(Object? arguments) {
    if (arguments is Map) {
      final message = arguments['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (arguments is String && arguments.isNotEmpty) return arguments;
    return null;
  }

  /// Decodes `{id: non-empty String, paths: List<String>}`.
  _DropBatch? _decodeBatch(Object? raw) {
    if (raw is! Map) return null;
    final idValue = raw['id'];
    // The id is required: without it a replayed batch cannot be recognised.
    if (idValue is! String || idValue.isEmpty) return null;

    final pathsValue = raw['paths'];
    if (pathsValue is! List) return null;
    final paths = <String>[];
    for (final item in pathsValue) {
      if (item is String && item.isNotEmpty) paths.add(item);
    }
    return _DropBatch(id: idValue, paths: paths);
  }

  void _report(String message) {
    if (_disposed) return;
    _onError(message);
  }
}

class _DropBatch {
  const _DropBatch({required this.id, required this.paths});

  final String id;
  final List<String> paths;
}

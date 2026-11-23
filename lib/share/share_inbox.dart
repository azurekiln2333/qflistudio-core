import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'share_inbox_store.dart';

/// 收件箱通道名。三端共用。
const String kShareInboxChannel = 'qflistudio/share_inbox';

/// 一个已落盘的外部文件。
@immutable
class SharedIncomingFile {
  const SharedIncomingFile({
    required this.path,
    required this.name,
    required this.bytes,
    this.mimeType,
  });

  /// 原生已复制到收件箱的绝对路径。
  final String path;

  /// 系统给出的显示名，已去掉路径分隔符。
  final String name;

  final int bytes;

  final String? mimeType;

  @override
  String toString() => 'SharedIncomingFile($name, $bytes)';
}

/// 一次分享进来的一批文件。
@immutable
class ShareInboxBatch {
  const ShareInboxBatch({
    required this.id,
    required this.files,
    required this.coldStart,
    required this.source,
  });

  final String id;
  final List<SharedIncomingFile> files;

  /// true 表示随进程启动到达。
  final bool coldStart;

  /// `send`、`sendMultiple`、`view`、`document`、`sendData`、`viewData`。
  final String source;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  bool get isEmpty => files.isEmpty;

  @override
  String toString() =>
      'ShareInboxBatch($id, ${files.length}, coldStart: $coldStart)';
}

/// 收件箱通道。三端共用。
abstract class ShareInbox {
  /// 原生送进来的批次。冷启动批次也走这里。
  Stream<ShareInboxBatch> get incoming;

  /// 注册通道，并取回冷启动批次。
  Future<void> start();

  /// 删除一个批次目录。
  Future<void> discard(String batchId);

  /// 清理超期与超额批次。
  Future<void> sweep();

  void dispose();
}

/// 走 [MethodChannel] 的实现。
///
/// 原生在没有监听者时缓存最后一批，Dart 起来后由 [start] 里的
/// `takePending` 取走。这样冷启动与热启动走同一条流。
class PlatformShareInbox implements ShareInbox {
  PlatformShareInbox({required ShareInboxStore store, MethodChannel? channel})
    : _store = store,
      _channel = channel ?? const MethodChannel(kShareInboxChannel);

  final ShareInboxStore _store;
  final MethodChannel _channel;
  final StreamController<ShareInboxBatch> _incoming =
      StreamController<ShareInboxBatch>.broadcast();

  bool _started = false;
  bool _disposed = false;

  @override
  Stream<ShareInboxBatch> get incoming => _incoming.stream;

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _channel.setMethodCallHandler(_onMethodCall);
    final pending = await _takePending();
    if (pending != null && !_disposed) _emit(pending);
  }

  Future<ShareInboxBatch?> _takePending() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('takePending');
      return parseShareInboxBatch(raw);
    } on MissingPluginException {
      // 桌面端与未实现的原生端没有这个通道。
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'incoming') return;
    final batch = parseShareInboxBatch(call.arguments);
    if (batch != null) _emit(batch);
  }

  void _emit(ShareInboxBatch batch) {
    if (_disposed || batch.isEmpty) return;
    _incoming.add(batch);
  }

  @override
  Future<void> discard(String batchId) async {
    if (!ShareInboxStore.isValidBatchId(batchId)) return;
    await _store.discard(batchId);
    try {
      await _channel.invokeMethod<void>('discard', {'id': batchId});
    } on MissingPluginException {
      // 已经由本地目录删除，原生端缺失不算失败。
    } on PlatformException {
      // 同上：目录已删，原生端报错只影响它自己的缓存。
    }
  }

  @override
  Future<void> sweep() => _store.sweep();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_incoming.close());
  }
}

/// 解析原生消息。坏字段整批丢弃，不抛异常。
ShareInboxBatch? parseShareInboxBatch(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  if (id is! String || !ShareInboxStore.isValidBatchId(id)) return null;
  final rawFiles = raw['files'];
  if (rawFiles is! List) return null;
  final files = <SharedIncomingFile>[];
  for (final entry in rawFiles) {
    if (entry is! Map) continue;
    final path = entry['path'];
    final name = entry['name'];
    final bytes = entry['bytes'];
    if (path is! String || path.isEmpty) continue;
    if (name is! String || name.isEmpty) continue;
    final size = bytes is int ? bytes : (bytes is num ? bytes.toInt() : 0);
    final mime = entry['mimeType'];
    files.add(
      SharedIncomingFile(
        path: path,
        name: name,
        bytes: size < 0 ? 0 : size,
        mimeType: mime is String && mime.isNotEmpty ? mime : null,
      ),
    );
  }
  if (files.isEmpty) return null;
  final coldStart = raw['coldStart'];
  final source = raw['source'];
  return ShareInboxBatch(
    id: id,
    files: List.unmodifiable(files),
    coldStart: coldStart is bool && coldStart,
    source: source is String && source.isNotEmpty ? source : 'send',
  );
}

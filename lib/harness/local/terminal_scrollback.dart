/// 有上限的终端滚动缓冲。
///
/// 会话的输出可能持续数小时，因此缓冲按字节数封顶，超限时从最早的块开始
/// 丢弃。块边界保留原始字节，转义序列不会被切开。
library;

import 'dart:typed_data';

/// 默认上限：512 KiB，约等于一屏密集日志的数十页。
const int kDefaultScrollbackBytes = 512 * 1024;

class TerminalScrollback {
  TerminalScrollback({this.maxBytes = kDefaultScrollbackBytes}) {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', '不能为负数');
    }
  }

  /// 缓冲的字节上限。为 0 时不保留任何输出。
  final int maxBytes;

  final List<Uint8List> _chunks = <Uint8List>[];
  int _length = 0;

  /// 当前保留的字节数。
  int get byteLength => _length;

  /// 是否还有内容。
  bool get isEmpty => _length == 0;

  /// 保留的块，按写入顺序。调用方只读。
  List<Uint8List> get chunks => List<Uint8List>.unmodifiable(_chunks);

  /// 追加一段输出。超限时丢弃最早的块。
  void add(List<int> data) {
    if (data.isEmpty || maxBytes == 0) return;
    final chunk = Uint8List.fromList(data);
    if (chunk.length >= maxBytes) {
      // 单块就超限：只保留它的尾部，前面的内容已经无法显示。
      _chunks
        ..clear()
        ..add(Uint8List.sublistView(chunk, chunk.length - maxBytes));
      _length = maxBytes;
      return;
    }
    _chunks.add(chunk);
    _length += chunk.length;
    while (_length > maxBytes && _chunks.isNotEmpty) {
      final removed = _chunks.removeAt(0);
      _length -= removed.length;
    }
  }

  /// 拼接后的完整字节。
  Uint8List toBytes() {
    final buffer = Uint8List(_length);
    var offset = 0;
    for (final chunk in _chunks) {
      buffer.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return buffer;
  }

  /// 清空缓冲。
  void clear() {
    _chunks.clear();
    _length = 0;
  }
}

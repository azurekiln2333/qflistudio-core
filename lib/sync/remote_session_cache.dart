import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Bounded, append-only copy of one device session's transcript.
///
/// A session that runs on the paired computer streams its transcript over the
/// relay. When the phone loses the connection the stream is gone, so the newest
/// lines are kept on disk and replayed the next time the session opens. The
/// file is capped twice: by byte size and by line count. The oldest lines go
/// first, so what survives is the most recent part of the conversation.
///
/// The file is a JSON Lines file: one JSON object per line, so a partial write
/// can only damage the last line and a reader can skip it.
class RemoteSessionCache {
  RemoteSessionCache({
    required String directory,
    String fileName = 'stream.jsonl',
    this.maxBytes = 2 * 1024 * 1024,
    this.maxEvents = 400,
  }) : _file = File(p.join(directory, fileName));

  /// 2 MiB: enough for the visible part of a long conversation without letting
  /// a chatty session fill the phone's storage.
  final int maxBytes;
  final int maxEvents;

  final File _file;
  Future<void>? _pending;

  String get path => _file.path;

  /// Append one event, then trim to the caps.
  ///
  /// Writes are serialised through [_pending] so two events arriving in the same
  /// tick cannot interleave their lines.
  Future<void> append(Map<String, dynamic> event) {
    final next = (_pending ?? Future<void>.value()).then((_) => _append(event));
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _append(Map<String, dynamic> event) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        '${jsonEncode(event)}\n',
        mode: FileMode.append,
        flush: false,
      );
      await _trim();
    } on FileSystemException {
      // A cache that cannot be written is not worth failing a session over.
    }
  }

  /// Kept lines, oldest first. A corrupt line is skipped instead of failing.
  Future<List<Map<String, dynamic>>> read() async {
    if (!await _file.exists()) return const <Map<String, dynamic>>[];
    final text = await _file.readAsString().catchError((Object _) => '');
    final events = <Map<String, dynamic>>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) events.add(Map<String, dynamic>.from(decoded));
      } on FormatException {
        continue;
      }
    }
    return events;
  }

  /// Delete the cache, for a session the user removed.
  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } on FileSystemException {
      // Ignored: the next trim rewrites the file anyway.
    }
  }

  /// Drop the oldest lines until both caps hold again.
  Future<void> _trim() async {
    if (!await _file.exists()) return;
    final length = await _file.length();
    if (length <= maxBytes) {
      final count = await _lineCount();
      if (count <= maxEvents) return;
    }
    final lines = const LineSplitter().convert(await _file.readAsString());
    var kept = <String>[];
    for (final line in lines) {
      if (line.trim().isNotEmpty) kept.add(line);
    }
    if (kept.length > maxEvents) {
      kept = kept.sublist(kept.length - maxEvents);
    }
    while (kept.isNotEmpty && _encodedBytes(kept) > maxBytes) {
      kept = kept.sublist(1);
    }
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      kept.isEmpty ? '' : '${kept.join('\n')}\n',
      flush: false,
    );
    await temp.rename(_file.path);
  }

  Future<int> _lineCount() async {
    if (!await _file.exists()) return 0;
    final text = await _file.readAsString().catchError((Object _) => '');
    return const LineSplitter()
        .convert(text)
        .where((line) => line.trim().isNotEmpty)
        .length;
  }

  int _encodedBytes(List<String> lines) {
    var total = 0;
    for (final line in lines) {
      total += utf8.encode(line).length + 1;
    }
    return total;
  }
}

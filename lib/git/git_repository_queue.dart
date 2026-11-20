import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Coordinates separate pages that refer to the same physical repository.
abstract final class GitRepositoryQueue {
  static final Map<String, Future<void>> _tails = {};

  static Future<T> run<T>(String root, Future<T> Function() action) {
    // Resolve synchronously before enqueueing to preserve invocation order.
    var key = p.normalize(p.absolute(root));
    try {
      key = Directory(key).resolveSymbolicLinksSync();
    } on FileSystemException {
      // init/clone may refer to a directory that does not exist yet.
    }
    if (Platform.isWindows) key = key.toLowerCase();
    final previous = _tails[key] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> tail;
    tail = previous
        .then((_) async {
          try {
            completer.complete(await action());
          } catch (error, stack) {
            completer.completeError(error, stack);
          }
        })
        .whenComplete(() {
          if (identical(_tails[key], tail)) _tails.remove(key);
        });
    _tails[key] = tail;
    return completer.future;
  }
}

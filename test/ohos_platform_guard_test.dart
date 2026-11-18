import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Core is compiled twice: by the OHOS Flutter fork, which has
/// `TargetPlatform.ohos` and `OhosView`, and by official Flutter, which has
/// neither.
///
/// Official builds used to depend on `tool/ci/patch_upstream_core.sh` rewriting
/// every such reference. Each new one broke every official build until the
/// script learned the string (2026-11-19). The sources now detect HarmonyOS by
/// enum name, and this test keeps the fork-only API from creeping back.
///
/// `OhosView` is allowed only in the Huawei one-tap login view: it is the one
/// place that must embed a native ArkTS platform view, and the CI patch script
/// replaces that file for official builds.
const String _ohosViewAllowlist = 'lib/pages/auth/huawei_quick_login_view.dart';

/// Directories that are compiled by both Flutter variants.
const List<String> _sourceRoots = ['lib', 'vendor/re_editor/lib'];

/// Names that exist only on the OHOS Flutter fork.
const List<String> _forkOnlyNames = ['TargetPlatform.ohos', 'OhosView'];

void main() {
  test('no fork-only OHOS API outside the one patched file', () {
    final offenders = <String>[];

    for (final root in _sourceRoots) {
      final directory = Directory(root);
      expect(directory.existsSync(), isTrue, reason: '$root is missing');
      for (final file in _dartFiles(directory)) {
        final relative = p.posix.joinAll(p.split(p.relative(file.path)));
        final lines = file.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          for (final name in _forkOnlyNames) {
            if (!line.contains(name)) continue;
            if (name == 'OhosView' && relative == _ohosViewAllowlist) continue;
            offenders.add('$relative:${index + 1}: $name in ${line.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These lines compile only on the OHOS Flutter fork. Use '
          'isOhosPlatform or isOhosTarget from lib/config/ohos_platform.dart '
          'instead:\n${offenders.join('\n')}',
    );
  });
}

/// Every `.dart` file under [directory], in a stable order.
Iterable<File> _dartFiles(Directory directory) {
  final files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}
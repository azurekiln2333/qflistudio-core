import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/services/app_private_roots.dart';

class _Paths extends PathProviderPlatform {
  _Paths(
    this.support,
    this.documents, {
    this.failSupport = false,
    this.failDocuments = false,
  });
  final String support;
  final String documents;
  final bool failSupport;
  final bool failDocuments;
  int documentReads = 0;

  @override
  Future<String?> getApplicationSupportPath() async =>
      failSupport ? null : support;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    documentReads++;
    return failDocuments ? null : documents;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform original;
  late String base;

  setUp(() {
    original = PathProviderPlatform.instance;
    base = p.join(Directory.systemTemp.path, 'qfli-private-roots');
  });

  tearDown(() {
    PathProviderPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android includes private sibling files and app_flutter', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final paths = _Paths(p.join(base, 'files'), p.join(base, 'app_flutter'));
    PathProviderPlatform.instance = paths;
    expect(await AppPrivateRoots.resolve(paths.support), {
      'storage': paths.support,
      'documents': paths.documents,
    });
  });

  test('OHOS does not duplicate nested flutter directory', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.ohos;
    final paths = _Paths(
      p.join(base, 'files'),
      p.join(base, 'files', 'flutter'),
    );
    PathProviderPlatform.instance = paths;
    expect(await AppPrivateRoots.resolve(paths.support), {
      'storage': paths.support,
    });
  });

  for (final missing in ['support', 'documents']) {
    test('mobile refuses incomplete $missing provider results', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final paths = _Paths(
        p.join(base, 'files'),
        p.join(base, 'app_flutter'),
        failSupport: missing == 'support',
        failDocuments: missing == 'documents',
      );
      PathProviderPlatform.instance = paths;
      await expectLater(
        AppPrivateRoots.resolve(paths.support),
        throwsA(isA<FileSystemException>()),
      );
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    test(
      '$platform never reads global Documents or accepts fallback',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final paths = _Paths(
          p.join(base, 'app-support'),
          p.join(base, 'Documents'),
        );
        PathProviderPlatform.instance = paths;
        expect(await AppPrivateRoots.resolve(paths.support), {
          'storage': paths.support,
        });
        expect(paths.documentReads, 0);
        await expectLater(
          AppPrivateRoots.resolve(paths.documents),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          AppPrivateRoots.resolve(base),
          throwsA(isA<FileSystemException>()),
        );
        expect(paths.documentReads, 0);
      },
    );
  }

  test('mobile documents fallback still includes private support', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final paths = _Paths(p.join(base, 'files'), p.join(base, 'app_flutter'));
    PathProviderPlatform.instance = paths;
    expect(await AppPrivateRoots.resolve(paths.documents), {
      'storage': paths.documents,
      'support': paths.support,
    });
  });
}

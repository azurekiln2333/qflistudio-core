import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/interop_fixture_roots.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('interop-fixture-roots-');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  group('Interop fixture roots', () {
    test('accepts explicit relocated fixture roots', () {
      final app = _createFixtures(
        tempRoot,
        'relocated/app',
        InteropFixtureRoots.appFiles,
      );
      final java = _createFixtures(
        tempRoot,
        'relocated/java',
        InteropFixtureRoots.javaFiles,
      );
      final resolved = InteropFixtureRoots.resolve(
        packageRoot: Directory(p.join(tempRoot.path, 'qflistudio-core')),
        environment: <String, String>{
          InteropFixtureRoots.appRootKey: app.path,
          InteropFixtureRoots.javaRootKey: java.path,
        },
      );

      expect(resolved.app.path, app.path);
      expect(resolved.java.path, java.path);
    });

    test('uses documented legacy sibling defaults when roots are unset', () {
      final packageRoot = Directory(
        p.join(tempRoot.path, 'qfli_studio_core'),
      )..createSync();
      final app = _createFixtures(
        tempRoot,
        'qflistudio',
        InteropFixtureRoots.appFiles,
      );
      final java = _createFixtures(
        tempRoot,
        'qfli_java',
        InteropFixtureRoots.javaFiles,
      );
      final resolved = InteropFixtureRoots.resolve(
        packageRoot: packageRoot,
        environment: const <String, String>{},
      );

      expect(resolved.app.path, app.path);
      expect(resolved.java.path, java.path);
    });

    test('rejects an absent App root with its key and path', () {
      final missingApp = p.join(tempRoot.path, 'missing-app');
      final java = _createFixtures(
        tempRoot,
        'relocated/java',
        InteropFixtureRoots.javaFiles,
      );

      _expectRootError(
        packageRoot: Directory(p.join(tempRoot.path, 'core')),
        environment: <String, String>{
          InteropFixtureRoots.appRootKey: missingApp,
          InteropFixtureRoots.javaRootKey: java.path,
        },
        key: InteropFixtureRoots.appRootKey,
        path: missingApp,
      );
    });

    test(
      'rejects an App root missing a required file with its exact path',
      () {
        final app = Directory(p.join(tempRoot.path, 'invalid-app'))
          ..createSync();
        final java = _createFixtures(
          tempRoot,
          'relocated/java',
          InteropFixtureRoots.javaFiles,
        );
        final missingFile = p.join(
          app.path,
          InteropFixtureRoots.appFiles.first,
        );

        _expectRootError(
          packageRoot: Directory(p.join(tempRoot.path, 'core')),
          environment: <String, String>{
            InteropFixtureRoots.appRootKey: app.path,
            InteropFixtureRoots.javaRootKey: java.path,
          },
          key: InteropFixtureRoots.appRootKey,
          path: missingFile,
        );
      },
    );

    test('rejects an empty App root with its configuration key', () {
      final java = _createFixtures(
        tempRoot,
        'relocated/java',
        InteropFixtureRoots.javaFiles,
      );

      _expectRootError(
        packageRoot: Directory(p.join(tempRoot.path, 'core')),
        environment: <String, String>{
          InteropFixtureRoots.appRootKey: ' ',
          InteropFixtureRoots.javaRootKey: java.path,
        },
        key: InteropFixtureRoots.appRootKey,
      );
    });

    test('rejects an absent Java root with its key and path', () {
      final app = _createFixtures(
        tempRoot,
        'relocated/app',
        InteropFixtureRoots.appFiles,
      );
      final missingJava = p.join(tempRoot.path, 'missing-java');

      _expectRootError(
        packageRoot: Directory(p.join(tempRoot.path, 'core')),
        environment: <String, String>{
          InteropFixtureRoots.appRootKey: app.path,
          InteropFixtureRoots.javaRootKey: missingJava,
        },
        key: InteropFixtureRoots.javaRootKey,
        path: missingJava,
      );
    });

    test(
      'rejects a Java root missing a required file with its exact path',
      () {
        final app = _createFixtures(
          tempRoot,
          'relocated/app',
          InteropFixtureRoots.appFiles,
        );
        final java = Directory(p.join(tempRoot.path, 'invalid-java'))
          ..createSync();
        final missingFile = p.join(
          java.path,
          InteropFixtureRoots.javaFiles.first,
        );

        _expectRootError(
          packageRoot: Directory(p.join(tempRoot.path, 'core')),
          environment: <String, String>{
            InteropFixtureRoots.appRootKey: app.path,
            InteropFixtureRoots.javaRootKey: java.path,
          },
          key: InteropFixtureRoots.javaRootKey,
          path: missingFile,
        );
      },
    );

    test('rejects an empty Java root with its configuration key', () {
      final app = _createFixtures(
        tempRoot,
        'relocated/app',
        InteropFixtureRoots.appFiles,
      );

      _expectRootError(
        packageRoot: Directory(p.join(tempRoot.path, 'core')),
        environment: <String, String>{
          InteropFixtureRoots.appRootKey: app.path,
          InteropFixtureRoots.javaRootKey: ' ',
        },
        key: InteropFixtureRoots.javaRootKey,
      );
    });
  });
}

void _expectRootError({
  required Directory packageRoot,
  required Map<String, String> environment,
  required String key,
  String? path,
}) {
  expect(
    () => InteropFixtureRoots.resolve(
      packageRoot: packageRoot,
      environment: environment,
    ),
    throwsA(
      isA<StateError>()
          .having(
            (error) => error.message,
            'message',
            contains(key),
          )
          .having(
            (error) => error.message,
            'message',
            path == null ? isNotNull : contains(path),
          ),
    ),
  );
}

Directory _createFixtures(
  Directory parent,
  String relative,
  List<String> files,
) {
  final root = Directory(p.join(parent.path, relative));
  for (final file in files) {
    final fixture = File(p.join(root.path, file));
    fixture.parent.createSync(recursive: true);
    fixture.writeAsStringSync('fixture');
  }
  return root;
}

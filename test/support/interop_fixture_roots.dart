import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Resolves the core-owned source through its Dart package identity and the
/// external ArkTS fixtures through explicit roots or legacy sibling defaults.
class InteropFixtureRoots {
  static const appRootKey = 'QFLI_STUDIO_APP_ROOT';
  static const javaRootKey = 'QFLI_STUDIO_JAVA_ROOT';

  static const appFiles = <String>[
    'ohos/entry/src/main/ets/interop/StudioInterop.ets',
    'ohos/entry/src/main/module.json5',
    'ohos/entry/src/main/resources/base/element/string.json',
  ];

  static const javaFiles = <String>[
    'ohos/entry/src/main/ets/interop/InteropReceiver.ets',
    'ohos/entry/src/main/module.json5',
  ];

  const InteropFixtureRoots({required this.app, required this.java});

  final Directory app;
  final Directory java;

  static Directory resolveCorePackageRoot() {
    final sourceUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:qfli_studio_core/interop/interop_protocol.dart'),
    );
    if (sourceUri == null || sourceUri.scheme != 'file') {
      throw StateError(
        'Could not resolve '
        'package:qfli_studio_core/interop/interop_protocol.dart '
        'to a file URI: $sourceUri',
      );
    }

    final source = File.fromUri(sourceUri);
    final packageRoot = Directory(
      p.dirname(p.dirname(p.dirname(source.path))),
    );
    if (!source.existsSync() ||
        !File(p.join(packageRoot.path, 'pubspec.yaml')).existsSync()) {
      throw StateError(
        'Resolved qfli_studio_core package source has no matching '
        'package root: ${source.path}',
      );
    }
    return packageRoot;
  }

  static InteropFixtureRoots resolve({
    required Directory packageRoot,
    Map<String, String>? environment,
  }) {
    final values = environment ?? Platform.environment;
    // Legacy defaults preserve the hosted siblings qflistudio and qfli_java;
    // callers with another checkout layout must set the explicit roots.
    final legacyParent = Directory(p.dirname(packageRoot.path));
    return InteropFixtureRoots(
      app: _resolveRoot(
        key: appRootKey,
        configuredPath: values[appRootKey],
        legacyPath: p.join(legacyParent.path, 'qflistudio'),
        requiredFiles: appFiles,
      ),
      java: _resolveRoot(
        key: javaRootKey,
        configuredPath: values[javaRootKey],
        legacyPath: p.join(legacyParent.path, 'qfli_java'),
        requiredFiles: javaFiles,
      ),
    );
  }

  static Directory _resolveRoot({
    required String key,
    required String? configuredPath,
    required String legacyPath,
    required List<String> requiredFiles,
  }) {
    if (configuredPath != null && configuredPath.trim().isEmpty) {
      throw StateError(
        '$key is set but empty; provide a fixture directory path.',
      );
    }

    final path = p.normalize(p.absolute(configuredPath ?? legacyPath));
    final root = Directory(path);
    if (!root.existsSync()) {
      final source = configuredPath == null
          ? 'legacy sibling default (because $key is unset)'
          : '$key';
      throw StateError(
        '$source must point to an existing directory: $path',
      );
    }

    for (final relative in requiredFiles) {
      final fixturePath = p.join(root.path, relative);
      if (!File(fixturePath).existsSync()) {
        throw StateError(
          '$key is missing required fixture: $fixturePath',
        );
      }
    }
    return root;
  }
}

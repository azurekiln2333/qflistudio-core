import 'dart:convert';
import 'dart:io';

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

  static Directory resolveCorePackageRoot({File? packageConfig}) {
    final config = (packageConfig ?? _findPackageConfig()).absolute;
    final Object? decoded;
    try {
      decoded = jsonDecode(config.readAsStringSync());
    } on FileSystemException catch (error) {
      throw _packageConfigError(config, 'cannot read configuration: $error');
    } on FormatException catch (error) {
      throw _packageConfigError(config, 'invalid JSON: ${error.message}');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['configVersion'] != 2 ||
        decoded['packages'] is! List<dynamic>) {
      throw _packageConfigError(config, 'expected version 2 and a packages list');
    }
    final matches = (decoded['packages'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .where((package) => package['name'] == 'qfli_studio_core')
        .toList();
    if (matches.length != 1) {
      throw _packageConfigError(config, 'expected one qfli_studio_core entry');
    }
    final rootValue = matches.single['rootUri'];
    if (rootValue is! String || rootValue.trim().isEmpty) {
      throw _packageConfigError(config, 'qfli_studio_core rootUri is missing');
    }
    final Uri rootUri;
    try {
      rootUri = config.uri.resolve(rootValue);
    } on FormatException catch (error) {
      throw _packageConfigError(config, 'invalid rootUri: ${error.message}');
    }
    if (rootUri.scheme != 'file') {
      throw _packageConfigError(config, 'rootUri must resolve to a file URI');
    }
    final packageRoot = Directory.fromUri(rootUri);
    for (final relative in <String>[
      'pubspec.yaml',
      'lib/interop/interop_protocol.dart',
    ]) {
      final source = File(p.join(packageRoot.path, relative));
      if (!source.existsSync()) {
        throw _packageConfigError(config, 'missing package file: ${source.path}');
      }
    }
    return packageRoot;
  }

  static File _findPackageConfig() {
    // The working directory locates configuration, never the core checkout.
    // Resolve the package identity from that configuration even in consumers.
    var directory = Directory.current.absolute;
    while (true) {
      final config = File(
        p.join(directory.path, '.dart_tool', 'package_config.json'),
      );
      if (config.existsSync()) return config;
      final parent = directory.parent;
      if (parent.path == directory.path) {
        throw StateError(
          'Cannot resolve qfli_studio_core: no .dart_tool/package_config.json '
          'at or above ${Directory.current.path}. '
          'Run package resolution on the hosted runner first.',
        );
      }
      directory = parent;
    }
  }

  static StateError _packageConfigError(File config, String detail) {
    return StateError(
      'Cannot resolve qfli_studio_core from ${config.path}: $detail',
    );
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
      throw StateError('$source must point to an existing directory: $path');
    }

    for (final relative in requiredFiles) {
      final fixturePath = p.join(root.path, relative);
      if (!File(fixturePath).existsSync()) {
        throw StateError('$key is missing required fixture: $fixturePath');
      }
    }
    return root;
  }
}

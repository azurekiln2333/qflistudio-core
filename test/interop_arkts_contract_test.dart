import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';

/// Contract tests for the ArkTS half of qfli-interop/1.
///
/// The ArkTS receiver cannot run in this test harness, so its behaviour is
/// pinned by reading the source. That is weaker than executing it, and the
/// weak spots are named in the task's design.md. What it does catch is the
/// failure mode that matters: one side silently drifting from the other on the
/// allowlist, the protocol string or a grammar rule.
void main() {
  final root = Directory.current.parent;

  String read(String app, String relative) {
    final file = File(p.join(root.path, app, relative));
    if (!file.existsSync()) {
      throw StateError('missing ${file.path}');
    }
    return file.readAsStringSync();
  }

  group('Studio side', () {
    final source = read(
      'qflistudio',
      p.join('ohos', 'entry', 'src', 'main', 'ets', 'interop',
          'StudioInterop.ets'),
    );

    test('speaks the same protocol string as the Dart client', () {
      expect(source, contains("const PROTOCOL = '$kInteropProtocol'"));
    });

    test('accepts only the bundles the Dart target table declares', () {
      for (final target in InteropTargets.all) {
        expect(
          source,
          contains("'${target.bundleName}'"),
          reason: '${target.bundleName} is missing from the Studio allowlist',
        );
      }
      expect(source, contains('ALLOWED_RECEIVERS'));
    });

    test('sends its own bundle name as the caller', () {
      expect(source, contains("'${InteropStudio.bundleName}'"));
    });

    test('enforces the same payload caps', () {
      expect(source, contains('256 * 1024'));
      expect(source, contains('= 64;'));
      expect(source, contains('= 240;'));
      expect(source, contains('= 4 * 1024;'));
    });

    test('rejects the same path shapes', () {
      expect(source, contains(r"/^[A-Za-z]:/"));
      expect(source, contains("path.charAt(0) === '/'"));
      expect(source, contains("segment === '..'"));
      expect(source, contains("segment.charAt(0) === '.'"));
    });
  });

  group('Java receiver', () {
    final source = read(
      'qfli_java',
      p.join('ohos', 'entry', 'src', 'main', 'ets', 'interop',
          'InteropReceiver.ets'),
    );

    test('answers only the Studio bundle', () {
      expect(source, contains("const ALLOWED_CALLER = '${InteropStudio.bundleName}'"));
    });

    test('refuses any language it does not implement', () {
      expect(source, contains("export const LANGUAGE = 'java'"));
      expect(source, contains('unsupported_language'));
    });

    test('rejects the same path shapes as the Dart grammar', () {
      expect(source, contains(r"/^[A-Za-z]:/"));
      expect(source, contains("path.charAt(0) === '/'"));
      expect(source, contains("segment === '..'"));
      expect(source, contains("segment.charAt(0) === '.'"));
    });

    test('reports every refusal code the Dart side understands', () {
      for (final code in <String>[
        InteropErrorCode.badRequest,
        InteropErrorCode.unsupportedProtocol,
        InteropErrorCode.callerNotAllowed,
        InteropErrorCode.payloadTooLarge,
        InteropErrorCode.compileFailed,
        InteropErrorCode.runFailed,
        InteropErrorCode.timeout,
      ]) {
        expect(source, contains("'$code'"), reason: '$code is not produced');
      }
    });

    test('sends the terminal events the Dart transport waits for', () {
      expect(source, contains("'done'"));
      expect(source, contains("'error'"));
      expect(source, contains("'stdout'"));
      expect(source, contains("'stderr'"));
      expect(source, contains("'progress'"));
      expect(source, contains("'accepted'"));
    });

    test('the module exports the ability the Studio target names', () {
      final module = read(
        'qfli_java',
        p.join('ohos', 'entry', 'src', 'main', 'module.json5'),
      );
      expect(module, contains('"name": "${InteropTargets.java.abilityName}"'));
      expect(module, contains('"exported": true'));
      expect(
        module,
        contains(
          './ets/interop/${InteropTargets.java.abilityName}.ets',
        ),
      );
    });
  });

  group('Studio module', () {
    final module = read(
      'qflistudio',
      p.join('ohos', 'entry', 'src', 'main', 'module.json5'),
    );

    test('exports the bridge ability with the agreed action', () {
      expect(module, contains('"name": "${InteropStudio.bridgeAbility}"'));
      expect(module, contains('"${InteropStudio.bridgeAction}"'));
      expect(module, contains('"exported": true'));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';

import 'support/interop_fixture_roots.dart';

/// Contract tests for the ArkTS half of qfli-interop/1.
///
/// The ArkTS receiver cannot run in this test harness, so its behaviour is
/// pinned by reading the source. That is weaker than executing it, and the
/// weak spots are named in the task's design.md. What it does catch is the
/// failure mode that matters: one side silently drifting from the other on the
/// allowlist, the protocol string or a grammar rule.
void main() {
  final coreRoot = InteropFixtureRoots.resolveCorePackageRoot();
  final fixtures = InteropFixtureRoots.resolve(packageRoot: coreRoot);

  String read(Directory root, String relative) {
    final file = File(p.join(root.path, relative));
    if (!file.existsSync()) {
      throw StateError('missing ${file.path}');
    }
    return file.readAsStringSync();
  }

  group('Studio side', () {
    final source = read(
      fixtures.app,
      p.join(
        'ohos',
        'entry',
        'src',
        'main',
        'ets',
        'interop',
        'StudioInterop.ets',
      ),
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

  group('channel argument contract', () {
    // The probe bug this group exists for: Dart sent `bundleName` as a channel
    // argument while the ArkTS handler stored it as `targetBundle` and the
    // probe read `bundleName`. Every side compiled; the device answered
    // "unknown app" for an installed app. Text checks on the protocol string
    // could not see it because the two sides never disagreed on the protocol.
    //
    // So the keys are compared, not described: the Dart file is parsed for the
    // channel arguments it sends and the ArkTS file for what it reads.

    final transport = read(
      coreRoot,
      p.join(
        'lib',
        'interop',
        'interop_transport.dart',
      ),
    );
    final bridge = read(
      fixtures.app,
      p.join(
        'ohos',
        'entry',
        'src',
        'main',
        'ets',
        'interop',
        'StudioInterop.ets',
      ),
    );

    /// Top-level argument keys sent with `invokeMethod`/`invokeMapMethod`, in
    /// order, for the method named [method].
    List<String> sentKeys(String method) {
      final call = RegExp(
        "methods\\s*\\.\\s*invoke(?:Map)?Method\\s*<[^>]*>\\(\\s*'$method'\\s*,",
      ).firstMatch(transport);
      expect(call, isNotNull, reason: 'no channel call for $method');
      final start = call!.end;
      final close = transport.indexOf(')', start);
      expect(close, greaterThan(start), reason: 'unterminated $method call');
      final block = transport.substring(start, close);
      final keys = RegExp(r"'([A-Za-z][A-Za-z0-9]*)'\s*:").allMatches(block);
      return keys.map((match) => match.group(1)!).toList();
    }

    test('probe sends the keys the bridge stores for probe', () {
      expect(sentKeys('probe'), <String>[
        'bundleName',
        'abilityName',
        'language',
        'protocol',
      ]);
    });

    test('start sends the keys the bridge reads for start', () {
      expect(sentKeys('start'), <String>[
        'bundleName',
        'abilityName',
        'parameters',
      ]);
    });

    test('the bridge reads probe values under names it actually stores', () {
      // `onMethodCall` copies channel arguments into the map the handlers read.
      // A handler that reads a key the bridge never sets gets undefined, which
      // is exactly the shipped probe bug.
      final copied = RegExp(
        "raw\\.set\\('([A-Za-z][A-Za-z0-9]*)'",
      ).allMatches(bridge).map((match) => match.group(1)!).toSet();
      final stored = RegExp(
        "raw\\.set\\(key,",
      ).hasMatch(bridge);
      expect(
        copied,
        containsAll(<String>['targetBundle']),
        reason: 'the bridge no longer copies bundleName to targetBundle',
      );
      expect(
        stored,
        isTrue,
        reason: 'the bridge no longer copies the extra channel arguments',
      );
      final probeBody = RegExp(
        r'export function probe\(raw: Map<string, string>\)[\s\S]*?\n}',
      ).firstMatch(bridge);
      expect(probeBody, isNotNull, reason: 'probe is gone or renamed');
      final readKey = RegExp(
        "raw\\.get\\('([A-Za-z][A-Za-z0-9]*)'\\)",
      ).firstMatch(probeBody!.group(0)!)!;
      expect(
        readKey.group(1),
        'targetBundle',
        reason: 'probe reads a key the channel never sets',
      );
    });

    test('the bridge answers installed and available separately', () {
      // The Dart reader treats `installed` as the authority and falls back to
      // `unknown`. A bridge that stops reporting it would silently turn every
      // answer into "unknown", so the answer keys are pinned here too.
      for (final key in <String>[
        "result.set('installed'",
        "result.set('available'",
        "result.set('languages'",
      ]) {
        expect(bridge, contains(key));
      }
    });

    test('the probe uses a start, not a bundle query', () {
      // `GET_BUNDLE_INFO` is a system permission. On a device the query failed
      // with 8521226 and the probe could only ever answer "unknown", so the
      // check must stay on the start outcome. The comment may still name the
      // permission; the call must not exist.
      expect(bridge, isNot(contains('getBundleInfoSync')));
      expect(bridge, isNot(contains('getBundleInfo(')));
      expect(bridge, isNot(contains('getBundleInfoForSelfSync')));
      expect(bridge, isNot(contains("import { bundleManager }")));
      expect(bridge, contains('startAbility'));
    });

    test('the probe names both start errors that mean not installed', () {
      // 16000001: ability does not exist. 16000003: bundle does not exist.
      expect(bridge, contains('16000001'));
      expect(bridge, contains('16000003'));
    });

    test('the probe asks for an analyze that runs no compiler', () {
      final probeBody = RegExp(
        r'async function probeByStart[\s\S]*?\n}',
      ).firstMatch(bridge);
      expect(probeBody, isNotNull, reason: 'probeByStart is gone or renamed');
      final body = probeBody!.group(0)!;
      expect(body, contains("'action'"));
      expect(body, contains("'analyze'"));
      expect(body, contains("'payloadUri'"));
    });

    test('no bundle permission is declared or needed', () {
      final module = read(
        fixtures.app,
        p.join(
          'ohos',
          'entry',
          'src',
          'main',
          'module.json5',
        ),
      );
      expect(module, isNot(contains('GET_BUNDLE_INFO')));
      final strings = read(
        fixtures.app,
        p.join(
          'ohos',
          'entry',
          'src',
          'main',
          'resources',
          'base',
          'element',
          'string.json',
        ),
      );
      expect(strings, isNot(contains('bundle_info_reason')));
    });

    test('the Dart reader accepts exactly the keys the bridge reports', () {
      for (final key in <String>[
        'installed',
        'available',
        'languages',
        'protocol',
      ]) {
        expect(transport, contains("raw['$key']"));
      }
    });
  });

  group('Java receiver', () {
    final source = read(
      fixtures.java,
      p.join(
        'ohos',
        'entry',
        'src',
        'main',
        'ets',
        'interop',
        'InteropReceiver.ets',
      ),
    );

    test('answers only the Studio bundle', () {
      expect(
        source,
        contains("const ALLOWED_CALLER = '${InteropStudio.bundleName}'"),
      );
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

    test('delivers one terminal event carrying the aggregated output', () {
      // Streaming several events is impossible: each bridge start hands the
      // foreground back to Studio and the system then refuses the next start
      // from the now-background receiver, so the run crosses as one done or
      // error whose text holds the whole output.
      expect(source, contains("'done'"));
      expect(source, contains("'error'"));
      expect(source, contains('formatAggregate'));
      expect(source, contains('OUTPUT_TAIL_BYTES'));
      expect(source, isNot(contains("'progress'")));
    });

    test('the module exports the ability the Studio target names', () {
      final module = read(
        fixtures.java,
        p.join(
          'ohos',
          'entry',
          'src',
          'main',
          'module.json5',
        ),
      );
      expect(
        module,
        contains('"name": "${InteropTargets.java.abilityName}"'),
      );
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
      fixtures.app,
      p.join(
        'ohos',
        'entry',
        'src',
        'main',
        'module.json5',
      ),
    );

    test('exports the bridge ability with the agreed action', () {
      expect(module, contains('"name": "${InteropStudio.bridgeAbility}"'));
      expect(module, contains('"${InteropStudio.bridgeAction}"'));
      expect(module, contains('"exported": true'));
    });
  });
}

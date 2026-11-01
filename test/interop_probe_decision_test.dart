import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';
import 'package:qfli_studio_core/interop/interop_transport.dart';

/// The probe answer drives one user-visible decision: whether Run stays on the
/// original path or moves into a sibling app.
///
/// Three states exist because the platform can refuse the bundle query. The
/// tests pin what each state means for the run button, so a future probe that
/// reports "unknown" can never be read as "installed" or "missing" by accident.
void main() {
  final target = InteropTargets.java;

  group('probe states', () {
    test('installed offers the cross-app run', () {
      const probe = InteropProbe.installed(protocol: 'qfli-interop/1');
      expect(probe.status, InteropProbeStatus.installed);
      expect(probe.isInstalled, isTrue);
      expect(probe.available, isTrue);
    });

    test('missing refuses the cross-app run and names what to install', () {
      final probe = InteropProbe.missing(
        InteropTargets.installHint(target.language),
      );
      expect(probe.status, InteropProbeStatus.missing);
      expect(probe.isInstalled, isFalse);
      expect(probe.available, isFalse);
      expect(probe.diagnostic, contains('QFLIJVMX'));
      expect(probe.diagnostic, contains('com.azurekiln.qfli.java'));
    });

    test('unknown is neither installed nor missing', () {
      const probe = InteropProbe.unknown('无法确认 QFLIJVMX 是否已安装。');
      expect(probe.status, InteropProbeStatus.unknown);
      expect(probe.isInstalled, isFalse);
      // The Run button keeps its original path, but an explicit request from
      // the menu may still try, because the start call fails honestly.
      expect(probe.available, isTrue);
      expect(probe.diagnostic, isNotNull);
    });
  });

  group('run button decision', () {
    /// The same rule `EditorPage._answeringSiblingApp` applies.
    InteropTarget? decide(InteropProbe probe) =>
        probe.isInstalled ? target : null;

    test('an installed receiver takes the tap', () {
      expect(
        decide(const InteropProbe.installed(protocol: 'qfli-interop/1')),
        isNotNull,
      );
    });

    test('a missing receiver leaves the tap on the original path', () {
      expect(decide(const InteropProbe.missing('未安装')), isNull);
    });

    test('an unknown receiver leaves the tap on the original path', () {
      expect(decide(const InteropProbe.unknown('无法确认')), isNull);
    });

    test('a language without a receiver never offers the run', () {
      expect(InteropTargets.forEntryFile('main.go'), isNull);
      expect(InteropTargets.forEntryFile('index.html'), isNull);
    });
  });

  group('label', () {
    test('names the app the user will see', () {
      expect(target.productName, 'QFLIJVMX');
    });

    test('run dialog titles carry the product name', () {
      // The dialog builds its title from the same product name, so the user can
      // always tell which app is running the project.
      expect(InteropTargets.forLanguage('java')?.productName, 'QFLIJVMX');
      expect(InteropTargets.forLanguage('c')?.productName, 'QFLIForge');
      expect(InteropTargets.forLanguage('python')?.productName, 'QFLIPyFlow');
    });
  });
}

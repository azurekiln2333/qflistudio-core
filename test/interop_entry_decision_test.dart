import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/interop/interop_targets.dart';

/// The editor shows a cross-app run entry only when
/// [InteropTargets.forEntryFile] returns a receiver for the project entry.
///
/// That decision drives a visible menu item, so it is pinned here rather than
/// only by hand: an entry the map does not know must produce no menu item, and
/// an entry it does know must name the app the user has to install.
void main() {
  group('editor entry decision', () {
    for (final entry in <String>[
      'Main.java',
      'src/main/java/demo/Main.java',
      'MAIN.JAVA',
    ]) {
      test('$entry offers the Java receiver', () {
        final target = InteropTargets.forEntryFile(entry);
        expect(target, isNotNull);
        expect(target!.language, 'java');
        expect(target.bundleName, 'com.azurekiln.qfli.java');
        expect(target.productName, 'QFLIJVMX');
      });
    }

    for (final entry in <String>[
      'main.c',
      'src/main.cc',
      'main.cpp',
      'x.cxx',
    ]) {
      test('$entry offers the C/C++ receiver', () {
        final target = InteropTargets.forEntryFile(entry);
        expect(target, isNotNull);
        expect(target!.bundleName, 'com.azurekiln.qfli.cpp');
      });
    }

    test('main.py offers the Python receiver', () {
      final target = InteropTargets.forEntryFile('pkg/main.py');
      expect(target, isNotNull);
      expect(target!.bundleName, 'com.azurekiln.qfli.pyflow');
    });

    for (final entry in <String>['main.go', 'index.html', 'main.rs', '']) {
      test('${entry.isEmpty ? 'empty name' : entry} offers nothing', () {
        expect(InteropTargets.forEntryFile(entry), isNull);
      });
    }

    test('an extension alone does not need the file to exist', () {
      // The probe decides installation; the map only decides which app to ask.
      expect(
        InteropTargets.forEntryFile(p.join('project', 'Missing.java')),
        isNotNull,
      );
    });
  });

  group('install hint', () {
    test('names the app the user must install', () {
      final hint = InteropTargets.installHint('java');
      expect(hint, contains('QFLIJVMX'));
      expect(hint, contains('com.azurekiln.qfli.java'));
    });

    test('does not promise a run for a language with no receiver', () {
      final hint = InteropTargets.installHint('go');
      expect(hint, contains('go'));
      expect(hint, isNot(contains('QFLIJVMX')));
    });
  });
}

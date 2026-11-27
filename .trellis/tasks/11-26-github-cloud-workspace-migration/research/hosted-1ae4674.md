# Research: Published core hosted CI at 1ae4674

- Query: Does the exact gate-published migration candidate pass its hosted core and consumer gates, and what finite failures need owner repair?
- Scope: internal source and GitHub-hosted workflow metadata/log text only
- Date: 2026-11-28 (Asia/Shanghai)
- Repository: `azurekiln2333/qflistudio-core`
- Commit: `1ae4674a4b153701b0c3b3ff04b1a1b77a318611`
- Gate-reported tree: `8d555b8b9ef4dd92d07dc692f4d6ebaae3d0f724`

## Findings

Publication passed, but both exact-commit hosted workflows completed with failure. This is not a final CI acceptance. Target synchronization is a separate coordinator lane; this observer did not inspect or mutate target Git state.

### Exact hosted jobs

| Workflow/run | Job ID | Result and material boundary |
| --- | --- | --- |
| core-check / 46042974549 | 140655095032 | screenshots success |
| core-check / 46042974549 | 140655095477 | check: analysis passed; formatting and complete suite failed |
| core-check / 46042974549 | 140655095401 | legacy: analysis passed; complete suite failed |
| core-check / 46042974549 | 140655095502 | canonical: analysis passed; complete suite failed |
| core-check / 46042974549 | 140655095683 | relocated: analysis passed; complete suite failed |
| core-check / 46042974549 | 140655095356 | invalid-java-root: resolver unit tests passed; expected-invalid-root check failed |
| core-check / 46042974549 | 140655095408 | missing-app-root: resolver unit tests passed; expected-missing-root check failed |
| core-consumer-check / 46042974535 | 140655094805 | OHOS: preparation unit tests/SDK install passed; fixed-filter formatting failed; consumer resolution/compile skipped |
| core-consumer-check / 46042974535 | 140655095455 | official: preparation unit tests/SDK install passed; runner preparation step failed while parsing version evidence; consumer resolution/compile skipped |

### 1. Unsupported package resolver blocks contract registration

The main check and both intentional-negative logs directly report:

```text
Unsupported operation: Isolate.resolvePackageUriSync
dart:isolate                                   Isolate.resolvePackageUriSync
test/support/interop_fixture_roots.dart 29:31  InteropFixtureRoots.resolveCorePackageRoot
test/interop_arkts_contract_test.dart 18:40    main
```

At this commit `test/support/interop_fixture_roots.dart:29` calls the synchronous isolate API for `package:qfli_studio_core/interop/interop_protocol.dart`. `test/interop_arkts_contract_test.dart:18` invokes it while registering the suite. The negative jobs therefore fail before reaching the configured fixture validation; rejecting their unrelated error is correct. The existing root unit cases call `resolve(packageRoot: ...)` directly and do not cover actual package-root discovery.

Finite repair: use package-identity resolution supported by the hosted Flutter test runtime, retain checkout-basename independence, and directly cover package-root discovery. Preserve all fixture assertions and both environment-key/path negative checks. Do not assume another isolate resolver API works without hosted evidence. Update `.trellis/spec/backend/interop-fixtures.md`, which currently prescribes the unsupported synchronous API.

The complete main-check JSON event stream contains 3,703 test completion events: 3,315 visible successes, 27 visible skips, one visible loading error, and 360 hidden successes. There is exactly one `error` event and no additional failed test completion. Its terminal event reports `success=false`. The lone error is the contract suite loading failure above. This count is for main check job 140655095477 only; the other three positive layout logs were not independently enumerated.

### 2. Official preparation succeeds before version JSON capture fails

`tool/ci/prepare_flutter_core.py` succeeds in official mode and emits `changed=true`, `native_ohos_view_preserved=false`, SDK revision `ae9b586f34a8443573f82ef57c3bf914a908cbf7`, and prepared view SHA-256 `5609b79e493cff0a657bfca12df1719a2b2724a11735140d492279bb1c13b658`.

The subsequent `.github/workflows/core-consumer-check.yml:71` machine-version command is the first Flutter invocation for this freshly cloned official SDK. Its captured output contains Dart SDK/tool bootstrap text, dependency resolution, and `Changed 101 dependencies` before the valid version object. The parser then throws:

```text
json.decoder.JSONDecodeError: Expecting value: line 1 column 3 (char 2)
```

The actual version object reports Flutter `3.50.1`, framework revision `ae9b586f34a8443573f82ef57c3bf914a908cbf7`, Dart `3.14.0`, and engine `4d35714800b9266b6693a58e1225ecd7e9e45ed7`. Finite repair: bootstrap separately, then capture clean machine JSON and retain the exact framework-revision assertion. This failure is evidence parsing, not a failed official-view shim. Neither consumer dependency resolution nor compilation was reached, so no consumer compatibility success is established.

### 3. Hosted formatter output identifies source corrections

OHOS consumer job 140655094805 reports `Changed lib/pages/local_content_pages.dart` and `Formatted 2 files (1 changed)` for its fixed-filter source/regression formatting step. It does not emit a patch. That output also warns that `package:flutter_lints/flutter.yaml` cannot resolve before root package resolution. No exact local-content formatting edit is inferred here.

Main check reports formatting changes in these three files and includes the full patch reproduced below:

- `test/interop_arkts_contract_test.dart`
- `test/interop_fixture_roots_test.dart`
- `test/support/interop_fixture_roots.dart`

The edits collapse or reflow expressions and callbacks; they do not remove assertions. Apply relevant hosted formatting corrections alongside the resolver repair, then verify the resulting immutable candidate on hosted runners. No formatter was run locally.

### Files and related specs

| Path | Responsibility / observed pattern |
| --- | --- |
| `.github/workflows/core-check.yml` | Main checks, checkout-layout matrix, intentional-negative root modes, screenshots and evidence upload |
| `.github/workflows/core-consumer-check.yml:71` | First machine-version capture before JSON parsing |
| `test/support/interop_fixture_roots.dart:29` | Unsupported synchronous package resolver |
| `test/interop_arkts_contract_test.dart:18` | Package discovery during contract registration |
| `test/interop_fixture_roots_test.dart:33` | Fixture root tests inject packageRoot rather than exercising discovery |
| `lib/pages/local_content_pages.dart` | Sole file rejected by fixed-filter formatting gate |
| `.trellis/spec/backend/interop-fixtures.md` | Checkout-independent fixture contract; resolver API guidance needs repair |
| `.trellis/spec/backend/core-consumers.md` | Required re_editor override, direct vendored xterm, exact-SDK preparation and evidence boundary |
| `.trellis/workflow.md` | Cloud-only product validation and durable summarized evidence policy |

### Primary hosted references and log identity

All references below identify ordinary GitHub hosted results, not signed log-download URLs.

- `https://github.com/azurekiln2333/qflistudio-core/actions/runs/46042974549`
- `https://github.com/azurekiln2333/qflistudio-core/actions/runs/46042974535`

Log identity is SHA-256 of the returned UTF-8 stdout bytes, including the selected endpoint/CLI's prefixes; it is not an artifact checksum.

| Retrieved text | Bytes / lines | SHA-256 |
| --- | --- | --- |
| Main check failed-step view | 2629349 / 9401 | `54228aa78feb1de1f8b3969011d31e0ff23b92f14ebdd4adc9a1a7e55ed444a9` |
| Official preparation failed-step view | 30688 / 170 | `00db5743e356e42f340d0e979ed2dfb35322e403d12d6ff685963360c488287b` |
| OHOS formatting failed-step view | 11314 / 47 | `37f971503c3e16415d95326d88bc4f5f65e6de3f505dd06319489412114a08e1` |
| Invalid Java direct job log | 80311 / 920 | `382b4b66efd19dde40ccfbb2bc3dec98e1f3cb4a927fbe01285e7338b97cebf8` |
| Missing App direct job log | 79142 / 910 | `1643f8373b67dee3da1a323a7fd6ddf33474ee09ed0db9ab3b3c3c58238c3582` |

## Caveats / Not Found

- Only GitHub metadata/log-text reads and source reads were used. No product build/test/analyze/formatter/install ran locally; no artifact/SDK download, workflow dispatch, rerun, Git mutation or target mutation was performed.
- Direct log endpoints intermittently timed out or returned EOF. Bounded failed-step log reads supplied the successful main/consumer excerpts; no transport error is classified as a product failure.
- Evidence upload steps succeeded, but artifact contents, retention, signatures, installability and native/device execution were not inspected or established.
- Legacy/canonical/relocated job conclusions and failed steps were inspected; their complete failure inventories were not independently parsed. Do not assign the main-check count to those jobs.
- This report diagnoses the published commit only. Unpublished repairs by other agents require their own exact-SHA hosted gates.
- The coordinator and assigned repair agents received the finite resolver, version-capture, and formatting findings. This observer wrote only this research file.

## Hosted formatter patch

The following is the complete formatter patch from main check job 140655095477. It is source-repair evidence, not local formatter output.

```diff
diff --git a/test/interop_arkts_contract_test.dart b/test/interop_arkts_contract_test.dart
index 21ad6e4..dc1e99a 100644
--- a/test/interop_arkts_contract_test.dart
+++ b/test/interop_arkts_contract_test.dart
@@ -86,11 +86,7 @@ void main() {
 
     final transport = read(
       coreRoot,
-      p.join(
-        'lib',
-        'interop',
-        'interop_transport.dart',
-      ),
+      p.join('lib', 'interop', 'interop_transport.dart'),
     );
     final bridge = read(
       fixtures.app,
@@ -144,9 +140,7 @@ void main() {
       final copied = RegExp(
         "raw\\.set\\('([A-Za-z][A-Za-z0-9]*)'",
       ).allMatches(bridge).map((match) => match.group(1)!).toSet();
-      final stored = RegExp(
-        "raw\\.set\\(key,",
-      ).hasMatch(bridge);
+      final stored = RegExp("raw\\.set\\(key,").hasMatch(bridge);
       expect(
         copied,
         containsAll(<String>['targetBundle']),
@@ -216,13 +210,7 @@ void main() {
     test('no bundle permission is declared or needed', () {
       final module = read(
         fixtures.app,
-        p.join(
-          'ohos',
-          'entry',
-          'src',
-          'main',
-          'module.json5',
-        ),
+        p.join('ohos', 'entry', 'src', 'main', 'module.json5'),
       );
       expect(module, isNot(contains('GET_BUNDLE_INFO')));
       final strings = read(
@@ -315,24 +303,13 @@ void main() {
     test('the module exports the ability the Studio target names', () {
       final module = read(
         fixtures.java,
-        p.join(
-          'ohos',
-          'entry',
-          'src',
-          'main',
-          'module.json5',
-        ),
-      );
-      expect(
-        module,
-        contains('"name": "${InteropTargets.java.abilityName}"'),
+        p.join('ohos', 'entry', 'src', 'main', 'module.json5'),
       );
+      expect(module, contains('"name": "${InteropTargets.java.abilityName}"'));
       expect(module, contains('"exported": true'));
       expect(
         module,
-        contains(
-          './ets/interop/${InteropTargets.java.abilityName}.ets',
-        ),
+        contains('./ets/interop/${InteropTargets.java.abilityName}.ets'),
       );
     });
   });
@@ -340,13 +317,7 @@ void main() {
   group('Studio module', () {
     final module = read(
       fixtures.app,
-      p.join(
-        'ohos',
-        'entry',
-        'src',
-        'main',
-        'module.json5',
-      ),
+      p.join('ohos', 'entry', 'src', 'main', 'module.json5'),
     );
 
     test('exports the bridge ability with the agreed action', () {
diff --git a/test/interop_fixture_roots_test.dart b/test/interop_fixture_roots_test.dart
index cf402d3..16467fc 100644
--- a/test/interop_fixture_roots_test.dart
+++ b/test/interop_fixture_roots_test.dart
@@ -43,9 +43,8 @@ void main() {
     });
 
     test('uses documented legacy sibling defaults when roots are unset', () {
-      final packageRoot = Directory(
-        p.join(tempRoot.path, 'qfli_studio_core'),
-      )..createSync();
+      final packageRoot = Directory(p.join(tempRoot.path, 'qfli_studio_core'))
+        ..createSync();
       final app = _createFixtures(
         tempRoot,
         'qflistudio',
@@ -84,32 +83,25 @@ void main() {
       );
     });
 
-    test(
-      'rejects an App root missing a required file with its exact path',
-      () {
-        final app = Directory(p.join(tempRoot.path, 'invalid-app'))
-          ..createSync();
-        final java = _createFixtures(
-          tempRoot,
-          'relocated/java',
-          InteropFixtureRoots.javaFiles,
-        );
-        final missingFile = p.join(
-          app.path,
-          InteropFixtureRoots.appFiles.first,
-        );
-
-        _expectRootError(
-          packageRoot: Directory(p.join(tempRoot.path, 'core')),
-          environment: <String, String>{
-            InteropFixtureRoots.appRootKey: app.path,
-            InteropFixtureRoots.javaRootKey: java.path,
-          },
-          key: InteropFixtureRoots.appRootKey,
-          path: missingFile,
-        );
-      },
-    );
+    test('rejects an App root missing a required file with its exact path', () {
+      final app = Directory(p.join(tempRoot.path, 'invalid-app'))..createSync();
+      final java = _createFixtures(
+        tempRoot,
+        'relocated/java',
+        InteropFixtureRoots.javaFiles,
+      );
+      final missingFile = p.join(app.path, InteropFixtureRoots.appFiles.first);
+
+      _expectRootError(
+        packageRoot: Directory(p.join(tempRoot.path, 'core')),
+        environment: <String, String>{
+          InteropFixtureRoots.appRootKey: app.path,
+          InteropFixtureRoots.javaRootKey: java.path,
+        },
+        key: InteropFixtureRoots.appRootKey,
+        path: missingFile,
+      );
+    });
 
     test('rejects an empty App root with its configuration key', () {
       final java = _createFixtures(
@@ -147,32 +139,29 @@ void main() {
       );
     });
 
-    test(
-      'rejects a Java root missing a required file with its exact path',
-      () {
-        final app = _createFixtures(
-          tempRoot,
-          'relocated/app',
-          InteropFixtureRoots.appFiles,
-        );
-        final java = Directory(p.join(tempRoot.path, 'invalid-java'))
-          ..createSync();
-        final missingFile = p.join(
-          java.path,
-          InteropFixtureRoots.javaFiles.first,
-        );
-
-        _expectRootError(
-          packageRoot: Directory(p.join(tempRoot.path, 'core')),
-          environment: <String, String>{
-            InteropFixtureRoots.appRootKey: app.path,
-            InteropFixtureRoots.javaRootKey: java.path,
-          },
-          key: InteropFixtureRoots.javaRootKey,
-          path: missingFile,
-        );
-      },
-    );
+    test('rejects a Java root missing a required file with its exact path', () {
+      final app = _createFixtures(
+        tempRoot,
+        'relocated/app',
+        InteropFixtureRoots.appFiles,
+      );
+      final java = Directory(p.join(tempRoot.path, 'invalid-java'))
+        ..createSync();
+      final missingFile = p.join(
+        java.path,
+        InteropFixtureRoots.javaFiles.first,
+      );
+
+      _expectRootError(
+        packageRoot: Directory(p.join(tempRoot.path, 'core')),
+        environment: <String, String>{
+          InteropFixtureRoots.appRootKey: app.path,
+          InteropFixtureRoots.javaRootKey: java.path,
+        },
+        key: InteropFixtureRoots.javaRootKey,
+        path: missingFile,
+      );
+    });
 
     test('rejects an empty Java root with its configuration key', () {
       final app = _createFixtures(
@@ -206,11 +195,7 @@ void _expectRootError({
     ),
     throwsA(
       isA<StateError>()
-          .having(
-            (error) => error.message,
-            'message',
-            contains(key),
-          )
+          .having((error) => error.message, 'message', contains(key))
           .having(
             (error) => error.message,
             'message',
diff --git a/test/support/interop_fixture_roots.dart b/test/support/interop_fixture_roots.dart
index 1fd242e..2cf0890 100644
--- a/test/support/interop_fixture_roots.dart
+++ b/test/support/interop_fixture_roots.dart
@@ -38,9 +38,7 @@ class InteropFixtureRoots {
     }
 
     final source = File.fromUri(sourceUri);
-    final packageRoot = Directory(
-      p.dirname(p.dirname(p.dirname(source.path))),
-    );
+    final packageRoot = Directory(p.dirname(p.dirname(p.dirname(source.path))));
     if (!source.existsSync() ||
         !File(p.join(packageRoot.path, 'pubspec.yaml')).existsSync()) {
       throw StateError(
@@ -93,17 +91,13 @@ class InteropFixtureRoots {
       final source = configuredPath == null
           ? 'legacy sibling default (because $key is unset)'
           : '$key';
-      throw StateError(
-        '$source must point to an existing directory: $path',
-      );
+      throw StateError('$source must point to an existing directory: $path');
     }
 
     for (final relative in requiredFiles) {
       final fixturePath = p.join(root.path, relative);
       if (!File(fixturePath).existsSync()) {
-        throw StateError(
-          '$key is missing required fixture: $fixturePath',
-        );
+        throw StateError('$key is missing required fixture: $fixturePath');
       }
     }
     return root;
```

# Checkout-independent interop fixture contracts

## 1. Scope and trigger

`test/interop_arkts_contract_test.dart` compares shared Dart transport definitions with real App/Java ArkTS sources. The package identity is `qfli_studio_core`; its canonical checkout basename is `qflistudio-core`. These identities are intentionally different. App run 45897522770 demonstrated that deriving core source from a literal sibling basename fails during suite loading under the canonical layout.

## 2. Signatures

`test/support/interop_fixture_roots.dart` provides:

```dart
static Directory resolveCorePackageRoot();
static InteropFixtureRoots resolve({
  required Directory packageRoot,
  Map<String, String>? environment,
});
```

The result holds `Directory app` and `Directory java`. Core resolution uses `Isolate.resolvePackageUriSync` for `package:qfli_studio_core/interop/interop_protocol.dart`, checks the file URI/source/pubspec and derives its owning package root. Do not infer that root from `Directory.current` or a checkout folder name.

## 3. Environment and file contracts

| Input | When set | When absent |
| --- | --- | --- |
| `QFLI_STUDIO_APP_ROOT` | Explicit fixture directory, normalized to an absolute path | Sibling `qflistudio` beside the resolved core package |
| `QFLI_STUDIO_JAVA_ROOT` | Explicit fixture directory, normalized to an absolute path | Sibling `qfli_java` beside the resolved core package |

Relative explicit paths are relative to the process working directory; CI supplies absolute paths. Empty explicit values are invalid rather than requests for fallback. The optional `environment` parameter isolates resolver tests from runner environment state.

Required App fixtures under `ohos/entry/src/main/` are `ets/interop/StudioInterop.ets`, `module.json5` and `resources/base/element/string.json`. Required Java fixtures under the same prefix are `ets/interop/InteropReceiver.ets` and `module.json5`. Core transport is read under the resolved package root at `lib/interop/interop_transport.dart`. All existing contract assertions remain active.

## 4. Validation and errors

| Condition | Required outcome |
| --- | --- |
| Package URI is null or non-file | `StateError` naming the unresolved package URI |
| Resolved core source/pubspec is missing | `StateError` naming the resolved source path |
| Explicit root is empty/whitespace | `StateError` naming the environment key |
| Root directory is absent | `StateError` naming the key/default selection and absolute path |
| Required fixture file is absent | `StateError` naming the key and exact missing file |

Missing inputs never skip a contract test or silently select another checkout.

## 5. Good, baseline and bad cases

- Good: canonical core checkout with explicit App and Java fixtures under independent directories.
- Baseline: legacy core alias with `qflistudio`/`qfli_java` siblings and unset root keys.
- Bad: a configured directory exists but points to its nested `ohos/entry/src/main` rather than the repository root; validation must report the missing full fixture path.

## 6. Required hosted checks

Run resolver negative cases and the real contract assertions on GitHub-hosted runners. The positive canonical, legacy and relocated layouts use identical immutable core/App/Java/SDK inputs and run the complete suite. Missing/invalid root cases must assert failure plus the key/path, without accepting unrelated compile or setup errors. Preserve the independent screenshots job. Source format/analyze/tests must never execute in local editing clones.

Register all resolver unit cases unconditionally. The cloud-only policy governs where commands run; it must not silently remove negative assertions from a consumer's complete suite. Retain per-layout input identities, analyze/test output and intentional failure diagnostics as cloud artifacts.

Migration changes need their own successful candidate run. A passing older SHA or temporary compatibility symlink cannot satisfy the source portability gate.

## 7. Wrong and correct

Wrong: `Directory.current.parent/qfli_studio_core/lib/...` assumes both the working directory and checkout basename.

Correct: resolve the package URI for the core source, then resolve external fixtures through validated explicit root keys or the documented legacy defaults. Keep the Dart package name unchanged when moving the checkout.

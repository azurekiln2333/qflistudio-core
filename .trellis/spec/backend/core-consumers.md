# Shared-core consumer dependency contract

## 1. Scope and trigger

Apply when a product checks out or pins this shared package. The repository folder is `qflistudio-core`; the Dart package identity remains `qfli_studio_core`. Moving folders does not rename imports. Both vendored dependencies are part of the tested source contract.

## 2. Manifest contract

Consumer applications beside core declare:

```yaml
dependencies:
  qfli_studio_core:
    path: ../qflistudio-core
dependency_overrides:
  re_editor:
    path: ../qflistudio-core/vendor/re_editor
  xterm:
    path: ../qflistudio-core/vendor/xterm
```

Core's own overrides use `vendor/re_editor` and `vendor/xterm`. A consuming package must declare its overrides: pub ignores overrides declared inside dependencies. Official reference: `https://dart.dev/tools/pub/dependencies#dependency-overrides` (reviewed 2026-11-27).

## 3. Immutable inputs

Pin core to a full accepted GitHub commit and check it out at the expected sibling path. The repository at that commit includes both vendor source trees; no separate vendor download or CloudTerminal checkout is needed. Any runner compatibility patch is separately owned, pinned and reported by the product.

The provisional tested baseline is `476a30acee21dc486ee2849dd8064a7be665e4d5`, with Flutter OHOS `3.41.10-ohos-1.0.1` at `adaf911c35c9136a7d18fc424d714c9ec7724e60`. This documents baseline inputs, not a final migration acceptance. See migration cloud evidence for the accepted candidate. No Rust-specific tooling override is implied.

## 4. Validation and error matrix

| Condition | Required response |
| --- | --- |
| Core path missing | Fail checkout/manifest validation with the expected sibling path. |
| Vendor override absent or resolves to hosted source | Fail the consumer dependency contract before claiming compatibility. |
| Core name/import renamed to `qflistudio-core` | Reject the package rename; only folder spelling changes. |
| Compiler error in a core dependency | Inspect the executed SDK and resolved package roots before modifying core to fit an unintended package version. |

Example: SQL run `45958672684`, job `140371148749`, at `2bec36ea0c577ca02c6ce24acb99cd24b4815935` reported a `num` to `int` failure at core `herdr.dart:908`. That consumer's published manifest omitted the xterm override. Core's vendored `UnicodeV11.wcwidth` returns `int`. The missing override is a concrete input mismatch; successful consumer rerun is required before closing the diagnosis.

The owner-retrieved compiler log also names hosted `xterm-4.0.0`, missing `UnicodeV11`, and an unhandled `TargetPlatform.ohos` switch. SQL's declared Flutter input was `3.41.9+ohos-1.0.2` at `62357a93d653bf844f730bb1f4b7cc9e2139d14e`; those log excerpts did not independently print the executed SDK revision. Keep declared and executed SDK evidence distinct. This diagnosis does not validate that alternate SDK against core.

## 5. Good, baseline and bad cases

- Good: canonical sibling layout with both vendor overrides and exact core/SDK identities recorded by hosted CI.
- Baseline: a legacy checkout alias is valid only when all three relative paths and its workflow agree.
- Bad: copy only the re_editor override, resolve hosted xterm and cast core values to conceal the mismatch.

## 6. Required hosted evidence

After cloud package resolution, verify `package_config.json` maps `qfli_studio_core`, `re_editor` and `xterm` to the expected checkout and vendor directories. Record any lockfile changes and run the complete consumer suite. Core's own passing suite does not prove that a consumer selected these sources. Never run dependency resolution or tests in local editing clones.

## 7. Wrong and correct

Wrong: assume a path dependency inherits its package's `dependency_overrides`.

Correct: make both required overrides explicit in each consumer manifest and inspect resolved paths on the hosted runner.

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

Core directly declares `xterm` as the relative path `vendor/xterm`. That direct dependency carries the bundled implementation into path-consuming applications. The explicit consumer xterm override above remains supported but is optional; if present it must select the same checkout's vendor tree. Core retains its own xterm override to preserve its existing lock resolution. The re_editor consumer override remains required. Pub ignores overrides declared inside dependencies; a root consumer override can supersede a direct dependency. Official reference: `https://dart.dev/tools/pub/dependencies#dependency-overrides` (reviewed 2026-11-27).

## 3. Immutable inputs

Pin core to a full accepted GitHub commit and check it out at the expected sibling path. The repository at that commit includes both vendor source trees; no separate vendor download or CloudTerminal checkout is needed. Record runner compatibility preparation separately from the checkout SHA.

The provisional tested baseline is `476a30acee21dc486ee2849dd8064a7be665e4d5`, with Flutter OHOS `3.41.10-ohos-1.0.1` at `adaf911c35c9136a7d18fc424d714c9ec7724e60`. This documents baseline inputs, not a final migration acceptance. See migration cloud evidence for the accepted candidate. No Rust-specific tooling override is implied.

## 4. Validation and error matrix

| Condition | Required response |
| --- | --- |
| Core path missing | Fail checkout/manifest validation with the expected sibling path. |
| re_editor override absent, or either vendor resolves to hosted/another source | Fail the consumer dependency contract before claiming compatibility. |
| No consumer xterm override | Accept only when direct core dependency resolves to this checkout's `vendor/xterm`. |
| Core name/import renamed to `qflistudio-core` | Reject the package rename; only folder spelling changes. |
| Compiler error in a core dependency | Inspect the executed SDK and resolved package roots before modifying core to fit an unintended package version. |

Historical example: SQL run `45958672684`, job `140371148749`, at `2bec36ea0c577ca02c6ce24acb99cd24b4815935` reported a `num` to `int` failure at core `herdr.dart:908`. Baseline core `476a30a` still declared hosted xterm and relied on a root override; that consumer omitted it. Core's vendored `UnicodeV11.wcwidth` returns `int`. The direct path repair removes that omission hazard; successful consumer rerun is required before closing the diagnosis. Do not add casts to conceal selection of hosted xterm.

The owner-retrieved compiler log also names hosted `xterm-4.0.0`, missing `UnicodeV11`, and an unhandled `TargetPlatform.ohos` switch. SQL's declared Flutter input was `3.41.9+ohos-1.0.2` at `62357a93d653bf844f730bb1f4b7cc9e2139d14e`; those log excerpts did not independently print the executed SDK revision. Keep declared and executed SDK evidence distinct. This diagnosis does not validate that alternate SDK against core.

## 5. Good, baseline and bad cases

- Good: canonical sibling layout, required re_editor override, bundled xterm selected directly or by the matching optional override, and exact core/SDK identities recorded by hosted CI.
- Baseline: a legacy checkout alias is valid only when all three relative paths and its workflow agree.
- Bad: copy only the re_editor override, resolve hosted xterm and cast core values to conceal the mismatch.

## 6. Required hosted evidence

After cloud package resolution, verify `package_config.json` maps `qfli_studio_core`, `re_editor` and `xterm` to the expected checkout and vendor directories. Record any lockfile changes and run the complete consumer suite. Core's own passing suite does not prove that a consumer selected these sources. Never run dependency resolution or tests in local editing clones.

## 7. Wrong and correct

Wrong: assume a path dependency inherits its package's `dependency_overrides`.

Correct: declare the required re_editor override, retain the direct bundled xterm dependency, and inspect both resolved paths on the hosted runner. Any root xterm override must agree with core's checkout.

## 8. Official Flutter and OHOS preparation boundary

Run the following in a GitHub-hosted runner checkout before consumer analysis,
tests or compilation. The consumer owner supplies the selected flavor and exact
SDK revision; a CORE_REF bump alone does not execute this step.

```sh
python3 -B ../qflistudio-core/tool/ci/prepare_flutter_core.py \
  --flavor official --sdk-root "$FLUTTER_ROOT" \
  --sdk-revision "$FLUTTER_REVISION"
```

The script defaults `--core-root` to its own checkout. Optional `--app-root`
adds that application's `lib` to the fork-only symbol scan. Use `--flavor ohos`
for the OHOS fork. It requires `GITHUB_ACTIONS=true` and
`RUNNER_ENVIRONMENT=github-hosted`, verifies exact SDK Git HEAD, rejects modified
Flutter library sources, and checks the SDK's OHOS enum/view presence against
the declared flavor.

Official mode replaces only the reviewed Huawei login view in the runner copy
with an inert widget preserving its constructor, agreement field and callback
API. Its original normalized SHA-256 is fixed in the script; recognized-stub
repetition is idempotent. OHOS mode requires the original native implementation
and preserves its bytes, channels and behavior. Missing roots, SDK mismatch,
unreviewed source drift or fork-only names outside the approved file fail before
mutation. Do not reuse an official-prepared checkout for OHOS compilation.

The narrow `core-consumer-check` workflow exercises the script's failure cases
and compiles a consumer with no xterm override on official Flutter `3.50.1`
(`ae9b586f34a8443573f82ef57c3bf914a908cbf7`) and OHOS Flutter
`3.41.10-ohos-1.0.1` (`adaf911c35c9136a7d18fc424d714c9ec7724e60`). It checks
resolved package roots, Unicode widths and Huawei API/non-OHOS inert behavior.
These are candidate inputs awaiting hosted execution, not a device-login,
native packaging, hooks-runner override or universal SDK compatibility claim.
The full core suite and path matrix continue on the pinned OHOS SDK.

Wrong: hide an undefined `OhosView` behind a runtime platform check and assume
official Flutter can compile it. Correct: explicitly prepare the approved runner
copy and keep the original native file for the OHOS job.

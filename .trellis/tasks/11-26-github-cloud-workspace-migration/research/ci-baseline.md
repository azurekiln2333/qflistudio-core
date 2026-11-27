# Cloud CI planning evidence: 2026-11-26

Source: read-only Pi w63:p4 audit through GitHub workflow blobs and API run/job/artifact metadata, reported through Herdr. No artifact downloads or local builds/tests. These are existing baseline results, not final migration acceptance; refresh after wsui handoff and final integration.

## Core

- Successful main run 45379383816 at ee83f1c0d72708547d0692e6cd05498d3539ce02: check job including dependency resolution, formatting, analysis and full tests passed; verification artifact reported unexpired.
- Historical main failure 45031879854 at efa49c15e0640ba9fd3c36dab15acadf8689955d (2026-11-22): complete test suite failed. Do not misreport it as the latest result.
- Active wsui branch success 45656065902 at 476a30acee21dc486ee2849dd8064a7be665e4d5: check and screenshots passed; artifacts unexpired. Earlier runs 45649150338, 45628047632 and 45611396233 failed. Final wsui/main SHA is pending owner handoff.
- core-check uses Ubuntu and pinned OHOS Flutter, pinned app/Java repositories and verification logs. It is not itself a product installer workflow.

## Existing product baseline

qflistudio-next App installers run 45381816968 passed on v5.0.13, commit 7104c64ef545ca006533140794729c2f2f40795f. Artifact metadata was reported unexpired with expiry around 2026-12-08. This does not cover every language product or the future migration SHA.

| Platform | Successful existing app outputs | Limits requiring explicit acceptance evidence |
| --- | --- | --- |
| Windows | x64 and arm64 installer jobs/artifacts | Workflow packaging success, not physical-device installation; assistant output is separate |
| Linux | x64 and arm64 package jobs/artifacts | App-owned outputs; no separate cpp input identified for these jobs |
| macOS | x86_64 and arm64 DMG jobs/artifacts | Ad-hoc signing, no notarization |
| iOS | arm64 IPA and Git iOS integration diagnostics | IPA unsigned; cpp and Git framework jobs do not establish signed installation |
| Android | x86_64, armeabi-v7a and arm64-v8a APK artifacts | APKs use debug signing; not store signing. ABI/ELF/plugin provenance inspections present |
| OHOS | arm64 HAP artifact/job | HAP unsigned; native/resource outputs do not establish signed installation |

qflistudio-cpp installer run 45645017677 separately has successful Windows x64, Linux x64, macOS universal, Android, iOS and OHOS jobs. That distinct product currently pins core cbaa4a41... and needs owner coordination. cpp native workflow includes Android and OHOS outputs and iOS slices/XCFramework; qflistudio-git workflow covers Android ABIs, OHOS ABIs and iOS device/simulator frameworks. Exact immutable native inputs and complete per-product intermediate retention still require the execution audit.

## Direct path/patch contract

qflistudio-next .github/actions/app-setup/action.yml checks out core into qfli_studio_core. app-installers.yml uses inputs.core_ref or env.CORE_REF at nine call sites; current observed pin is ee83f1c0d72708547d0692e6cd05498d3539ce02. App-owned tool/ci/patch_upstream_core.sh adapts the runner checkout for upstream Flutter by replacing an OHOS-only view and checking for remaining fork-only APIs. OHOS Flutter jobs disable this patch. This is not a universally required core-owned script or automatic Rust requirement.

## Execution implications

Wait for active UI owner handoff before final pins. Preserve runner aliases unless all consuming paths migrate together. Coordinate final core pin and SDK adaptation with app/native owners. Signing credentials and unavailable platform owners are real delivery dependencies; never count unsigned IPA/HAP as complete signed installation workflows. Retention and reusable native/Flutter intermediates need explicit coverage, not inference from a successful final artifact.

## Handoff update

Core main writer handoff has now arrived at 476a30acee21dc486ee2849dd8064a7be665e4d5. The source coordinator independently verified live GitHub/CNB main and successful run 45656065902 with both check and screenshots jobs. The original run head_branch is wsui/integration; its exact SHA matches new main. A separate rewritten wsui/integration now points to 0defbf39d1ef35e4eae43717e1a910da0f9cfbe5 and has owner-reported failing CI; that follow-up is not covered by the 476a30a success. App v5.0.14 release is owner-reported running, so no new release success is claimed.

## Immutable SDK and consumer contract, 2026-11-27 continuation

Direct inspection of core-check.yml at 476a30acee21dc486ee2849dd8064a7be665e4d5 confirms FLUTTER_OHOS_TAG=3.41.10-ohos-1.0.1, FLUTTER_OHOS_REVISION=adaf911c35c9136a7d18fc424d714c9ec7724e60, APP_REF=69656b4ab14e706e85907ef4c4205d8cd35a1338 and JAVA_REF=60d97c783f29da767fafe503980812101f6aa61f. Ubuntu checks use aliases qfli_studio_core/qflistudio/qfli_java and the pinned app setup_flutter.sh. Core pubspec requires Dart ^3.11.5. This is analysis/test/screenshot evidence, not six-platform app packaging or native payload certification.

At app c5f4bc3afe9c81ba488fd3f544d43c3dac061512, previously inspected installer inputs were official Flutter 3.50.0, the same OHOS tag/revision, OHOS tools 26.0.0.821/API 26, Node 24.14.1, Android NDK 27.0.12077973 and CMake 3.22.1. The workflow has no workflow_call and is not a generic reusable six-platform installer. Treat these as immutable source configuration evidence; do not infer successful consumer builds from them. App owns the official-Flutter adaptation script and exact patch/checkout compatibility.

Rust's later candidate flutter-oh-3.41.9+ohos-1.0.2 differs from the checked core SDK. No matching core cloud evidence has been established, so it is neither approved nor declared incompatible. Rust can perform independent native/source checks while final core and application SDK integration remain gated. Consumers retaining 476a30a have only a provisional baseline; no final migration SHA or universal official-Flutter 3.50 compatibility claim has been issued.

Pi w63:p4 subsequently identified main run 45689025146 at exact core 476a30acee21dc486ee2849dd8064a7be665e4d5. The coordinator directly rechecked its API metadata and jobs: completed/success, check and screenshots successful, both pinned-SDK install steps successful. This is additional baseline evidence, not a newly published migration commit.

The pinned app setup script at 69656b4ab14e706e85907ef4c4205d8cd35a1338 has blob 05cb24cc4f0ecc3cbefbf9fe6f8a8e917ac14a05. Pi source inspection confirms --ohos selects https://gitcode.com/openharmony-tpc/flutter_flutter.git, shallow-clones the tag and enforces exact HEAD equality. Neither this script nor the core workflow has visible code_assets/hooks_runner/flutter_tools package overrides. The fork's internal package configuration was not independently validated. There is no approved Rust-specific tooling override recipe, and the old 9d2eaf recipe must not be inherited as validated. Exact evidence and this limitation were sent to Rust w61:p1 and w61:p3 through Herdr.

App w65:p1 also reports no such overrides in its c5f4bc3 setup/patch scripts, and reports successful app run 45689238802. That app run is owner-reported here and does not validate Rust native hooks. The app-owned official-Flutter patch at c5f4bc3 replaces huawei_quick_login_view.dart with an inert SizedBox.shrink implementation retaining its API, then rejects remaining TargetPlatform.ohos/OhosView usage across app/core/vendor re_editor. This changes Huawei-login behavior and must not be copied as a generic Rust compatibility template. OHOS jobs disable that patch; core-check does not execute official Flutter 3.50 or build HarmonyOS packages.

## Web failure ownership audit

Web w64:p1 reported run 45858109136 on its commit 1a05b081 and core 476a30a, with 293 tests passing, six skipped and 17 failing across startup, catalog, saved workspaces, tools, offline browser and server lifecycle. Pi w63:p4 independently verified that source/workflow/artifact checks and Linux setup/analyze passed and Flutter unit tests failed. Failure counts and the core pin were supplied context; the inspected endpoints did not expose stack paths establishing core attribution.

Published core retains HomePage, HomeTab and the Flutter Material NavigationBar instantiation. One concrete behavior hypothesis is the form-factor split: QfliApp selects HomePage for phone, LargeScreenWorkbench for tablet/desktop; HomePage only builds bottom NavigationBar below width 900. A wide/non-phone test may therefore miss expected widgets without an API removal. This does not explain all 17 failures or absolve core of runtime regressions. Failure names, first exception/stack, viewport/form factor, selected route, offline profile and socket contract are needed to assign ownership. No future core migration SHA is promised as their fix, and no local tests or Web edits were performed.

## Confirmed canonical-checkout test defect

App w65:p1 reports run 45897522770 at app76e1f80 with core476a30a: six-platform package jobs pass, but core unit-suite loading fails in test/interop_arkts_contract_test.dart:21/77. Source coordinator directly read that test from exact core476a30a: root is Directory.current.parent; the reader joins root/app/relative, throws if absent, and group initialization reads qfli_studio_core/lib/interop/interop_transport.dart. Canonical qflistudio-core checkout breaks this assumption before assertions. Other required fixtures use qflistudio and qfli_java aliases. This is a confirmed core-owned portability defect, unlike the unresolved Web runtime clusters above.

No permanent fix has been published. The cloud-policy child now requires folder-independent own-package resolution, explicit required sibling fixture roots and hosted canonical/legacy layout coverage. App owner is recording a narrow CI-only legacy-path adaptation with its existing immutable pin and all assertions retained. Any passing adapted run is evidence for the adapted runner layout, not proof that the unmodified pinned test supports canonical names. No local source/sibling mutation or test skipping was requested. App's separate fromCharCodes UTF-8 test-decoder issue remains app-owned. The subsequent bounded metadata review below verifies job conclusions but does not independently identify either failure's stack trace.

## App packaging progress, not final acceptance

Pi w63:p4 reviewed GitHub run/job/step metadata for qflistudio-next App installers run 45897522770. Push on main, full app HEAD 76e1f80ab2df6c3b1f7ae62a2648f3c52683ad11; overall completed/failure, 2026-11-26 21:21:04 to 21:44:23 UTC. No artifacts or logs downloaded.

Package jobs passed for Windows x64/arm64 installers, Linux x64/arm64 packages, macOS x86_64/arm64 DMGs, iOS unsigned IPA, Android release APKs and OHOS unsigned HAP. Associated build/inspect/package/upload steps show success. GitHub-hosted execution guard, Flutter version resolution, pinned Java receiver, Windows/Linux Node companion, Windows assistant packaging and Studio Git iOS integration also passed.

Both Verify core with OHOS Flutter and Verify app with OHOS Flutter failed their full-suite test step after successful setup/resolution/analyze; reporting/upload succeeded and App helper tests passed. Publish verified release or preview was skipped. Therefore this is six-platform package-job progress, not a green end-to-end workflow or published release. Metadata alone does not verify artifact retention/content, final signing/installation or real-device behavior. Core's hardcoded path defect is independently supported by the source inspection above; its exact occurrence in this run and the App UTF-8 explanation are owner-reported.

## App verification recovery and pending final documentation commit

App w65:p1 later reported fixes and published documentation/progress commit b052d77aa64d11c2baab686ffefadbe9f3a33156. The core coordinator directly queried GitHub: run 45908020703 is completed/success at full app SHA da74782075d4bb31f92546c18031c340df1adb21. All 18 verification/package jobs passed, including both App/Core verification and all six platform families; the nineteenth job, Publish verified release or preview, was skipped. This supersedes the earlier failed App verification as evidence for this tested App commit, without establishing release publication or signed/device-tested installation.

The final documentation SHA has its own workflow_dispatch run 45912697544. Direct API inspection confirmed its head is b052d77aa64d11c2baab686ffefadbe9f3a33156 and status is in_progress with no conclusion at that snapshot. Do not transfer the earlier run's terminal success to this different SHA. App owner will wait for its terminal result before target w6D handover.

Owner-reported details not independently audited here: seven docs/spec files differ from tested da74782; App 24 and Core 3326 tests pass with 27 Core skips; core476a30a/plugin697291a remain pinned; the runner fixture symlink is explicitly documented; 1703 source/target tracked files match by bytes and both App workspaces are clean with GitHub-only target. No sibling checkout was inspected to establish those claims. The temporary fixture symlink does not fix the core source's directory assumption. Permanent core portability correction, final migration pin and new immutable native contract remain outstanding. WSL is unchanged.

## Canonical-folder CI/path audit, 2026-11-27

Read-only audit supplied by w63:p5 and cross-checked against the published core test at `476a30acee21dc486ee2849dd8064a7be665e4d5`; no source edit, task start, build/test, dependency install, artifact download, fetch, ref mutation, cleanup or push occurred during that audit. The test uses `Directory.current.parent` and joins the literal sibling name `qfli_studio_core` to read `lib/interop/interop_transport.dart` (source lines 16, 18-21, 77-79). Under canonical folder `qflistudio-core`, the contract suite fails during loading. App run 45897522770's core job/check 140175027362 reported the missing source with stack locations at test lines 21:7 and 77:23.

The required fixtures are concrete: App `ohos/entry/src/main/{ets/interop/StudioInterop.ets,module.json5,resources/base/element/string.json}`; Java `ohos/entry/src/main/{ets/interop/InteropReceiver.ets,module.json5}`; and the core transport source. Existing core cloud run 45689025146 at exact `476a30a` passed both Ubuntu 24.04 `check` and `screenshots` jobs using OHOS Flutter `3.41.10-ohos-1.0.1` revision `adaf911c35c9136a7d18fc424d714c9ec7724e60`, app fixture ref `69656b4ab14e706e85907ef4c4205d8cd35a1338`, and Java fixture ref `60d97c783f29da767fafe503980812101f6aa61f`; the workflow used legacy checkout aliases `qfli_studio_core`, `qflistudio`, and `qfli_java`. This is baseline validation and not proof the canonical path works.

App run 45912697544 at `b052d77aa64d11c2baab686ffefadbe9f3a33156` is now completed/success (19 artifacts reported unexpired through 2026-12-10); publication was skipped. App run 45908020703 at `da74782075d4bb31f92546c18031c340df1adb21` passed its 18 verification/package jobs, but is a different commit. App owner reports its core job passed with a temporary `qfli_studio_core -> qflistudio-core` fixture symlink; this is adapted-runner evidence, not an unmodified canonical-folder pass. No permanent core fix or post-fix hosted matrix exists. The App UTF-8 decoder failure is separately App-owned. This supersedes the earlier in-progress snapshot for run 45912697544.

Planning proposal: derive the core source file by Dart package identity, accept explicit validated App/Java fixture roots with documented `qflistudio`/`qfli_java` sibling defaults, preserve every assertion, and fail with the exact missing path plus configuration key. Before accepting a core fix, run GitHub-hosted checks with identical immutable refs for canonical core checkout, legacy checkout alias, relocated explicit fixture roots, and negative absent/invalid roots. No symlink or skipped assertion can satisfy portability coverage. No final migration SHA exists; `476a30a` remains the provisional tested baseline.

Fresh live status check on 2026-11-27 used `git ls-remote` (no fetch) and GitHub CLI run metadata: `main` still advertises `476a30acee21dc486ee2849dd8064a7be665e4d5`; the latest listed main `core-check` is run `45689025146`, completed/success on that exact SHA, updated 2026-11-25T19:58:10Z. No newer core main commit or core-check result was found by this check.

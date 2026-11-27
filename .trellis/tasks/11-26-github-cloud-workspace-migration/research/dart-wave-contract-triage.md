# Dart consumer wave: bounded compatibility triage

Frozen 2026-11-28. Source review only; no local checks, Git mutation, sibling checkout inspection, or production/test edits. This report does not hold the separately reviewed migration repair commit. The coordinator and brain own compatibility decisions and any subsequent consumer changes.

## Evidence and conclusion

The eight reported Dart test failures map to four Core behavior surfaces. All six relevant files are blob-identical between published baseline `476a30acee21dc486ee2849dd8064a7be665e4d5` and migration candidate `1ae4674a4b153701b0c3b3ff04b1a1b77a318611`:

| Core file | Identical blob at both revisions |
| --- | --- |
| `lib/services/project_templates.dart` | `8dd8317e5dd552a06ab9fada0e8e4daf361829a5` |
| `lib/pages/home_page.dart` | `f3325932dffeadac9877b2a4b800c869ef941941` |
| `lib/editor/editor_page.dart` | `0456d5cd5434e78c7680b56fe88b2e0329a2234b` |
| `lib/editor/editor_quick_bar.dart` | `19cde7e195e4ee5faba42790b09f163ecb1560b9` |
| `lib/app.dart` | `ae7153cbc92af13fa43181e1e3fbbcb85fb0caa7` |
| `lib/layout/app_form_factor.dart` | `026e08113816f05c9509a6f2ae9a3767ff6a9130` |

The bounded `lib/` comparison contains only the result/reset `OverflowBar` change in `local_content_pages.dart`; it does not change these four surfaces. This establishes source equality, not equivalent execution under every consumer setup.

An independent public GitHub compare of Dart app `51c43c210cdef0821fb0242d20e73825f4ea40f2` to `2d3d12ea055397c2040bd553687f2ad6ff7b5a1d` returned exactly three changed files: `.github/workflows/apple-build.yml`, `.github/workflows/application-build.yml`, and `.github/workflows/ohos-build.yml`. Their prior Core pin was **`573d1b6eecf1c2b392ad753264a5a09f62f8335e`**, not `476a30a`; the new pin is `1ae4674a4b153701b0c3b3ff04b1a1b77a318611`. The official preparation entry point also changed from app-owned `tool/ci/prepare_core.py` to Core `prepare_flutter_core.py`. The configured official SDK remains Flutter 3.41.9 at `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`.

Accordingly, these newly surfaced expectations cross the older `573d1b6` to already-published `476a30a` behavior boundary. They are not evidence that this migration series newly changed the listed surfaces. This does not waive Core's coordinated compatibility responsibility under the brain ruling.

## Hosted evidence boundary

The consumer owner report is `D:/MyNewProjects/_orchestra/status/qflistudio-dart.core-wave-linux-triage.md`.

| Owner-reported run | Immutable inputs | Reported result |
| --- | --- | --- |
| `45957413004`, attempt 1, Linux job `140366997352` | Dart `51c43c210cdef0821fb0242d20e73825f4ea40f2`; Core `573d1b6eecf1c2b392ad753264a5a09f62f8335e` with former stock-Flutter preparation | 221 passed, 3 skipped |
| `46047966319`, attempt 3, Linux job `140680655612` | Dart `2d3d12ea055397c2040bd553687f2ad6ff7b5a1d`; Core `1ae4674a4b153701b0c3b3ff04b1a1b77a318611` | Analyze passed; 213 passed, 8 failed, 3 skipped; official preparation and vendored xterm resolution succeeded |

This lane independently checked source blobs and the public workflow comparison. It did not independently re-fetch these run logs or execute the consumer suite. Execution results and assertion locations above and below remain attributed to the owner report.

## Finite compatibility decisions

### Template greeting: one failure

`test/dart_app_test.dart:111` expects `Hello, QFLIStudio+!`, while the current template produces `Hello, QFLIStudioN!` at `project_templates.dart:216`. The bounded `573d1b6..476a30a` source diff shows this branding change across language templates, not only Dart.

Decision needed: affirm the current generated-output branding contract, or explicitly retain a legacy consumer contract. Neither a broad template rollback nor a weaker execution assertion follows mechanically from this evidence. Preserve template creation and execution coverage, with the expected exact output governed by the approved contract.

### Home navigation/profile: five failures

`test/dart_offline_test.dart:133` expects five tappable rail entries but receives four. These tests mount `HomePage` directly at 1000px; they are not testing the workbench rail. Current Home merges the former examples destination into content, explicitly documented near `home_page.dart:184-185`; the relevant destination construction is at `:111-114`, `:168-195`, and `:203-218`. Offline content routes to `TutorialCenterPage` at `:268-277`, and profile is now index 3 rather than 4 at `:279`.

Decision options: explicitly preserve legacy consumer navigation, or coordinate migration to the current named destinations/content surface. Preserve every offline/login/AI/network policy assertion. Changing only the expected count would leave incorrect destination assumptions and is not a sufficient repair. The reported failures occur at the navigation precondition, before the later policy assertions.

### Editor Settings affordance: one failure

`test/dart_offline_test.dart:315` opens the first `Icons.more_vert` and expects visible text `设置`. Earlier Git/cloud-absence assertions passed. The older editor had an unconditional popup Settings action; the current popup adds quick actions only when `_largeScreen == null`, focus mode is off, and `_quickBarFits(context)` is false (`editor_page.dart:4121-4123`). At the reported 1100x900 test size, the quick bar fits. Settings still exists as an icon/tooltip action in `editor_quick_bar.dart:443-447`, rendered through `:114-147`. `_openSettings` at `editor_page.dart:2516-2524` retains the offline AI visibility gate.

Decision options: explicitly retain the Settings overflow-menu affordance, or coordinate consumer interaction with the existing quick-bar/tooltip affordance. Preserve Settings navigation and all offline gating assertions. The evidence establishes an affordance expectation mismatch; it does not establish that Settings disappeared from the editor.

### Android-variant startup: one failure

`test/dart_startup_test.dart:138` expects one `HomePage` but finds none; splash and readiness assertions passed. The older app always selected HomePage. Current `QfliApp` accepts a documented device-family override for embedded products and deterministic tests. Its default `_resolveFormFactor` reads `Platform.operatingSystem` (`app.dart:115-116`); Linux resolves desktop (`app_form_factor.dart:38,63-64`), and `app.dart:230-242` selects the workbench. A Flutter `TargetPlatformVariant.android` override does not change the host operating-system string.

Decision options: use the existing explicit `AppFormFactor.phone` contract for a deterministic phone test while retaining first-frame/readiness/correct-shell assertions, or approve a separate compatibility default. Do not change global OS detection speculatively or characterize this Linux-hosted variant result as a verified Android-device startup failure.

## Coordinator contract decision

The Core coordinator accepts the current published behavior as the migration
contract: exact `Hello, QFLIStudioN!` execution output; four named Home/Tools/
Content/Profile destinations with Profile index 3 and offline TutorialCenterPage;
Settings through the fitting quick-bar tooltip action with short-layout overflow
fallback; explicit `QfliApp(formFactor: AppFormFactor.phone)` for deterministic
phone tests, while actual Linux defaults to desktop/workbench. The executable
consumer contract is recorded in `.trellis/spec/backend/core-consumers.md` section 9.

Consumer owners may migrate the affected selectors and exact expected template
output to these contracts. They must preserve every offline/network/login/AI/Git
absence assertion, real template execution/output proof, first-frame/readiness
and correct-shell assertion. Changing a count alone or deleting later assertions
is not sufficient. No Core rollback or consumer repin is authorized by this
decision; exact-SHA hosted validation remains required.

## Disposition

No mechanical source repair is justified within this bounded review. The coordinator decision above resolves the finite branding, navigation, affordance and form-factor contract; consumer implementation and hosted acceptance remain with that owner. No assertions, fixtures, production source, or workflow files were changed by this triage. No skip, tolerance, golden relaxation, or assertion removal is recommended.

Lint, type checking, and tests were not run locally under the repository cloud-only policy. Any chosen implementation requires its own exact-SHA GitHub-hosted evidence. This frozen report is static triage, not validation or final consumer acceptance.

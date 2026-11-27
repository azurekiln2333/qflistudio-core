# Ignored source and checkpoint disposition

The independent `ignored-source/manifest.json` under the migration backup records 3,185 source/configuration candidates (40,675,200 bytes), with original SHA-256 and normalized Git blob identities. This is a bounded authored-file inventory, not a backup claim for every generated file under `build/`. No helper, checkpoint, product test or SDK was executed.

## Published and intermediate source

A read-only comparison with all objects reachable from published core `476a30acee21dc486ee2849dd8064a7be665e4d5` found:

| Category | Files | Disposition |
| --- | ---: | --- |
| Build/checkpoint source whose normalized blob is in published history | 2,911 | Already recoverable from GitHub history; do not commit duplicate build snapshots. |
| Build/checkpoint source present only as local Git objects | 18 | Intermediate tree variants described below; retain exact external copy, do not replay over integrated safety fixes. |
| Other build source/helper candidates without an exact local Git blob | 55 | 39 historical JSON fixture sources owned by JSON; 16 temporary core publication/integration helpers and source-review inputs. Retain externally, not current tooling. |
| Alternative agent integrations | 201 | 46 `.agent`, 52 `.claude`, 52 `.codebuddy`, 51 `.cursor` source/template candidates. Preserve externally; portable Codex/Pi and shared skills are separately reviewed/versioned by the context owner. These alternative-platform snapshots do not contain additional product tasks or source features. |

The 18 nonpublic checkpoint files come from tree objects, not commits: prefixes `0667c4ec8462`, `976845f6668f`, `9b4145b37ff2`, `17d0dd02e01f`, and `f0beb77e81b8`. No commit in the inspected refs/reflogs has one of those trees. Do not present those prefixes as released revisions.

The first three trees differ in 3, 2 and 9 selected paths from the published editor/workspace integration commit `36697b04836a9dc6178f96071eca010f1685218c` (tree `f6913564b96692619c4c56e45d16b39ddb4d59b8`). They are pre-integration/review variants of the debugger spec, saved-workspace spec, editor page/explorer/retained host, workspace dialogs and four tests. The read-only diffs show missing queued-save membership protection, old tab-index closure, missing external-project navigation/dialog guidance and earlier test formatting/coverage. They are recovery evidence, not proposed missing features. The integrated published source is the accepted source of these contracts.

The last two trees each contain two earlier test variants relative to published workspace commit `2f9039a3ba95449679b17257b0313c1ee3644a2c` (tree `d21ffcdc7ac9c834e0b788b21178e9f80768a519`): `test/saved_workspace_capability_test.dart` and `test/workspace_metadata_refresh_test.dart`. These variants use assertions inside asynchronous callbacks, broader tooltip lookup, older completion tracking and pre-format wrapping. The published tests retain the reviewed replacements; importing the intermediate tree would revert them.

## Temporary helper and cross-product inputs

The 16 remaining core build candidates are `c_owned_job.py`, `debug-ui-page-before.dart`, `explorer-review.diff`, `freeze-c-publication-v4.py`, `freeze-c-workspace-followup.py`, `integrate-debug-ui.py`, `prepare-c-candidate-window.py`, `prepare-c-tail-window.py`, `prepare-c-workspace-followup-window.py`, `publish-c-release.ps1`, `publish-c-workspace-followup.py`, `record-c-workspace-checkpoint.py`, `run-c-core-window.py`, `stage-c-reviewed-batch.py`, `stage-c-v4-composed.py`, and `stage-preview-compatibility.py`.

These are one-session staging/publication drivers, pre-edit source and review diffs. They are not supported project entry points. In particular, the debugger integration helper's output-buffer/debug-panel hooks and the preview helper's explicit `entryOverride` URL resolution are present in published `lib/editor/editor_page.dart`. The explorer review describes multi-root ownership/generation handling already present in the published explorer. Do not execute the old scripts: several write the Git index, create local verification trees or publish historical branches outside the migration gate. Keep their original bytes and hashes in the external backup for forensic recovery.

The 39 JSON files are 13 source/config/test paths repeated under `build/json-integration/{17d0dd02e01f,d21ffcdc7ac9,f0beb77e81b8}`. The JSON coordinator was notified through Herdr; core did not inspect or mutate the JSON repository. Their external preservation is retained pending that owner's disposition and is not grounds to delete the source directory.

## Acceptance boundary

This inventory distinguishes valid published source from generated checkpoint copies and obsolete helper recipes. It does not certify the old directory for deletion, certify alternative agent runtime configuration, or replace the separate source-WIP/branch ledgers. Original ignored files remain in place as well as in the named backup. No generated source tree, SDK, binary, cache, log, private runtime record or package is added to Git by this disposition.

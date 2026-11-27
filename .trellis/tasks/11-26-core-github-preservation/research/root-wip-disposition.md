# Root and dirty linked-worktree WIP disposition

Audit date: 2026-11-27. Worker: Herdr `w63:p5`, model `gpt-6.1-sol`.

## Decision and scope

**Do not replay the old root WIP over published main.** All 56 original root product files have exact same-path content in published ancestry. Twelve remain exact at the provisional published baseline; 38 have later versions there, and six were deliberately removed. No unpublished root implementation delta needs porting.

The five other dirty linked-worktree snapshots contain **41 original changed/untracked files**, including two dependency manifests. None of their complete file blobs was found anywhere in the ancestry of the provisional published baseline. This is bounded exact-content evidence, not proof that every behavior is new. Their useful source must receive cloneable, inactive preservation under `.trellis/tasks/11-27-core-preserved-followups/research/`; external backup alone is not their final public disposition. **Do not activate account binding, desktop companion, ProjectConfigGuard, historical CI, or diagnostic tests during migration.**

This worker writes only this report. The coordinator owns snapshots, relocation, index/refs, patch export and publication. P2 owns the branch/ignored-context ledger; this report deliberately does not duplicate it. No sibling application was inspected. No build, test, analyzer, formatter, package installation, SDK operation, artifact download, WSL operation, Git mutation or worker spawn was performed.

## Immutable evidence and method

All final WIP comparisons use this immutable preservation input, not the subsequently aligned live source tree:

- Snapshot root: `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/snapshot-20261127T062635Z`.
- Original file bytes: `worktree-NN/files/<original-repository-relative-path>`.
- Original tracked deltas: each worktree's `tracked.patch`; original statuses and base identities are in `manifest.json` and `status.z`.
- Snapshot `manifest.json` SHA-256: `2008f3da190d3821fa0de913bedc924ba91d191721c457d019b01c512356aa85`.
- Root `worktree-00/tracked.patch` SHA-256: `c0ca8bc8f2a2e8598c4bd79822a0345bc739eabfb93a183b447ab62e9ff11041`.
- All **56 root + 41 linked = 97** original file SHA-256 values were recomputed against the snapshot manifest: **zero mismatches**. Raw per-file SHA-256 values remain in that hash-anchored manifest; the rows below record Git content identities separately.

Immutable commits:

| Key | Full commit | Meaning |
| --- | --- | --- |
| B | `573d1b6eecf1c2b392ad753264a5a09f62f8335e` | Original dirty root HEAD. |
| H | `655d06b76d1b89bc93d249ff743236eb2f3fdaf4` | Historical pre-workbench WIP capture; 55 original root files match this exact same-path tree. Its message says it was a baseline, not a recipe to merge again. |
| F | `645e05162497ea38f619c5e1a5ae2bf96a6d1995` | Exact historical facade variant for the remaining root file. |
| P | `476a30acee21dc486ee2849dd8064a7be665e4d5` | Provisional published baseline supplied by the coordinator, not a final migration SHA. |
| D | `5d992361ad5ee3bc31397c7dd2c98a01048f1b2a` | Explicit removal of the obsolete project entry, project page, workbench shell/sidebar and their two tests. |

Read-only `merge-base --is-ancestor` returned 0 for B -> H, H -> P and F -> P. Same-path `ls-tree`/`rev-parse` checks establish the exact file identities, not just patch similarity. In particular:

- `F:lib/vibe_coding/vibe_agent_facade.dart` is `2b6048ee9f6055d78a1574a8e10e20f8eba1ce35`, exactly the snapshot variant.
- `log --find-object` identifies F introducing that facade blob and `451595da0825ae033858060256167b3eea1d28c0` replacing it.
- All other 55 root rows match H at the **same path**. This is stronger evidence than merely finding an object somewhere in a bundle.
- All 36 root U rows are absent from B. The 20 M rows differ from B as captured in the original tracked patch. Counts are original snapshot counts, not current live `git status`.

Git blob IDs below are computed without `-w` using `hash-object --path=<original path>` and the repository's text conversion, without writing objects. Thus **exact means Git-normalized content identity**, including normalization of CRLF/LF, not a claim that Windows working-file raw bytes equal the Git blob. Raw-byte recoverability is the independently checked SHA-256 evidence above. Initial live reads preceded the snapshot handoff; all final decisions and hash checks were repeated from the immutable snapshot.

## Root: exact 56-row ledger

M = modified tracked at B; U = untracked at B. `P blob` uses an unambiguous 12-character display of the immutable P tree entry; full original/history blobs are recorded. H/F in the provenance column means exact whole-file, same-path identity, not just the named behavior.

Disposition vocabulary:

- **Exact P**: no application needed; the entire Git-normalized file is already P.
- **Covered/later P**: exact original history exists and the original useful behavior is represented or evolved in P. Keep P, not this old file. The row names the concrete boundary.
- **Deliberately removed**: D deleted this exact historical source path; it is not missing accidental untracked work. A future desire for that UI needs a new feature decision, not restoration during migration.
- Every root row has **minimal port delta: none**. Original bytes remain in the verified backup and historical content in published ancestry.

| # | State | File | Original Git blob | Exact history | P blob | Disposition / behavioral evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | U | `lib/chat/attachment_picker.dart` | `0be9b8b986863ddbb76b45be4f1754108e1cba58` | H | `4d62a88ab0ee` | Covered/later P. Same safe project/workspace enumeration and phone sheet; P adds workbench multi-pick menu and empty-state close. No restoration of the older sheet-only whole file. |
| 2 | U | `lib/chat/chat_transcript.dart` | `b6c695d3dfdda25810e49abbab63dd30ba97cb94` | H | `00d06926d7fb` | Covered/later P. User/assistant/tool rendering, approval and retry remain; P adds typed errors, progress/activity, earlier paging, stable scroll, reasoning and file/message actions. Old unconditional tail-jump is not a missing improvement. |
| 3 | U | `lib/chat/composer_card.dart` | `83811b2ab4cee146fdb95024013097ca1fb0e1e7` | H | `db033b31ccd4` | Covered/later P. Draft, attachments, permissions, model/effort and send/stop remain. P fixes real-width layout, session-switch async races and adds context/workbench controls. Do not restore late clear/attachment callbacks lacking current-state guards. |
| 4 | U | `lib/chat/composer_draft.dart` | `4e39c13285a9e229891357c34ae17c23a2c8c2f6` | H | `d08fb7335641` | Covered/later P. Text and attachments remain; P adds `autoSend` so shared files need not send without user confirmation. |
| 5 | U | `lib/chat/composer_state.dart` | `84bbe53158acb31371925d68f33675775a173101` | H | `42aafd5b3b8c` | Covered/later P. Per-session drafts and serialized defaults remain; P captures queued-save snapshots, rejects stale project loads and adds per-model context capacity. |
| 6 | U | `lib/chat/write_approval_card.dart` | `d9fec0f60a978be5c7ca37ee66e9311b4b91bc8f` | H | `d9fec0f60a97` | Exact P. Approval allow/deny source already present. |
| 7 | M | `lib/editor/editor_page.dart` | `7dedd2810b40dab53ba653cc871315ffa60c4ce3` | H | `0456d5cd5434` | Covered/later P. Original B delta removes foreground probe, adds experimental background run and right-column panels. P retains static run routing/background terminal attachment and panel/layout scenarios; `6e30f47` replaces external `onOpenAgent` handoff with integrated `EditorAgentHost`. Whole-file replay would remove much newer editor/workspace behavior. |
| 8 | M | `lib/editor/terminal_pane.dart` | `7a31bd5b64f4775eb497f754d548e995ac67c29d` | H | `b1c9e25fb59a` | Covered/later P. Original `showLocal()` addition remains at P line 691. P additionally handles iOS sandbox ownership and OHOS runtime guide; retain those. |
| 9 | U | `lib/interop/interop_background_transport.dart` | `759968e21b6734ab6419824329cc7a75d9e93c83` | H | `2d42ddadc33d` | Covered/later P. Token-filtered streamed run, ZIP handoff, stop acknowledgement/timeouts remain. Only substantive same-path change is fork-enum detection replaced by shared `isOhosPlatform`. |
| 10 | M | `lib/interop/interop_protocol.dart` | `56001d18e5ba40aba3922d8e6e4bf17ed8fdb68f` | H | `56001d18e5ba` | Exact P. Original B additions serialize, decode and validate per-run `sessionToken`. |
| 11 | M | `lib/interop/interop_run_dialog.dart` | `6b946879c01ce1a1531a6de596c600a036cf521b` | H | `c4f2e42f39ce` | Covered/later P. Original bounded start timeout and InteropException UI remain. P adds `InteropRunOutcome` and immediate missing-app return for caller fallback; old `int?` API would regress it. |
| 12 | M | `lib/interop/interop_runner.dart` | `3a57d7355508e86cb0458d29ab7bd3359a42305a` | H | `c6ba12a2e518` | Covered/later P. Secure random token, foreground closing output versus background diagnostic, confirmed-stop outcome remain. P additionally preserves `appMissing` in failed runs. |
| 13 | M | `lib/interop/interop_transport.dart` | `e61ef5b261a710d9c6b0fbdaafbb1417cbf9407e` | H | `84f9209b53a4` | Covered/later P. ZIP URI payload, integer wire normalization, unknown probe error and `InteropStop` remain. P replaces direct `TargetPlatform.ohos` use with portable helper; never bring the fork-only enum back. |
| 14 | U | `lib/interop/interop_zip.dart` | `1184bc70cf4303146155314b781875ffe793ca8a` | H | `1184bc70cf43` | Exact P. Payload ZIP implementation already present. |
| 15 | U | `lib/layout/breakpoints.dart` | `707806be7f0121d5c4bfcfdec99a0cf633a91102` | H | `43b35d46b129` | Covered/later P. Same responsive layout contract; P deliberately widens sidebar 280 -> 300 and agent pane 360 -> 400 for legibility. Old dimensions are not an integration delta. |
| 16 | U | `lib/pages/project/project_page.dart` | `ff160f9dfe785ee557e6d646e2caa7a0d4205a94` | H | absent | Deliberately removed by D. Old session-list plus composer project route is retained in history; current integrated editor/session UX supersedes this architecture, not necessarily every old UI choice. Reintroducing it is a deferred feature decision. |
| 17 | M | `lib/services/ai_service.dart` | `6f1c952850ab2824bf0a22cf2884a5f658851ca3` | H | `24ecdf0a0dba` | Covered/later P. Original model reasoning-effort encoding remains. P adds full streaming/reasoning handling for the three protocols; no port of older non-streaming service. |
| 18 | M | `lib/services/api_client.dart` | `76168181370854300c0a0220b0fd5db7dd6365e8` | H | `df8f431c3655` | Covered/later P. `AiModelInfo`, model/effort selection and model catalog remain. P adds stream/fallback, relay-message projection, context metadata, failure diagnostics and account-scoped cloud API; old file would erase these. |
| 19 | M | `lib/services/studio_profile.dart` | `8960d4f537b06766b041a4c361ae5c58ecc4f135` | H | `2ea0c0cefad9` | Covered/later P. Original optional `backgroundInteropRunner` remains. Preserve later QFLIStudioN branding and device-sync capability rather than restoring old branding/profile surface. |
| 20 | U | `lib/session/agent_session.dart` | `59d0653031162099ab0c502f313297fa7731b398` | H | `120a1a925c96` | Covered/later P. Session create/list/rename/delete and transcript/history persist remain. `6bc39a4` replaces whole JSON rewrites with JSONL/index, legacy migration, paging and later bounded compaction; old storage must not be reinstalled. |
| 21 | U | `lib/shell/agent_runtime_factory.dart` | `349313dcff90958b7910d31e8ee14e64a5f56193` | H | `03ad096a8af5` | Covered/later P. Cached runtime construction remains; P adds scheduler, disk model-cache directory and non-starting current-runtime accessor. |
| 22 | U | `lib/shell/login_gate.dart` | `b99dbdf543c56783676956a09862dea18b68fe5a` | H | `2f77cb69157c` | Covered/later P. Functional login gate identical; only reviewed difference is capitalization of Agent in explanatory copy. |
| 23 | U | `lib/shell/project_entry.dart` | `c7c9680fc7958e0b740ee031ed1c5052bb175f8d` | H | absent | Deliberately removed by D. Historical standalone project/workbench entry, not a missing migration API. |
| 24 | U | `lib/shell/workbench_agent_pane.dart` | `b8c7d2406da2a3dc3fa506fabcb925d37a811fd4` | H | `fcb10ac1597e` | Covered/later P. Session opening, draft send, approval and login paths remain; P adds live runtime/scheduler integration, resilient options, session switching, detailed errors/paging and file opening. Do not reinstall old ownership/disposal. |
| 25 | U | `lib/shell/workbench_shell.dart` | `c6863a8e31d6be024e60d3012f93ff07aa766f11` | H | absent | Deliberately removed by D. Prototype three-pane shell and its placeholder UI are historical; current editor-integrated agent and large-screen workbench own that boundary. |
| 26 | U | `lib/shell/workbench_state.dart` | `b143ac7a35775d2ded71c65c5af4797563b39670` | H | `b143ac7a3577` | Exact P. Shared state survives despite removal of obsolete wrapper shell. |
| 27 | U | `lib/sidebar/workbench_sidebar.dart` | `983f260419afbcec8caf325c6bdb67ecbead645d` | H | absent | Deliberately removed by D. Old duplicate files/sessions sidebar is not to be re-enabled next to unified current sidebar. |
| 28 | U | `lib/vibe_coding/vibe_agent_facade.dart` | `2b6048ee9f6055d78a1574a8e10e20f8eba1ce35` | F | `8e1a5b02c25c` | Covered/later P. Exact F variant adds error/activity/paging contract defaults, not completed implementations. P implements those plus live session registry, scheduling, write leases, cached models and reasoning/history. No unique unpublished facade additions. |
| 29 | M | `lib/vibe_coding/vibe_coding_controller.dart` | `78005e90ab9e6e407e493767dfa0dff1ddfd791d` | H | `00559101376d` | Covered/later P. Original approval hooks, restored/sanitized history, model/effort, read-only attachments, changed paths and `search_text` remain. P adds streaming/reasoning and coordinated newer behavior. |
| 30 | M | `lib/vibe_coding/vibe_models.dart` | `8dda4d32bb42546d89b7649a9b74eed8d0b1b675` | H | `d5105239abba` | Covered/later P. Original changed-path tool metadata remains; P adds reasoning message kind/duration. |
| 31 | M | `lib/vibe_coding/vibe_skills.dart` | `3d36a1f03def359de91d22fc281e8c5480b75508` | H | `5c252783ee58` | Covered/later P. User-level skills and project > user > built-in precedence remain. P adds Pi/Codex directories, lazy bodies, bounded UTF-8 reads and unreadable-directory handling. |
| 32 | M | `lib/vibe_coding/vibe_tools.dart` | `05afd4ce41678822d1edfd4295c328b65e947e07` | H | `ac67da89d84b` | Covered/later P. Bounded search and explicitly whitelisted external read-only attachments remain. P adds write guards/history and coordinated external-root access. Old direct filesystem paths must not overwrite those fixes. |
| 33 | U | `test/agent_session_test.dart` | `183f64de9ff2002338ea1cf61f706ce1013f7dc0` | H | `2bd2f4a6c49b` | Covered/later P. Basic session persistence/rename/delete/corrupt-file cases remain or migrate to legacy-JSON tests; P expands index/JSONL paging/corruption/compaction assertions. |
| 34 | U | `test/ai_reasoning_effort_test.dart` | `687608735fd03fa02558bd2168acd45a1dd6ca3c` | H | `687608735fd0` | Exact P. Reasoning-effort coverage already present. |
| 35 | U | `test/chat_attachment_picker_test.dart` | `3ee666ac8f0b6171dd89931895144d1f0653b3c6` | H | `b0afd4d24558` | Covered/later P. Original assertions remain; P adds empty-state close cases. Workbench menu has separate published coverage. |
| 36 | U | `test/chat_composer_card_test.dart` | `e9dd94ef7884f5bb50a798a58fbd28da79157c85` | H | `0daef30cae92` | Covered/later P. No unique scenario found in old variant; P contains original cases plus session-switch, model, width/accessibility and later UI regressions. |
| 37 | U | `test/chat_transcript_test.dart` | `bbeb25dcb86531e7f8ade5151ff0b62b437afaba` | H | `bd25c761f042` | Covered/later P. Original render/approval/retry assertions remain with the renamed retry label; P adds approval status and error details/copy/diagnosis/narrow-layout cases. |
| 38 | U | `test/composer_state_test.dart` | `057c476f4ca949edb6b895ed15a783761e3a6b6c` | H | `057c476f4ca9` | Exact P. |
| 39 | U | `test/editor_background_run_test.dart` | `c7a91a45fbf86d9c2d8d484f7125860e43a36353` | H | `f4c6c049f127` | Covered/later P. Same background-run assertions; P uses `support/ohos_target.dart` instead of a fork-only enum literal. |
| 40 | U | `test/editor_pad_layout_test.dart` | `fa841ed5dfd75b2d3d5d93d5b88fa2dc3f7aa03c` | H | `59b1cdc3d0c7` | Covered/later P. All 12 named breakpoint/sidebar/panel/focus/terminal/inset/resize scenarios remain; fixture/layout code evolves for integrated Agent UI. No old whole-file restore. |
| 41 | M | `test/interop_arkts_contract_test.dart` | `a60b9dd1f8fb3b161ef110e7184ed7ed59487b92` | H | `a60b9dd1f8fb` | Exact P, including the known checkout-name assumption. No unique dirty hunk blocks p4's independent portability correction. This is not a claim that the original test is portable. |
| 42 | U | `test/interop_background_transport_test.dart` | `4631b9931aa7bb4e4c3aa5653c49a131ff6799b9` | H | `3632e96e2390` | Covered/later P. Same background channel/stop assertions; portable OHOS target helper replaces enum literal. |
| 43 | M | `test/interop_protocol_test.dart` | `6d210a00f7727a8afbbd4a7623065eceadd6d602` | H | `6d210a00f772` | Exact P. Original session-token roundtrip assertions already present. |
| 44 | M | `test/interop_runner_test.dart` | `50f0012503f45747c3c0c7f7528b8fb5dac67be1` | H | `50f0012503f4` | Exact P. Done-text and confirmed/unconfirmed-stop assertions already present. |
| 45 | U | `test/interop_zip_test.dart` | `f57fa81a2955738f5d2b690c87dc449e8237341b` | H | `f57fa81a2955` | Exact P. |
| 46 | U | `test/project_page_test.dart` | `68d2fa112ba54a774b51961b8408a6ba87190019` | H | absent | Deliberately removed by D with its obsolete page. Retain historical assertions as provenance, not active tests for a removed route. |
| 47 | U | `test/support/fake_agent.dart` | `84a0ff22ead4db2c512e40eb43a7649461ea3854` | H | `0cf375875ebb` | Covered/later P. P extends the fake for newer live/error/stream contracts; old fake would remove needed seams. |
| 48 | U | `test/vibe_agent_facade_test.dart` | `ac4f50c3d7e6a5cf5719cf5e1d6191b7ec3f5971` | H | `f272e6ec8f5d` | Covered/later P. Login/permissions/attachments/history/model/skills/retry remain; P updates mock relay to streaming and adds metadata/paging/error/activity/cache/duplicate-trigger checks. |
| 49 | U | `test/vibe_attachment_read_test.dart` | `415a32f23f2c46ec18dfd7460c34373b27c8b41a` | H | `95fc4868f1be` | Covered/later P. Original whitelist tests remain; P updates persisted suffix to `.jsonl` and uses shared streaming relay fixture. |
| 50 | M | `test/vibe_coding_controller_test.dart` | `e5f81649111de7f1fab97915e56ba0fa760f624d` | H | `3bb84ac1dbf9` | Covered/later P. Original nine-tool expectation/search addition and assertions remain; P updates relay fixture to `/api/ai/chat/stream`. Remaining B delta is formatting, not missing behavior. |
| 51 | M | `test/vibe_coding_skills_test.dart` | `f18ba5a8807eee5653114dd0cc3b1bb2735fd8d2` | H | `0a5c4f9110cb` | Covered/later P. Original user-skill precedence/disable/home tests remain. P additionally sets `includeUserSkills: false` in three isolated tests to exclude machine HOME contamination. |
| 52 | M | `test/vibe_coding_tools_test.dart` | `7dba6bfcb72d0ae8ad85c494a7bdc933cd7f0b4d` | H | `7dba6bfcb72d` | Exact P. Original `search_text` schema expectation already present. |
| 53 | U | `test/vibe_controller_agent_hooks_test.dart` | `f6580280610fb3e11fd3795719e5935a5058d273` | H | `ecba8fef6d67` | Covered/later P. Same approval/restoration/model hooks; P uses shared streaming relay response and route assertion. |
| 54 | U | `test/vibe_search_text_test.dart` | `5a54cfbb455e9ac2bd66181ac083192d258245f8` | H | `4866b87b3874` | Covered/later P. Same bounded search tests; P uses shared streaming relay fixture/route assertion. |
| 55 | U | `test/workbench_shell_test.dart` | `beca786aa3b5f2bd318d08f237365005421bbed3` | H | absent | Deliberately removed by D with obsolete shell; not an independent uncommitted test gap. |
| 56 | M | `tool/vibe_e2e_runner.dart` | `fd24ad64ed1ce2d5d231fd819869297584afa74a` | H | `fd24ad64ed1c` | Exact P. Original fake API model/effort signature additions already present. No helper was run. |

### Root semantic cross-check anchors

All following history anchors were resolved to full commits and checked as ancestors of P; short names here are navigation shorthand:

- `6e30f47` embeds the Agent in the editor; D removes six obsolete shell/page paths. `fd1f5f4` unifies sidebar and stabilizes conversations.
- `3cbd918` preserves no-foreground-probe routing and adds missing-app outcomes; `19d3798` centralizes portable OHOS detection. At P, `showLocal` is `terminal_pane.dart:691`; `EditorAgentHost` construction is `editor_page.dart:535`; background output selects `showLocal` at `:3452`.
- `123602b` changes iOS project/sandbox paths; `1a2723c` adds runtime-install guidance. Replaying the old terminal loses both.
- `451595d` supplies live runtime scheduling/write leases; `6bc39a4` changes storage to JSONL/index; `9570129` and `fdd06c6` add reasoning/model streaming; `d5d18a8` adds context capacity; `fb64bab` adds skill discovery/Trellis context.
- At P the original controller hooks are explicit: `writeApprovalHook` at `vibe_coding_controller.dart:195`, `configureModel` at `:348`, `allowReadOnlyFiles` at `:354`, `search_text` dispatch at `:1063`. `vibe_tools.dart:163` registers read-only files; `:412` performs bounded search.
- Original interop behaviors are concrete at P: token validation `interop_protocol.dart:400`, token generation `interop_runner.dart:328`, ZIP handoff `interop_transport.dart:220`, integer normalization `:340`, background token check `interop_background_transport.dart:190` and confirmed stop `:271`.

These are static assertions/source/history observations. No local tests were executed and no new runtime acceptance is implied.

## Other five dirty linked-worktree snapshots

### Scope, base identities and exact-content result

Only the original manifest's changed/untracked files are included. Dependency source metadata is included, so WT30 has 30 files, not the 28 initially counted using only `lib/test/tool` filters. The final explicit count is **3 + 3 + 30 + 4 + 1 = 41**.

| Snapshot ID | Original linked worktree | Original HEAD | Changed / untracked |
| --- | --- | --- | --- |
| 06 | `D:/MyNewProjects/_wt/check-d/qfli_studio_core` | `e5b7fa3cb9fbc8ae4ceb18fca71998724da7f5b2` | 0 / 3 |
| 07 | `D:/MyNewProjects/_wt/cloudterminal-import/work/qfli_studio_core` | `5fc7268b34912d8677c0e95d77f8b0deef8ba69c` | 0 / 3 |
| 30 | `D:/MyNewProjects/_wt/remote-account-binding/core` | `72c0b0955e4ddd5215dc818327fa5a67a4be22f7` | 8 / 22 |
| 36 | `D:/MyNewProjects/_wt/studio-git-integration/qfli_studio_core` | `d5d18a8fc2de25df57b056e37dc7daa3b445de13` | 3 / 1 |
| 44 | `D:/MyNewProjects/_wt/ui-c/qfli_studio_core` | `30a3bd1acb6eac95d8d1a875b7a8218392c7d680` | 0 / 1 |

A read-only `rev-list --objects P` scan over the **complete published reachable tree/history**, not only the same paths, found none of these 41 Git-normalized blobs. No claim is made about unpublished refs; that is P2's lane. WT30 tracked base deltas and WT36 tracked base deltas were read from their captured patches as well as compared to immutable P. None of the 41 is approved for live product integration in this migration.

Categories below:

- **DF**: deferred authored feature; safe source candidate for inactive patch preservation, not a ready implementation.
- **DS**: deferred safety improvement; unique useful code, but user explicitly excludes activating it in migration.
- **DD**: deferred diagnostic/visual source; preserve as inactive patch or durable scenario summary, never auto-enable tests.
- **HC**: historical cloud-CI recipe; preserve inactive, do not replace current workflow or SDK pins.
- **SC**: semantically covered by newer published code despite a different whole-file blob; preserve only original research delta if useful, never replay.
- Privacy `A` = no credential/private-content exclusion identified in this source; `F` = literal hits are demonstrably fake test inputs or public package/version hashes; `N` = sanitize the public derivative as specified below. This is content publication review, not runtime security certification.

### Explicit 41-row product/source ledger

| # | WT / state | File | Original Git blob | Class / privacy | Evidence, minimal useful delta and disposition |
| --- | --- | --- | --- | --- | --- |
| L01 | 06 U | `tool/agent_editor_scenes_test.dart` | `32c8bc3df2651ab1fe9e7bcc6a2b19c49772f471` | DD / N | Authored integrated-editor screenshot scene driver: empty/running/errors/long/session/switch/TLS/drawer. Contains real machine-specific default output and font locations plus demo persona; sanitize public derivative. Keep source inactive; exclude PNGs/captures. |
| L02 | 06 U | `tool/pi_d_check_test.dart` | `da2e9f7bd90d005b935fb76809d546b48a275bbe` | DD / F | Authored independent C/D/G/H checks: immediate send feedback, progress/activity/wait, drafts/attachments, model labels, keyboard, touch targets, errors and hostile timing. Many scenarios now covered by published pane/composer tests. Preserve source in an inactive patch with future dedup review, not as newly executed or active tests. |
| L03 | 06 U | `tool/pi_d_switch_test.dart` | `7bfbcb966e64508278603dbb05305dec95f5239b` | DD / F | Narrow model/effort session-switch regression. Current P `test/workbench_agent_pane_test.dart:420` and `:472` cover switch and late model list. Preserve source/provenance inactive; no mandatory new test during migration. |
| L04 | 07 U | `.github/workflows/remote-control.yml` | `7479a2b27e64cf6d2c24984b01ba974ed4377e56` | HC / A | Branch-specific remote-module verification with fixed old paired commit/SDK, structure/analyze/module/full-suite jobs and pinned actions. Current module already exists on main and core-check covers the package on newer immutable inputs. Archive only; never install at `.github/workflows` now. |
| L05 | 07 U | `tool/ci/check_remote_control.py` | `906a1f26d0dcf37a1f38cca3077d0451d9d3046c` | HC / N | Source-layout, no-second-shell/import-origin, vendored xterm provenance and fixture-hash checks. Some invariants are useful, but literal historical source paths and fixture identities require a fresh fixture review before execution/public replay. Preserve code-only derivative, not fixture bodies. Local-run permission in historical docstring is not current policy. |
| L06 | 07 U | `tool/ci/setup_flutter.sh` | `96d651ee0e271f26cf5d3fc53c6da39ae1079506` | HC / A | Authored exact tag/commit install verification and retries for old OHOS Flutter 3.27.5. Current P uses 3.41.10 via pinned app helper. Contains destructive target cleanup if run: archive text only, no invocation/copy into current CI. |
| L07 | 30 M | `lib/app.dart` | `f3fe04a18c261b6011d9534b3cb0649819ddef86` | DF / A | Small base-relative delta wraps real existing AuthStore in RemoteAccountScope. Preserve original hunk only. Entire old app file lacks newer app/workbench behavior; never restore whole file. |
| L08 | 30 U | `lib/remote_control/account/account_api.dart` | `c20aae39af179be704e1739da2f5dc64f364179d` | DF / A | Separate QFLI grant and relay exchange/refresh/device/bind/revoke HTTP clients, no redirects and sanitized error responses. Runtime variables are credentials, not embedded values. Preserve inactive with account feature. |
| L09 | 30 U | `lib/remote_control/account/account_devices_page.dart` | `1df61d49c4574d419ef45c4fb75a82940a81a1a1` | DF / A | Device list/auth/bind/revoke/connect UI plus owner/sign-in scopes and manual fallback. Example relay URL is a placeholder, not a live credential/endpoint capture. Preserve inactive. |
| L10 | 30 U | `lib/remote_control/account/account_models.dart` | `0600b704c31401518177df7b1f28c09d99775b6c` | DF / A | Typed grant/device/cache decoder and id/time validation. No persisted live device list or grant instance in this source. Preserve inactive. |
| L11 | 30 U | `lib/remote_control/account/account_scope.dart` | `bb858978a804b920675c82f9d323b1145b9ed19a` | DF / A | Tiny real-AuthStore inherited scope. Neither definition nor its feature is in P; do not claim app dependents are already supported. Preserve inactive. |
| L12 | 30 U | `lib/remote_control/account/relay_credentials.dart` | `0fa0809270082d01f4927766bbc90beb203f13d5` | DF / A | In-memory default and secure-backend interface with version-fenced read/save/clear. Serialization methods are code, not stored token data. No actual backend or credential dump should accompany patch. |
| L13 | 30 U | `lib/remote_control/account/relay_endpoint.dart` | `d41f12d59bbd13d7b473deea9ec76de93c1d19f3` | DF / A | Validated WS-to-HTTP origin and `/api/` URL builder. Preserve inactive; no runtime server record embedded. |
| L14 | 30 U | `lib/remote_control/account/remote_account_controller.dart` | `00d0968e5fb2d1804f9a5469c0b38498545a703c` | DF / A | Identity/epoch/relay fences, credential restore/exchange/refresh, device cache and revoke/bind race handling. Valuable authored state machine but not validated server integration; no migration activation. |
| L15 | 30 U | `lib/remote_control/desktop/desktop_companion_channel.dart` | `83fb85f598cd1b8ab4f57c1f2b9c49bcadf4f70d` | DF / A | Line-delimited JSON channel/decoder and fake transport; protocol examples are placeholders. Preserve with companion feature, not actual socket transcripts. |
| L16 | 30 U | `lib/remote_control/desktop/desktop_companion_controller.dart` | `b1002e5cef288d7aa32aaedc6cf05c41e5875871` | DF / A | Companion lifecycle/pair code/discovery/open/input/status and bounded output state. No discovered session dump exists in source. Preserve inactive; future protocol/test reconciliation required. |
| L17 | 30 U | `lib/remote_control/desktop/desktop_companion_entry.dart` | `59b83c6c435fff9b9921b774bdc5220f6fb18359` | DF / A | App-scoped registry, shutdown and desktop-only entry/missing UI. Introduces process ownership behavior, not a migration fix. Preserve inactive. |
| L18 | 30 U | `lib/remote_control/desktop/desktop_companion_link.dart` | `6caa023e494f362e0f96fa294fd484da429f38f9` | DF / A | Conditional IO/stub export. Retain with both implementations; no live export into product now. |
| L19 | 30 U | `lib/remote_control/desktop/desktop_companion_link_io.dart` | `3c5e5daba66300ff8f1dfa3734df605a140b7ee7` | DF / A | Spawn/attach over authenticated loopback with ProcessSupervisor and attach-file cleanup. Reads runtime secrets but embeds none. Do not include actual attach/sidecar files or execute spawn code. |
| L20 | 30 U | `lib/remote_control/desktop/desktop_companion_link_stub.dart` | `c8342b46f4c6070605329d1dbac7423fc1c2269c` | DF / A | Browser unsupported surface. Preserve inactive with IO code; not evidence that all web paths compile. |
| L21 | 30 U | `lib/remote_control/desktop/desktop_companion_locator.dart` | `77d51e31c334a6334e14a90dfd7d27659b1aea96` | DF / A | Injectable installed/source bundle discovery and token-bearing attach-document parser. Paths are platform layout rules derived from environment; example comment is generic, not an observed user path. Preserve inactive. |
| L22 | 30 U | `lib/remote_control/desktop/desktop_companion_platform.dart` | `e051450532d668ccaad25408a65c5ada36c50528` | DF / A | Conditional platform probe export; retain both implementations as feature context. |
| L23 | 30 U | `lib/remote_control/desktop/desktop_companion_platform_io.dart` | `6a2f56d0035e356100e9bb78ecd5431b34d1578e` | DF / A | Runtime environment/filesystem adapters and attach-file reader. Code-only safe candidate; do not capture its runtime results. |
| L24 | 30 U | `lib/remote_control/desktop/desktop_companion_platform_stub.dart` | `11691bdc20da1f6cc1369579c1a35c37774bdbfd` | DF / A | Unsupported browser environment; preserve inactive. |
| L25 | 30 U | `lib/remote_control/desktop/desktop_companion_session.dart` | `810c0d9ed6adde2c00dcf515ede104f13eb41a8d` | DF / A | Shared child/connection lifetime, detach-only page handles and generation guards. Useful feature-level ownership design; source imports IO directly and needs future platform review, not migration enablement. |
| L26 | 30 U | `lib/remote_control/desktop/desktop_remote_page.dart` | `e42a9159f2d45000a297e27c31a85d17990f84ba` | DF / A | Pairing/countdown/QR, install diagnostics, attach file chooser and real-session UI. No real QR/session/credential payload embedded. Preserve inactive with QR dependency delta. |
| L27 | 30 M | `lib/remote_control/pages/home_screen.dart` | `3e8d8a98675b97f600b75acf317b077c0baef2f9` | DF / A | Base-relative account device action and auth recovery/banner hooks. Preserve hunks only; do not overlay current screen. |
| L28 | 30 M | `lib/remote_control/pages/pair_screen.dart` | `06da5dad143075932dad6622be3b1ae9a7a79979` | DF / A | Account entry and alternate pairing UI hooks; embedded command uses a user-supplied server placeholder. Archive hunks, not an instruction to run it locally. |
| L29 | 30 M | `lib/remote_control/remote_computer_page.dart` | `785829801449a0235a2c8f55bfb28a0a6902946d` | DF / A | Account scope/controller boot, token-provider wiring and lifecycle routing. Preserve hunks only; current P has no account integration. |
| L30 | 30 M | `lib/remote_control/state/remote_controller.dart` | `e02e19d1867b6699d7ff75f579241760864f7948` | DF / A | RelayTokenProvider, account-bound hello, no-secret fallback, save/dial generation checks. Some generation checks might be reusable later, but cannot be detached and enabled without account contract review. |
| L31 | 30 M | `lib/remote_control/state/remote_store.dart` | `bc7731e92804ad29ea1560283dd523b1a353eaba` | DF / A | PairingAuth/account-id metadata and JSON cache seam, excluding relay bearer values from pairing serialization. Preserve hunks only. |
| L32 | 30 M | `pubspec.lock` | `f8fef21f49b88dbab07e99c9a11dc64088e5371a` | DF / F | Original base-relative additions are only hosted `qr` and `qr_flutter` records with public package checksums. Dependency metadata, not build output. Archive just those hunks; never replace current lock/remove newer dependencies. |
| L33 | 30 M | `pubspec.yaml` | `d71c21f5901cb2620804d41cb57ed19b315cccb7` | DF / A | Only original feature delta is `qr_flutter` declaration/comment. Archive that hunk with companion feature. Whole old manifest would remove current secure-storage/Git/assets; prohibited. |
| L34 | 30 U | `test/remote_control/account_test.dart` | `43dd7fbd870c332eb04f0eef5c2220b7681f6b82` | DF / F | Mock HTTP/backend/socket account regressions; all literal grants/tokens/password-shaped URL inputs are synthetic construction/rejection fixtures, not real credentials. Preserve inactive. Fixed public QFLI service origin is source configuration, not captured account data. |
| L35 | 30 U | `test/remote_control/desktop/desktop_companion_controller_test.dart` | `5ef3154aa7ceb0fafb6d094c92d9308734040a8b` | DF / F | Fake channel pair-code/discovery/open/stream/input/disconnect tests. Literal loopback pairing URI and demo code are synthetic. Preserve inactive; no actual companion output. |
| L36 | 30 U | `test/remote_control/desktop/desktop_companion_locator_test.dart` | `1cf6da783d6f45cf51573262f66e1b29859b9588` | DF / F | `_FakeMachine` supplies every apparent personal filesystem path and manifest; no real disk reads. Synthetic home names can be normalized to `example` for public derivative hygiene, but no secret redaction is required. Keep attach parser rejection fixtures. |
| L37 | 36 M | `lib/editor/file_explorer.dart` | `5a65ec2694c1956862f1992517de264032a3945a` | DS / A | Unique guard calls before confirm and after backup; disables protected delete menu, fences async menu generation. P still has backed-up delete plus external-root policy but no config guard. Archive original guard-only hunks; future reconciliation must retain newer external-root and post-disposal deletion rules. |
| L38 | 36 M | `lib/services/cloud_sync_service.dart` | `15d735ecff4d94f8d87acf18dc2c68a4581323b0` | DS / A | Unique local+remote-tree protected-descendant check before dirty/cache/remote delete and current-session recheck. P has scoped deletion but not this protection. Archive hunks; no extra remote requests enabled now. |
| L39 | 36 U | `lib/services/project_config_guard.dart` | `f514bc92e171f23a14c13e54f5a9a6a0a619c0ff` | DS / A | Unique protected-name/descendant policy, Win32 alias checks, lexical/physical containment and recursive link checks. Useful safety follow-up; no tests were included with this original change. Preserve source inactive, design/tests required before future enablement. |
| L40 | 36 M | `lib/vibe_coding/vibe_rules.dart` | `3fef92619d4700ab81cd71936795869d9e2afbde` | SC / A | Original addition reserves Trellis bootstrap budget and detects nonempty regular workflow. P `fb64bab` already does this via `kVibeTrellisRuleEntry` and shared `TrellisProject.hasWorkflow`; P's truncation notice budgets an extra separator correctly. Archive original delta separately if retaining all authored progress; do not replace shared resolver/private-copy it. |
| L41 | 44 U | `test/tmp_probe_test.dart` | `a68339559fceb7289731211a49cd8e7bce645281` | DD / A | Print-only FunctionsTab scrollable/ancestor probe, no behavioral assertions. Preserve an inactive source patch or source-linked summary; not a regression test to activate. |

## Privacy review and precise public preservation recommendation

### Review performed and limits

All 41 original linked files were scanned as text without running them. Literal checks covered private-key markers, common provider access-token forms/JWTs, long opaque quoted strings, credential assignments, URL user-info, email-shaped text, machine-specific paths, URLs and credential/path-related string literals. Hits were reviewed in source context, especially all account test literals, companion attach fixtures, dependency hashes and diagnostic defaults. Source/patch content was read for the feature boundaries above; no runtime JSON, fixtures captured from real sessions, conversation archives or sibling checkouts were pulled into this review.

**No real embedded credential, private key, live grant, actual bearer/refresh token, real pairing secret, live session transcript or actual device-list capture was identified in these 41 source files.** This is a bounded source publication review, not a guarantee about all neighboring files/history or a security acceptance of the unfinished code. Do not export entire snapshot directories. Comments referring to tokens describe code/runtime contracts; they do not justify adding corresponding runtime files.

Publication exclusions/derivative normalization:

1. **WT06 `tool/agent_editor_scenes_test.dart:702-704`** contains a machine/sibling-task-specific default screenshot output. Omit the original default string from the public derivative and use an explicit `PREVIEW_OUT` input or neutral runner-relative output; record that normalization. Also make `UI_FONT_PATH` explicit/neutral rather than depending on the Windows system-font default near `:673`. Normalize the demo user's presentation fields near `:101-102` to a generic example persona. These are environment/privacy hygiene changes to the **archive derivative only**; originals and their manifest hashes stay untouched. Do not copy screenshot PNGs, actual fonts, rendered error details or task check output.
2. **WT07 `tool/ci/check_remote_control.py:92-97`** contains historical machine-checkout path deny strings. In the public derivative, retain the invariant but use generic repository/source-checkout markers instead of publishing a machine-specific prefix. Keep the original SHA-256/blob reference so the exact bytes are recoverable privately. The public source-head and fixture checksum constants are provenance, not secrets. **Do not include the fixture bodies** merely because this script refers to them; those recorded terminal captures are outside this 41-file clearance.
3. **WT30 `test/remote_control/desktop/desktop_companion_locator_test.dart`** uses in-memory `_FakeMachine` homes/install paths throughout. They are synthetic, not observations. Optional consistent normalization of the invented home basename is safe if recorded; keep structural distinctions required by nested macOS/Windows/Linux tests. No runtime `sidecar.json`, `agent.json`, token storage, auth store, relay cache or selected-file content is cleared for publication.
4. Account tests' short token/grant/secret and URL-user-info literals are demonstrably fake MockClient/rejection data; they should remain to preserve the assertions. Do not redact those into empty values and silently destroy the test contract. Public QFLI origin references and hosted package/version/checksum metadata are not private credentials.
5. Historical local invocation examples and helper scripts in archived patch text are **not** permission to run locally. Any future usage must obey the current cloud-only policy. No screenshots/raw captures, local stdout/stderr, diagnostic JSON, credentials, private prompts, machine runtime pointers or SDK binaries belong in the public preservation payload.

### Safe export shape (coordinator only; no export performed by this worker)

Store only inert UTF-8 `.patch` text plus a provenance/index Markdown file under the already-created **planning, unactivated** task `.trellis/tasks/11-27-core-preserved-followups/research/`. Do not put archived code at `lib/`, `test/`, `tool/` or `.github/workflows/`; no pubspec/import/test discovery change is authorized. A patch under research is not a promise it applies to current main. Record original snapshot ID, original full base, original path/blob/SHA-256, every derivative normalization and the exported patch SHA-256. Do not use a new blanket snapshot patch containing unreviewed neighboring context.

Recommended minimal separation, accounting for every linked row:

| Public inert artifact | Exact source selection | Original patch base | Publication decision / future boundary |
| --- | --- | --- | --- |
| `remote-account-binding.patch` | WT30 **7 new** `lib/remote_control/account/*.dart` plus **6 tracked** account integration paths: `lib/app.dart`, `lib/remote_control/pages/home_screen.dart`, `lib/remote_control/pages/pair_screen.dart`, `lib/remote_control/remote_computer_page.dart`, `lib/remote_control/state/remote_controller.dart`, `lib/remote_control/state/remote_store.dart`; plus **1 new** `test/remote_control/account_test.dart`. **14 files total.** | `72c0b0955e4ddd5215dc818327fa5a67a4be22f7` | Code-only safe candidate after coordinator final content scan. New files use addition hunks; tracked files use original base-relative delta, not full old files/P-to-W reversion. No QR dependency hunks here. Keep inactive pending server grant/relay contract, credential backend, current-app wiring, race/security and cloud tests. |
| `desktop-companion.patch` | WT30 **12 new** `lib/remote_control/desktop/*.dart`, **2 new** `test/remote_control/desktop/*_test.dart`, plus only original `qr_flutter`/transitive `qr` additions from `pubspec.yaml` and `pubspec.lock`. **16 files total.** | same WT30 base | Code-only safe candidate. Preserve conditional stubs, IO/process/session ownership and tests together, no Node bundle or actual attach manifest. Optional fake-home normalization recorded. Does not supply/install/validate the separate companion service. Future platform/packaging/protocol/lifecycle review required. |
| `project-config-guard.patch` | WT36 new `lib/services/project_config_guard.dart` and only guard-related original hunks in `lib/editor/file_explorer.dart`, `lib/services/cloud_sync_service.dart`. **3 files total.** | `d5d18a8fc2de25df57b056e37dc7daa3b445de13` | Safe authored safety source, **deferred** by explicit user direction. No active migration fix. Later acceptance must cover symlink/alias/descendant refusal, post-await rechecks, cloud session/tree response failures, external-root compatibility, async disposal and ordinary allowed deletes. Original has no dedicated guard tests. |
| `trellis-rule-bootstrap-covered.patch` (or an exact hunk/identity summary) | WT36 original delta in `lib/vibe_coding/vibe_rules.dart` only. **1 file.** | same WT36 base | Safe code-only provenance, semantically superseded. Keep separate from guard patch so replay cannot replace shared `TrellisProject` resolver. If summary-only, explicitly point to original snapshot/blob and P's equivalents; do not call it unfinished required implementation. |
| `remote-control-ci-historical.patch` | WT07 `.github/workflows/remote-control.yml`, `tool/ci/check_remote_control.py`, `tool/ci/setup_flutter.sh`. **3 files.** | `5fc7268b34912d8677c0e95d77f8b0deef8ba69c` | Inert code-only historical recipe after machine-prefix normalization above. Never install/dispatch it in migration: it checks an old explicit paired commit and OHOS 3.27.5, whereas current core-check uses P/current SDK/fixtures. Source marker is no longer absent from main, so the old claimed pairing guard does not prove current pairing. Preserve ideas, not obsolete validation claims. |
| `agent-ui-diagnostics.patch` | WT06 all **3** diagnostic Dart sources after the scene-driver normalization above. | `e5b7fa3cb9fbc8ae4ceb18fca71998724da7f5b2` | Inert code-only diagnostic history, not activated tests or screenshots. Include scenario summary noting current published switch cases and that no diagnostic was executed in migration. Future owner deduplicates/adapts before any cloud run. |
| `tools-scrollable-probe.patch` (or explicit summary) | WT44 `test/tmp_probe_test.dart`. **1 file.** | `30a3bd1acb6eac95d8d1a875b7a8218392c7d680` | Inactive print-only probe. Source-linked summary is acceptable; it is not a behavioral test and produces no acceptance result. No printed trace or capture needed. |

Accounting: **14 + 16 + 3 + 1 + 3 + 3 + 1 = 41** original files. If the coordinator chooses summaries rather than patches for the covered rule/probe, the index must explicitly record that choice and its source identity. All other safe unique authored feature source should be exported as inert reviewed patches to make progress cloneable; keep exact original bytes externally as well.

**No root patch is recommended:** its 56 files already have exact published history; cite H/F and this table instead of exporting obsolete implementation duplicates.

### Follow-up cautions, not migration implementation requests

- P has no `RemoteAccountScope`, `QfliGrantApi`, `RelayAccountApi` or desktop companion definitions in the inspected `lib/test` tree. Do not tell dependent apps these unfinished APIs are delivered by migration.
- Companion prototype comments do not prove browser support: `desktop_companion_session.dart` imports IO directly despite the conditional link facade. Fake channel/auth/discovery and source tests also require proper future reconciliation; preservation is not correctness acceptance.
- Config protection is a new application behavior across local deletion and cloud deletion, not simply a repository migration filter. The original guard checks are useful research, but enabling them would need a separate design and cloud tests.
- WT07 fixture identities/path checks refer to historical provenance. They cannot clear the referenced terminal fixture contents for publication, certify newer SDK behavior or replace p4's actual portable contract/CI work.
- External snapshots/bundle are preservation input; their existence does not authorize linked-worktree deletion or imply target/GitHub parity. Root and P2 retain those gates.

## Verification checkpoint

- [x] Original root file set reconciled: 20 M + 36 U = 56 explicit rows.
- [x] Root raw hashes match immutable snapshot manifest, and same-path exact historical provenance established for 56/56.
- [x] Facade F history separately confirmed; H/F ancestors of fixed P.
- [x] Root P dispositions: 12 exact P, 38 covered/later P, six explicit D removals; zero minimal port deltas.
- [x] Other dirty snapshot original set reconciled: 41 files including two pubspec files; every row has category, identity and privacy/public-preservation recommendation.
- [x] Linked raw hash checks: 41/41 match manifest; no exact linked blob found in complete P ancestry.
- [x] Proposed public artifact selections sum to all 41 files; diagnostic/covered-summary alternatives explicitly recorded.
- [x] No product/worktree/index/refs mutation or local verification execution by this worker.
- [x] Coordinator exported seven inert patches and a provenance manifest in `11-27-core-preserved-followups/research/`, covering all 41 linked files. Isolated-index reconstruction matched every reviewed derivative. Final staged-tree publication scan remains a separate coordinator gate; this update does not expand the worker's bounded privacy clearance.
- [ ] Fresh cloud validation of migration candidate/portability work belongs to p4/coordinator; this static preservation audit does not satisfy it.

The worker is available for independent portability source/CI review after this checkpoint. That review must use the new assigned immutable candidate/diff, not confuse p4's new changes with the original preserved WIP above.

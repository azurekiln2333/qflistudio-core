# Branch disposition ledger — checkpoint

Date: 2026-11-27. Scope: read-only branch/worktree preservation research for core. This is a checkpoint for root integration planning, not authorization to merge, stage, modify refs, or delete branches/worktrees.

## Evidence baseline and recovery boundary

- Comparison baseline: published GitHub `main` **476a30acee21dc486ee2849dd8064a7be665e4d5**. Local source `main` was previously **573d1b6eecf1c2b392ad753264a5a09f62f8335e**, then root fast-forwarded it to the same public baseline after relocating/preserving root WIP. Both identities are retained here.
- Current read-only advertisement: GitHub `main`, CNB `main` = 476a30a; GitCode and Gitee `main` = cbaa4a4166461baafff7c1a343bd3ca1865fcc4f, an ancestor of baseline. No advertised tags on any configured remote. Current local tag count: zero.
- All refs/reflogs preservation bundle: `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/all-refs-and-reflogs.bundle`; SHA-256 **104A7192E63C19DE09486DEC5ACBF2AAA77C44600FF788BCF343828A08A5C69A** (root reports bundle verified complete). This is the identity for recovery of unpublished original commit histories; do not replace with inferred ancestry or re-create commits.
- 70-worktree dirty/durable-context snapshot: `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/snapshot-20261127T062635Z/manifest.json` (created 2026-11-27T06:26:35Z). Snapshot records main at 573d1b6, 70 registered worktrees, file hashes and dirty/untracked state. Root has since relocated root WIP; no linked worktree was modified by this review. Root owns separate ignored build/checkpoint source inventory; this ledger does not repeat it.
- Current local refs: 69 local branches (including `main`); remote advertisements: 16 branch refs across configured remotes. Ledger has one row per local branch and per advertised remote branch. Remote-tracking refs are not additional advertisements.
- Status when inventory was captured: local `main` equals `github/main`; root WIP had been relocated by the owner. Root has continued independent edits since then. No builds, tests, analyzers, formatters, dependency installs, downloads, fetches, staging, commits, pushes, branch changes, or worktree changes were performed by this review.

## Disposition codes

- **IN**: tip is an ancestor of baseline 476a30a. Its committed history/content is already recoverable from a fresh clone at baseline; no replay needed.
- **PUB-MOBILE-CONTENT-EQUIVALENT**: the mobile semantics-disposal test commit has the same test blob change as content already present in advertised `github/ci/mobile-files` tip `d3d899571382121d3b5d69dd36b60222e5fa0b37`; do not replay or publish it. The preceding diagnostics commit changes timeout and suite selection; that workflow change is excluded as unsafe CI narrowing.
- **DEFER-HARNESS**: historical harness/Trellis/product variants remain inert review material. Non-ancestry and patch-ID differences do not prove missing functionality; baseline contains later work in these areas. Original commits remain recoverable from the external bundle and selected source derivatives are mapped in the branch manifest. Adoption and semantic supersession review belong to the planning follow-up, not migration activation.
- **DEFER-WSUI**: noncontained workbench UI, screenshot, test-fix and polish series. Preserve for UI-owner follow-up; no blanket merge. The rewritten integration tip has owner-reported failing CI. The advertised `github/wsui/integration` tip is a public recovery ref for its eight-commit rewritten series, while unpublished local fix/review/polish tips are in the full bundle. Use follow-up planning and exact-tip review before any patch.
- **SNAPSHOT**: dirty/untracked linked-worktree material is outside branch commits. It is hashed in the cited manifest and bundle/backup; preserve until its owning follow-up resolves it. Do not treat a clean committed tip as disposition of dirty files.

## Complete branch ledger

`Evidence` for all rows: full tip object ID; ancestry check against 476a30a; for noncontained rows, commit subjects and file-level patch scope inspected using read-only Git. Identical tips across refs are listed separately, as required.

| Ref | Full tip | Relative to 476a30a | Disposition / useful change and recovery |
|---|---|---|---|
| local `check/pi-a` | `a43b7df98142aab8459903952b2f592b0413f726` | IN | Same tip as `rework/pi-d`; no unique branch delta. |
| local `check/pi-b` | `a43b7df98142aab8459903952b2f592b0413f726` | IN | Alias tip; no unique branch delta. |
| local `check/pi-c` | `a43b7df98142aab8459903952b2f592b0413f726` | IN | Alias tip; no unique branch delta. |
| local `check/pi-d` | `e5b7fa3cb9fbc8ae4ceb18fca71998724da7f5b2` | IN | Baseline-contained editor unread-badge/double-send fix. |
| local `ci/mobile-diag` | `8a03c3077c65c728dccf9c2841f75ad1cde7b6d4` | 2 commits ahead | PUB-MOBILE-CONTENT-EQUIVALENT. Its test delta is already present in public `github/ci/mobile-files` tip `d3d899571382121d3b5d69dd36b60222e5fa0b37`; no fix or duplicate patch needed. The other commit is an excluded workflow timeout/suite-narrowing change. |
| local `feat/large-screen-workbench` | `ee83f1c0d72708547d0692e6cd05498d3539ce02` | IN | Baseline-contained. |
| local `fix/ohos-platform-check` | `f13028d90f451482173c948312da0d46726295b9` | IN | Baseline-contained platform guard. |
| local `harness/base` | `f9b648537fe862e3c26835b430bef54dc53f061c` | IN | Parent/base tip of harness cohort; no extra commit relative to baseline. |
| local `harness/integration` | `8440dcc9183e64bcae449730dec62778bcaade3d` | IN | Baseline-contained integration. |
| local `harness/pi-a` | `0917c93ba97392b4d5ec183a918dd94baaa5941a` | 3 commits ahead | DEFER-HARNESS. Local harness host/providers, Claude/Codex/Pi log readers, executable locator, PTY/mux, tests and synthetic fixtures. Keep as feature follow-up, not migration; bundle preserves commit chain `9c7f99f` → `d5305dc` → tip. |
| local `harness/pi-b` | `21152822e74d229e3b29a558c28cc4f4fbcbad2a` | 3 commits ahead | DEFER-HARNESS. Herdr + remote harness hosts/terminal/session mapping and tests. Bundle chain `c1625ad` → `09df701` → tip. |
| local `harness/pi-c` | `4f59dc08997a524ed9c29a5e6565b6df020e26ae` | 3 commits ahead | DEFER-HARNESS. Agents hub/unified surface and ownership/stop-confirmation behavior. Bundle chain `37e8108` → `31a7d8b` → tip. |
| local `harness/pi-d` | `d73db50b468b16f5242a44c72bfa25fc6ddf934a` | 4 commits ahead | DEFER-HARNESS. Studio agent host, project skills/Trellis context/session UI and discovery fixes. Bundle chain `56da9af` → `db47ef6` → `ec110b2` → tip. |
| local `main` | `476a30acee21dc486ee2849dd8064a7be665e4d5` | IN / baseline | Current source main equals public GitHub main. Original pre-fast-forward source main `573d1b6eecf1c2b392ad753264a5a09f62f8335e` and its WIP are preserved in external snapshot/bundle. |
| local `merge/core` | `9247d2db21da2e61b2163c4a699abc86e10ad3f4` | IN | Baseline-contained branding history. |
| local `mobile/integration` | `d2eca95626726961fd5461e94e5c50c1389fd088` | IN | Baseline-contained tab restoration. |
| local `mobile/pi-a` | `aeb97f7e0fba780a8534ef30232f1abb92e9060e` | IN | Baseline-contained sharing/subdirectory behavior. |
| local `mobile/pi-b` | `44e8953cb7a1b22c9f3868292cee2842bfc58f43` | IN | Baseline-contained external folder roots. |
| local `mobile/pi-c` | `69ebd651a37a2f9d3e48821ff2ad4a477c649141` | IN | Baseline-contained session details view. |
| local `mobile/pi-d` | `b1b6172bafc2a30323b26ea3aa29357c0af44e64` | IN | Baseline-contained sync/session cache. |
| local `r5/integration` | `cbaa4a4166461baafff7c1a343bd3ca1865fcc4f` | IN | Baseline contains this mirror main. |
| local `r5/pi1` | `5843ad8cbff9ecd450e74b91cf281daf7a3ca0ff` | IN | Baseline-contained composer overflow correction. |
| local `r5/pi2` | `5169fe1e60f8b238ddce022ad91f607f20abae87` | IN | Baseline-contained sidebar alignment. |
| local `r5/pi3` | `4306808ec21c9bcc072290f7670b7539505c4e07` | IN | Baseline-contained quick function bar. |
| local `r5/pi4` | `be1c800a46cb3eeac13da336f77b2709f7d3a855` | IN | Baseline-contained tools tests. |
| local `release/studio-git-ui-20261120` | `d5d18a8fc2de25df57b056e37dc7daa3b445de13` | IN | Baseline-contained release/UI series. |
| local `release/v5.0.5-preview.1` | `72c0b0955e4ddd5215dc818327fa5a67a4be22f7` | IN | Baseline-contained preview history. |
| local `remote/cloudterminal-core` | `5fc7268b34912d8677c0e95d77f8b0deef8ba69c` | IN | Baseline-contained remote-control change. |
| local `remote/remote-account-binding-core` | `72c0b0955e4ddd5215dc818327fa5a67a4be22f7` | IN | Baseline-contained tip; see dirty worktree snapshot ID 30 for separate unpublished account/desktop files. |
| local `rework/integration` | `b7f3d4022255fe31403b329692e559f538c2fa63` | IN | Baseline-contained. |
| local `rework/pi-a` | `9a6f4e82069ceb14b416c17bbebf4b9b7256d4d8` | IN | Baseline-contained narrow editor icon correction. |
| local `rework/pi-b` | `661425162d3249042f4c808f35da70c8f52fb8e5` | IN | Baseline-contained API failure-detail change. |
| local `rework/pi-c` | `1d942c38765f323a3a34c9b65cbf4b135536e06c` | IN | Baseline-contained chat failure explanation/tool-row sizing. |
| local `rework/pi-d` | `a43b7df98142aab8459903952b2f592b0413f726` | IN | Baseline-contained merge tip. |
| local `sync/progress` | `a20a84c73a220ad8e85bf766947a98d55bf665df` | IN | Baseline-contained HarmonyOS shell probe import. |
| local `thinking/contract` | `9a7cf78f0fd48bd32bb0fa5cdd8160a319d396e2` | IN | Baseline-contained failure names/diagnostics record. |
| local `thinking/loop` | `f38db122020c0de48b54e7635d45b8a18c3ef60e` | IN | Baseline-contained off-isolate session scan. |
| local `thinking/transport` | `05c7eb02c04397b4bb05986bd1fab533e42b419f` | IN | Baseline-contained tool-use stream registration fix. |
| local `thinking/ui` | `bac24058b97bbab1dfc3141c6fa7f2567bae1372` | IN | Baseline-contained merge. |
| local `ui/integration` | `573d1b6eecf1c2b392ad753264a5a09f62f8335e` | IN | Historical pre-fast-forward source main tip; its WIP file contents are separately in snapshot. |
| local `ui/pi-a` | `9a363f0d72a71acd1d742a236361e5b0889ec733` | IN | Baseline-contained home-tab order. |
| local `ui/pi-b` | `b0e7f5200d862c128c6bf1468871dd17136515cf` | IN | Baseline-contained merge. |
| local `ui/pi-c` | `30a3bd1acb6eac95d8d1a875b7a8218392c7d680` | IN | Baseline-contained tools rendering test. |
| local `ui/pi-d` | `26f674f24f43cc697ac2dbd6260f88e14f9a1947` | IN | Baseline-contained WebSocket dependency constraint. |
| local `wip/baseline-20261114` | `645e05162497ea38f619c5e1a5ae2bf96a6d1995` | IN | Baseline-contained agent contract history. |
| local `wsui/base` | `6e22b5bbaadc8adeef9a027d561b22f9011c1de7` | IN | Ancestor of baseline; no unique delta relative to 476a30a. |
| local `wsui/fix-a` | `cc833796654586ae362b455e34aebf80eaf287df` | 11 commits ahead | DEFER-WSUI. Workbench/screenshot follow-up fixup variant; UI/test changes depend on the deferred series. Retain exact tip in bundle; do not merge. |
| local `wsui/fix-b` | `8dd54c38a97d15903f9fea51afc758f22a0c08f3` | 13 commits ahead | DEFER-WSUI. Workbench screenshot/test fixup variant; same deferred UI series. Bundle-only local tip. |
| local `wsui/fix-ci` | `618fa2c1282684af04d0e11b6e5f08434aa264d3` | 10 commits ahead | DEFER-WSUI. Screenshot/CI/test-fix variant; workflow changes require separate cloud review. Bundle-only local tip. |
| local `wsui/fix-d` | `58a73d68ca7f42da103212162ad5b3c5469eef35` | 10 commits ahead | DEFER-WSUI. Large-screen/settings/screenshot fixup variant. Bundle-only local tip. |
| local `wsui/fix2-a` | `27534dd30120bae0d4b2594d38ba68a0a528326e` | 11 commits ahead | DEFER-WSUI. Later fixup variant; bundle-only local tip. |
| local `wsui/fix2-b` | `2eca924bf83ae59b0b838b0c0942fed6b3267c68` | 10 commits ahead | DEFER-WSUI. Editor/workbench fixup variant; bundle-only local tip. |
| local `wsui/fix2-ci` | `cefdf23f026c883aceca565e92729c0ef4f281e1` | 10 commits ahead | DEFER-WSUI. CI/test fixup variant; bundle-only local tip. |
| local `wsui/fix2-d` | `b731bf94a05e241cad2193abd629c58bedb69c2d` | 11 commits ahead | DEFER-WSUI. Large-screen page/test fixup variant; bundle-only local tip. |
| local `wsui/fix3-d` | `63c5cf63f4dbb54e11b6a658a790a7f6fefba7f1` | 2 commits ahead | DEFER-WSUI. Tools browser workbench test variant; bundle-only local tip. |
| local `wsui/integration` | `0defbf39d1ef35e4eae43717e1a910da0f9cfbe5` | 8 commits ahead, 8 baseline-only | DEFER-WSUI. Rewritten series includes MD3 workbench shell/explorer, editor/agent UI, density/intake, page layouts and screenshot workflow/tests (49 changed files in aggregate). Owner-reported failing CI; preserve as follow-up candidate, not accepted migration. Public recovery ref `github/wsui/integration` has this exact tip. |
| local `wsui/pfix-a` | `19a5845af9391a797d3d4b0aff5dd9703821153f` | 9 commits ahead | DEFER-WSUI. Follow-up test lifecycle/test synchronization over rewritten integration. Not contained by public integration tip; bundle-only local tip. |
| local `wsui/pfix-b` | `3bba2332d8348c5e89e8c1916c05b388ef8d3613` | 9 commits ahead | DEFER-WSUI. Follow-up test interaction synchronization and larger file-header coverage; bundle-only local tip. |
| local `wsui/pfix-d` | `2299d639bb86b3a065aa5dd62dc91f2970e41273` | 9 commits ahead | DEFER-WSUI. Screenshot Explorer restoration variant; bundle-only local tip. |
| local `wsui/pi-a` | `88ba03172abe7a6aa96789665e5c556b871e44cc` | 3 commits ahead | DEFER-WSUI. Workbench project deduplication and Explorer/navigation/controller behavior; bundle-only local tip. |
| local `wsui/pi-b` | `08fe626a56caf225df7d6abf23320fa13c3f1b03` | 3 commits ahead | DEFER-WSUI. Editor actions/retained-editor behavior and associated tests; bundle-only local tip. |
| local `wsui/pi-c` | `8101548999d419c84e78f965ad6630554a77dc8e` | 3 commits ahead | DEFER-WSUI. Replacement session-hub routing and tests; bundle-only local tip. |
| local `wsui/pi-d` | `ec04ba7d356dd1d1f8550d93d3e47cfe96bc38e1` | 3 commits ahead | DEFER-WSUI. Settings/content layouts and UI zoom test adjustments; bundle-only local tip. |
| local `wsui/polish` | `e12e6b56966051a968a2dcdaa5e970be36bb526e` | 4 commits ahead | DEFER-WSUI. Polish: MD3 menu/rail styling, Explorer/Agent headers, settings detail and screenshot scenes. Protected UI-owner follow-up. Bundle-only tip. |
| local `wsui/polish-a` | `cc7e88b97ab672e9bc2bea1c49f61cb3ffc90d64` | 1 commit ahead | DEFER-WSUI. Workbench chrome/theme/menu test fixup; bundle-only tip. |
| local `wsui/polish-b` | `d262af9e92f2361e72e04f614b4210b8b0593c7c` | 2 commits ahead | DEFER-WSUI. Explorer header/layout/test fixup; bundle-only tip. |
| local `wsui/polish-c` | `fd2dd927b2fb306f21dad203925d5d65eaafc689` | 1 commit ahead | DEFER-WSUI. Agent pane chrome/tests fixup; bundle-only tip. |
| local `wsui/polish-d` | `ef69fbd80bb94daf2e7bbee6f92bff32186ffe2a` | 2 commits ahead | DEFER-WSUI. Settings/screenshots test fixup; bundle-only tip. |
| local `wsui/shots` | `a661f54ca9fe54276f39cabd119e4d61b5015d8e` | 1 commit ahead | DEFER-WSUI. Adds opt-in screenshot test and workflow. Similar screenshot workflow already exists in baseline by content; retain branch provenance only unless a patch-id/content review finds a missing safe hunk. Bundle-only tip. |
| remote `cnb/main` | `476a30acee21dc486ee2849dd8064a7be665e4d5` | IN | Same as public baseline. |
| remote `gitcode/main` | `cbaa4a4166461baafff7c1a343bd3ca1865fcc4f` | IN | Ancestor/mirror baseline. |
| remote `gitee/main` | `cbaa4a4166461baafff7c1a343bd3ca1865fcc4f` | IN | Same advertised tip as GitCode. |
| remote `github/ci/agents-tabs` | `d2eca95626726961fd5461e94e5c50c1389fd088` | IN | Baseline-contained. |
| remote `github/ci/mobile-diag` | `8a03c3077c65c728dccf9c2841f75ad1cde7b6d4` | 2 commits ahead | PUB-MOBILE-CONTENT-EQUIVALENT; same test delta is already on public `github/ci/mobile-files` tip `d3d899571382121d3b5d69dd36b60222e5fa0b37`; workflow narrowing remains excluded. |
| remote `github/ci/mobile-files` | `d3d899571382121d3b5d69dd36b60222e5fa0b37` | IN | Baseline-contained. |
| remote `github/feat/large-screen-workbench` | `ee83f1c0d72708547d0692e6cd05498d3539ce02` | IN | Baseline-contained. |
| remote `github/main` | `476a30acee21dc486ee2849dd8064a7be665e4d5` | IN | Comparison baseline. |
| remote `github/release/studio-git-ui-20261120` | `c619f9ff0e83341f4efb548ea58eb7af42a9f51f` | IN | Baseline-contained release branch. |
| remote `github/release/v5.0.5-preview.1` | `72c0b0955e4ddd5215dc818327fa5a67a4be22f7` | IN | Baseline-contained release branch. |
| remote `github/remote/cloudterminal-core` | `b8d08a6703afd480374807b11e0ff16d1276e246` | IN | Baseline-contained; local remote/cloudterminal-core is a different but also contained tip. |
| remote `github/thinking/contract` | `9a7cf78f0fd48bd32bb0fa5cdd8160a319d396e2` | IN | Baseline-contained. |
| remote `github/thinking/loop` | `f38db122020c0de48b54e7635d45b8a18c3ef60e` | IN | Baseline-contained. |
| remote `github/thinking/transport` | `05c7eb02c04397b4bb05986bd1fab533e42b419f` | IN | Baseline-contained. |
| remote `github/thinking/ui` | `bac24058b97bbab1dfc3141c6fa7f2567bae1372` | IN | Baseline-contained. |
| remote `github/wsui/integration` | `0defbf39d1ef35e4eae43717e1a910da0f9cfbe5` | 8 commits ahead, 8 baseline-only | DEFER-WSUI; same public tip as local integration row. Owner-reported CI failure means do not merge wholesale. |

## Noncontained branch recommendations and recovery map

1. **Mobile diagnostic/test follow-up.** `8d512245b3650aadcc8434ca134ab9b7c923d00c` changes workflow timeout and selects four suites instead of the complete suite; exclude this CI change. The test-only commit `8a03c3077c65c728dccf9c2841f75ad1cde7b6d4` is content-equivalent to the `test/harness/home_agents_tab_test.dart` delta in published ancestor `d3d899571382121d3b5d69dd36b60222e5fa0b37` (blob pair `74cd815` → `9b8c916`). Do not replay it or publish a duplicate. Content equivalence is the disposition; its own branch history remains recorded in the bundle/ledger.
2. **Harness/Trellis cohort (four independent tips).** Historical variants cover local runtime providers, remote/Herdr transport, Agents hub and in-app Trellis/skills integration. Their source-only derivatives are now prepared in the 52-patch collection for preservation on main, while feature activation remains out of scope. The planning-only `11-27-core-preserved-followups` task records later adoption review. No public advertised branch holds these exact original tips; original commit objects and excluded bytes remain bundle-only. Once this candidate is published, a fresh clone will recover the selected inert derivatives and provenance, not the excluded material or original private commit history. Current main already contains later implementations in these domains; no missing-feature claim follows from a different tip or patch ID.
3. **Workbench/UI cohort.** The public rewritten series at `github/wsui/integration` / `0defbf39d1ef35e4eae43717e1a910da0f9cfbe5` remains a public recovery ref, with owner-reported failing CI. Do not merge or activate it wholesale. Selected original-parent-relative source derivatives from local `wsui/pi-*`, `pfix-*`, `polish*`, `fix*`, `fix2*`, `fix3-d` and `shots` are mapped in the prepared collection. Exact original commits remain in the external bundle. The branch rows' bundle-only descriptions concern original tip objects, not absence of these exported derivatives. Semantic equivalence to later accepted UI and adoption suitability remain deferred; these are not missing-feature conclusions or migration acceptance blockers.
4. **No other noncontained branch tips were found.** All remaining local/advertised refs are ancestry-contained by 476a30a. A branch row being contained says only its committed history is in baseline; it does not disposition linked-worktree dirt or ignored context.

## Recovery patch collection and review boundary

The inert per-commit collection is `.trellis/tasks/11-27-core-preserved-followups/research/branches/README.md`; the machine-readable original-parent mapping, refs, commit order, path exclusions, patch IDs and SHA-256 hashes are in `.trellis/tasks/11-27-core-preserved-followups/research/branches/branch-patch-manifest.json`. The captured set contains 30 noncontained refs, 83 unique commits and 52 distinct patch artifacts. A patch-ID match proves normalized Git patch equivalence only; it does not establish that a feature is absent from, or semantically superseded by, current `main`. Semantic supersession and adoption suitability remain explicitly pending. These patches are inert research; no feature activation or migration adoption is recommended.

For `harness/pi-b`, commit `c1625ad65f78bf1d35b0ec9547c3da01c4d8f3e9` has an explicitly withheld `test/harness_herdr_models_test.dart` section. The comment attributes fields to real Herdr output, while pane/workspace/terminal identifiers, titles, cwd values and the session path have unverified runtime provenance. The fixture section is excluded from the portable derivative and listed in the manifest; field names may be schema-derived, but exact values are not established synthetic. Companion `test/harness_herdr_platform_test.dart` also remains withheld for machine-specific path literals. Do not characterize either fixture as synthetic without provenance. This narrow exclusion is not a conclusion that the whole Herdr series is private or safe to activate.

## Durable progress not present in baseline and import candidates

The snapshot comparison against the actual commit tree of 476a30a found no linked-worktree-only `.trellis/spec`, `tasks`, `workspace`, `workflow.md`, or `scripts` path. Every durable path observed in linked worktrees is present in the public baseline tree; therefore there is **no unique linked-only Trellis task/spec/journal path that can safely be imported based on path absence alone**. The root source-main *file contents* at pre-fast-forward 573d1b6 were changed/untracked and the root backup manifest captures them; root owns their WIP relocation and recovery. The prior read-only hash comparison also found same-path variants among uncommitted root context and one linked snapshot for several specs/tasks/archive records. Those variants must be reconciled by content, not copied over the baseline.

Specific linked-worktree dirty/untracked evidence (do not duplicate root's ignored-build scan):

- Snapshot ID 30, `_wt/remote-account-binding/core`, tip `72c0b0955e4ddd5215dc818327fa5a67a4be22f7`: 8 modified tracked files, 22 untracked files. It includes account/relay and desktop companion source/tests (e.g. `lib/remote_control/account/*`, `lib/remote_control/desktop/*`, `test/remote_control/*`) and changes to `lib/app.dart`, remote-control screens/controllers, `pubspec.yaml` and lockfile. This is substantial feature work and may contain sensitive credential handling; keep private until owner review/privacy scan and separate follow-up. Bundle + snapshot hashes preserve it; not migration-safe and not a Trellis import.
- Snapshot ID 36, `_wt/studio-git-integration/qfli_studio_core`, tip `d5d18a8fc2de25df57b056e37dc7daa3b445de13`: three tracked modifications (`lib/editor/file_explorer.dart`, `lib/services/cloud_sync_service.dart`, `lib/vibe_coding/vibe_rules.dart`) and untracked `lib/services/project_config_guard.dart`. Separate feature follow-up; exact SHA-256 values are in manifest. Do not fold into this branch-preservation patch.
- Snapshot ID 7, cloudterminal import worktree, tip `5fc7268b34912d8677c0e95d77f8b0deef8ba69c`: untracked remote-control workflow/helper and `tool/ci/setup_flutter.sh`; snapshot hashes preserve them. These are tool/CI/source candidates requiring separate provenance/license/privacy review, not imported blindly.
- Snapshot ID 6, check-d, tip `e5b7fa3cb9fbc8ae4ceb18fca71998724da7f5b2`: three untracked `tool/agent_editor_scenes_test.dart`, `tool/pi_d_check_test.dart`, `tool/pi_d_switch_test.dart`; test/tool follow-up, not migration source.
- Snapshot ID 44, ui-c, tip `30a3bd1acb6eac95d8d1a875b7a8218392c7d680`: untracked `test/tmp_probe_test.dart`; diagnostic artifact, not a portable product test.

Baseline contains the linked task/spec paths observed in this snapshot, but that path comparison does not prove complete portable context. Root's separate reviewed import adds previously ignored workflow/scripts, specs, journals and selectively allowed `.agents`, `.codex` and `.pi` setup. Root snapshot ID 0 preserves their originals and runtime exclusions. Developer identity, runtime pointers, template hashes and raw captures remain excluded; authored source tests are classified individually, not categorically discarded.

## Explicit unresolved follow-up gates

- The source comparison is bounded to refs advertised during this read-only check and the supplied 70-worktree snapshot. Remote branch advertisements can move; refresh `ls-remote` before any publication or cleanup. No ancestry claim substitutes for file/path or test review.
- Private/generated/unclassified runtime material remains excluded: raw logs/reports, credential-bearing data, build/checkpoint trees and the specifically withheld Herdr fixtures. The separately reviewed seven WIP patches preserve 41 authored derivatives, including inert diagnostic source with recorded sanitization. No entire dirty worktree or raw capture is published by that selection.
- Public recovery refs already exist for the mobile and rewritten WSUI integration tips. Original unpublished harness/local-UI commit objects and excluded bytes remain external; selected text derivatives are now prepared for publication with their manifest. Do not equate derivative recovery with exact original history or claim publication before the gate completes.
- This review did not mutate original commits, refs or linked worktrees. The prepared patches remain unapplied inert research. Final staged-tree/privacy review and the core-last publication release remain coordinator gates; semantic adoption review is deferred to the planning follow-up.



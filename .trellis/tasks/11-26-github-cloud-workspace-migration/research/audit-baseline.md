# Read-only audit baseline: 2026-11-26

This is planning evidence, not final migration acceptance. Source coordinator directly inspected Git, paths and Herdr; four existing Pi were explicitly switched to gpt-6.1-sol and performed separate read-only audits. No local build/test/install or cleanup ran. Agent communications were through Herdr, not private conversation files.

## Direct source/target observations

- Source D:/MyNewProjects/qfli_studio_core main: 573d1b6eecf1c2b392ad753264a5a09f62f8335e. Initial git status --short: 46 records, including collapsed untracked directories. Later -uall counts are not directly comparable; planning files also increase the count.
- Live GitHub main queried using git ls-remote: ee83f1c0d72708547d0692e6cd05498d3539ce02. Source is 279 commits behind it.
- Target E:/MyNewProjects/QFLIProjects/qflistudio-core: clean main at the same baseline, only origin pointing to GitHub azurekiln2333/qflistudio-core. Target Codex w6A:p1 independently acknowledged these facts and the cloud-only rule; this was a pre-handoff acknowledgement.
- E:/MyNewProjects/QFLIProject does not exist. The plural parent contains 13 product clones; this session owns core only.
- Source remotes github/cnb/gitcode/gitee; target has only GitHub. Source main lacks .github; remote/target main contains core-check.yml.

## Branch/worktree audit: Pi w63:p2

Snapshot: 65 local branches, 20 remote-tracking refs including symbolic HEADs, zero local tags, 66 registered worktrees and three detached worktrees. Six worktrees have changes: root core; _wt/check-d/qfli_studio_core; _wt/cloudterminal-import/work/qfli_studio_core; _wt/remote-account-binding/core; _wt/studio-git-integration/qfli_studio_core; _wt/ui-c/qfli_studio_core. Status alone omits ignored durable context.

25 local branches had commits not in baseline GitHub main: ci/mobile-diag, harness/pi-a..pi-d and 20 wsui branches. Remote heads queries succeeded for all four remotes: GitHub had 14 heads at that later snapshot; others one each. CNB main 8440dcc and GitCode/Gitee main cbaa4a4 were ancestors of GitHub main. GitHub wsui/integration was moving; its final state requires refresh. Tags and ignored context across all worktrees still need complete refreshed execution inventories.

Claude w5H:p1 explicitly reports live ownership of wsui/* core worktrees, ongoing UI polish and a pending push to core main, plus app v5.0.14 work in _wt/wsui/app/qflistudio. Do not move, prune, overwrite or claim a final SHA until that owner hands off. Old source root remains dirty and must not be reset to the new remote.

## Context/artifact audit: Pi w63:p3

At its snapshot: .trellis tracks 55 files (8 specs, 47 task files), with 85 ignored files; .agents has 46 ignored Markdown skills/reference files; .codex has eight ignored portable configs/agents/hooks. Across 139 ignored context files, 112 durable candidates total 875841 bytes: 58 Trellis, 46 shared skill docs, eight Codex setup files. The remaining 27 are 19 pyc, four runtime pointers, two logs, developer identity and template hashes. These are candidates requiring reviewed inclusion, not automatic staging.

Remove broad root ignore entries for .trellis/.gitignore, .version, agents/, config.yaml, scripts/, spec/, tasks/00-bootstrap-guidelines/, workflow.md, workspace/ and all research. Keep .template-hashes.json excluded. Replace blanket .agents ignore with a default deny plus skills allowlist; similarly allow only known .codex agents/, hooks/, config.toml and hooks.json. Existing .trellis/.gitignore already narrowly excludes identity, runtime/session state, temporary files, backups and Python caches; preserve those rules. Review portable Pi integration separately.

Six existing context references point at three ignored specs. Four archived references point to missing pre-archive paths for the terminal-soft-keyboard task; repair to archive/2026-10 equivalents. Portable Codex setup uses relative project paths but requires user-level trust/hook configuration on a new PC; never commit authentication/trust settings.

No executable/native/Flutter package/cache binary names were found in HEAD/index scans; four intentional RobotoMono fonts remain. Seven vendored registrant/CMake text files require rationale rather than automatic deletion. Exactly 15 tracked raw historical research captures total 18550 bytes: twelve stdout/stderr, two report.json and one root-terminal-observation.json. Preserve historical blob/commit provenance before replacing current-tree captures with concise durable summaries. Keep intentional research Markdown and scripts. Filename scans are not a content/history secret clearance.

## Target/cleanup audit: Pi w63:p5

Target baseline tree: 10b5c6f17d04a644636fc6b70c675a982d0d9e31. Source baseline tree: 99110c61a56b4ef53ee0656e5439fdf95f80f75b. Target lacks workflow.md and .agents/.codex portable setup. Compare final commits/trees plus complete durable-file manifests and untracked/ignored audits; matching git status is insufficient.

The source .git is the common Git directory for all registered worktrees. Do not delete the root first. Root generated candidates include .dart_tool, build, .flutter-plugins-dependencies, two Flutter logs and two JVM crash logs. .trellis and vendor are not disposable output. Agent folders require durable/runtime classification.

Five WSL distributions were stopped: Ubuntu, qfli-terminal-test, qfli-terminal-al3-clean, qfli-terminal-al3-test, qfli-java-build. Terminal distributions map into D:/MyNewProjects/qflistudio/.artifacts; Java into D:/MyNewProjects/qfli_java/build/wsl; Ubuntu uses the Windows-managed location. None belongs exclusively to core. Exact registry paths and every owner's readiness must be rechecked before any unregister or deletion. No distro was launched or removed.

## Cross-repo contract communications

Rust coordinator w61:p1 owns qfli_rust -> qflistudio-rust. It acknowledges final core SHA as a dependency, unchanged Dart package/import name, and cloud-only verification. Its report says only native-runtime.yml currently exists, no repository secret/variable names were listed, and no patch_upstream_core.sh exists in Rust; this does not establish organization-level secret availability.

Claude w5H:p1 reports app path dependencies ../qfli_studio_core and vendor/re_editor/vendor/xterm, app-setup checkout alias qfli_studio_core with full CORE_REF, nine installer call sites, and app-owned tool/ci/patch_upstream_core.sh. Core-check pins APP_REF and JAVA_REF. Local target folder naming must not silently change package names or CI aliases. Claude owns UI/release work, not the whole six-platform migration. Final CI audit evidence is recorded separately.

## Subsequent core main writer handoff

On 2026-11-26, Claude w5H:p1 explicitly handed core main Git writes to w63:p1. The source coordinator independently queried live GitHub and CNB main, both 476a30acee21dc486ee2849dd8064a7be665e4d5, and GitHub wsui/integration, 0defbf39d1ef35e4eae43717e1a910da0f9cfbe5. Source root HEAD remains 573d1b6eecf1c2b392ad753264a5a09f62f8335e; its dirty files have not been reset or changed by migration.

GitHub API independently confirms completed successful run 45656065902 on exact 476a30a, with successful check and screenshots jobs. That run was originally triggered on wsui/integration; exact commit evidence now applies to the published main contents. It is not validation of future preservation/integration changes.

The owner reports all listed wsui worktrees clean, but retains them for a 5.0.15 polish follow-up and will coordinate before another main push. Rewritten 0defbf3 autosquashes UI polish into the prior series and currently fails CI according to the owner; preserve it as outstanding work, not an accepted merge. Main writer handoff is not permission to delete or rewrite the active polish worktrees.

App owner reports qflistudio-next main c5f4bc3afe9c81ba488fd3f544d43c3dac061512 and tag v5.0.14 pushed to GitHub/CNB with CORE_REF 476a30a, release workflow still running, app worktree clean. These app facts remain owner-reported until its final release evidence arrives. Main migration remains in planning pending user approval of the already presented plan.

Pi w63:p2 refreshed the bounded wsui inventory against explicit 476a30a: 19 registered wsui worktrees reported clean for tracked and ordinary untracked files (ignored data not audited). wsui/base is contained in that baseline; other wsui branches still have non-ancestor tips. The rewritten integration has eight commits on each side relative to 476a30a; wsui/pfix-b was also observed pointing to 0defbf3 without a registered worktree. Preserve all active work and refresh again before integration. A preliminary PowerShell quiet-command conditional emitted misleading MISSING labels; those labels are discarded, and branch presence is taken from for-each-ref output.

The worker's later corrected recheck already observed 23 registered wsui worktrees, all clean for tracked/ordinary untracked data, and 23 non-contained wsui refs including pfix-a/b/d. wsui/base and wsui/polish were contained. This supersedes the earlier 19-worktree snapshot and demonstrates continuing owner activity; branch-only commit counts overlap and are not a count of independent changes. Final cleanup/integration must use a fresh inventory.

## App migration owner coordination

Herdr w65:p1 identified itself as the qflistudio-next migration lead, owning D:/MyNewProjects/qflistudio -> E:/MyNewProjects/QFLIProjects/qflistudio-next. Direct pane inventory confirmed that cwd and active Codex. It will not edit core or language apps and will not globally delete WSL. Its four Pi perform read-only audits.

An initial prompt was rejected with agent_blocked while w65:p1 awaited user input; no interactive approval was answered. Later Herdr prompts succeeded and w65:p1 explicitly acknowledged the baseline, path contract and app ownership. The earlier delivery block is resolved. The most recent source/target status still has source 573d1b6 with 20 modified tracked and 60 visible untracked files including planning docs; target remains clean ee83f1c with sole GitHub origin. Core public main remains 476a30a, rewritten wsui/integration 0defbf3, and the common Git directory has 70 registered worktrees. These counts precede this documentation refresh.

Acknowledged app migration contract: canonical editing sibling is ../qflistudio-core, retaining Dart package/import qfli_studio_core and tracked vendor/re_editor plus vendor/xterm under that core folder. App owner must migrate pubspec, overrides, CI checkout paths, patch callers and dependent scripts coherently and prove it in cloud. Existing legacy CI aliases stay until that coordinated change; no automatic junction or local pub get. Core-check's independent app/Java aliases also require review if affected. Herdr inventory and pane lookup confirmed historical w5H:p1 no longer exists; no replacement was identified, and that absence does not release protected worktrees. App w65:p1 now owns app migration and installer CI; it reports app preservation c11a5a7 followed by integration of c5f4bc3. Those app progress reports are not core's independent completion evidence.

Later app owner update supersedes that c11a5a7 candidate status: historical screenshot/raw-report candidates are held in private backup, while the current app candidate tree is rebuilt on c5f4bc3 with core 476a30a and canonical sibling path. This is an owner-reported app history decision, not authorization to rewrite core history or a final core acceptance claim.

## Shared policy and dependent product status, 2026-11-27 continuation

SQL coordinator w62:p1 explicitly accepted exclusive ownership of E:/MyNewProjects/QFLIProjects/AGENTS.md, created it and reported a readback. Core independently confirmed the file exists, with SHA-256 295AB5A9A63CED3515A550E981D8DA145DEA606DF9E82B8F5AE8376726381163 at that inspection. Its convenience cloud-only rule does not replace committed per-repo instructions. App w65:p1 and target core w6A:p1 were notified through Herdr. No global WSL cleanup owner has been assumed by core.

Rust w61:p1, Go w5V:p1, Dart w5S:p1, Java w5W:p1, JSON w5X:p1, Python w50:p1, Web w64:p1, Git w5T:p1, Note w5Z:p1 and SQL w62:p1 received relevant core path/baseline/status replies. Delivery is not blanket acknowledgement or proof of downstream compatibility. Canonical repository is https://github.com/azurekiln2333/qflistudio-core.git; main remains 476a30acee21dc486ee2849dd8064a7be665e4d5. No final migration SHA, source/target parity or safe-delete claim exists. Rust has explicitly held its final core adoption while running independent native/source checks. Other products' implementation approval does not activate the core planning task.

App remote-account changes require RemoteAccountScope/DesktopCompanionEntry. Targeted definition searches in published 476a30a lib, dirty source lib and _wt/remote-account-binding/core/lib found neither definition. App owner is preserving its dependent patch/Trellis rather than enabling unresolved imports. This narrow search is not a complete API inventory or proof that a future migration SHA will supply those APIs.

## Dart temporary-clone historical commit preservation

Dart w5S:p1 reported two independent ignored clones, build/stock-core-checkout and build/stock-core-crlf, both at 573d1b6 with a nine-file diff matching its tracked tool/ci/stock-flutter-core.patch. Core did not inspect those clone contents or remove them.

Core directly checked these ten supplied tips in its non-shallow object database, with replacement objects disabled: a43b7df98142aab8459903952b2f592b0413f726, e5b7fa3cb9fbc8ae4ceb18fca71998724da7f5b2, fd1f5f4479cd60083cec871e3553ba9f3449dd56, 9a6f4e82069ceb14b416c17bbebf4b9b7256d4d8, 661425162d3249042f4c808f35da70c8f52fb8e5, 1d942c38765f323a3a34c9b65cbf4b135536e06c, 9a363f0d72a71acd1d742a236361e5b0889ec733, 7f7418c14bf07534c3061652f8c3f420b332c0a6, 26f674f24f43cc697ac2dbd6260f88e14f9a1947, 645e05162497ea38f619c5e1a5ae2bf96a6d1995. Each merge-base --is-ancestor TIP 476a30a returned 0, and each rev-list --count 476a30a..TIP returned 0.

Live GitHub main was independently queried at that full SHA. Pi w63:p2, gpt-6.1-sol, additionally queried live heads/tags: 13 heads and no tags; every supplied tip was reachable from advertised main and wsui/integration. Cached refs were not the preservation proof. This resolves only history reachable from those ten tips. Dart retains responsibility for preserving its patch, ignored/non-Git data and any additional refs before deleting those two exact clones. It does not authorize original core root/worktree or shared WSL deletion.

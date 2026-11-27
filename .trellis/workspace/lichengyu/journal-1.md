# Journal - lichengyu (Part 1)

> AI development session journal
> Started: 2026-10-11

---



## Session 1: Terminal soft-keyboard Return and tap fix
<!-- trellis-session: v=2 fp=e091eb4cf844c53a -->

**Date**: 2026-10-12
**Task**: Terminal soft-keyboard Return and tap fix
**Branch**: `main`

### Summary

Fixed all three terminal inputs (editor pane, window terminal, online terminal) so Return submits the command without collapsing the soft keyboard, and so tapping an already-focused terminal no longer re-pops the keyboard. Root cause: send is terminating (shouldUnfocus: true -> keyboard hides) and none is silently dropped by the OHOS engine (handleFunctionKey has no NONE branch). Switched to TextInputAction.unspecified via a shared TerminalInputBehavior helper; raising the keyboard now only happens when unfocused; hardware Return handled on all three fields. Added focused-after-Return and hardware-Return tests; terminal suites pass (83). Also gave the file-explorer sidebar an MD3 outlined card look (separate change, same branch).

### Git Commits

| Hash | Message |
|------|---------|
| `69d3fe1` | chore(task): add terminal soft-keyboard fix task |
| `a09c973` | fix(terminal): submit Return without hiding the soft keyboard |

### Status

[OK] **Completed**


## Session 2: Preserve core migration source and portable progress
<!-- trellis-session: v=2 fp=49015be6873b2b11 -->

**Date**: 2026-11-27
**Task**: Preserve core migration source and portable progress
**Branch**: `main`

### Summary

Authorized migration execution resumed. Independently preserved all refs/reflogs and 70 worktrees, aligned source main to the tested public baseline, reconciled original root WIP and prepared inert linked-source preservation, portable Trellis context and checkout-independent CI repairs. Publication and candidate cloud validation remain pending.

### Main Changes

- All 56 original root product files have published-history provenance; do not replay obsolete source.
- Seven inert patches preserve 41 unique authored linked-worktree files under the planning-only follow-up task.

### Git Commits

| Hash | Message |
|------|---------|
| `476a30acee21dc486ee2849dd8064a7be665e4d5` | test(screenshots): add opt-in workbench capture job |

### Testing

- [OK] No local builds, tests, formatters, analysis, installs, artifact downloads or WSL invocation. Source/hash/history inspection only.

### Status

[OK] **Completed**

### Next Steps

- Finish static candidate review, publish only through shared push gate, validate exact SHA on GitHub, then pull and compare target and obtain Herdr handoff.


## Session 3: Prepare reviewed core migration candidate under publication hold
<!-- trellis-session: v=2 fp=8da77e290cfcdef9 -->

**Date**: 2026-11-27
**Task**: Prepare reviewed core migration candidate under publication hold
**Branch**: `main`

### Summary

Preserved portable Trellis and inert source history, committed permanent interop fixture portability and hosted coverage, completed bounded source/index review. Core-last order prevents push request until brain releases it. Exact candidate CI, target parity and handoff remain pending; no local product execution or cleanup.

### Git Commits

| Hash | Message |
|------|---------|
| `beb333361484486306e48f66336d8d9a88075df6` | chore(migration): preserve portable progress and reviewed source history |
| `9c70b5067a7347c3d5992686c24e56ef2d007151` | fix(test): resolve interop fixtures independently of checkout names |

### Status

[OK] **Completed**

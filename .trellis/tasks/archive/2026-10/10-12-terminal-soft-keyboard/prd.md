# Fix terminal soft-keyboard interaction on Return and tap

## Goal

On mobile, both terminal inputs must (a) execute the typed command when the
user presses Return **without** the soft keyboard collapsing, and (b) raise the
soft keyboard when the terminal canvas is tapped **only if it is not already
open** — no repeated pop/jump on every tap.

Affected surfaces:

- Editor terminal pane input — `lib/editor/terminal_pane.dart` (`_buildPromptRow`)
- Window terminal input — `lib/terminal/widgets/terminal_output.dart` (`_buildInputLine`)

## Background

This is a regression cycle. History:

- `b75f656` set `TextInputAction.none` to stop the platform dismissing the
  keyboard on Return. But `none` also removes Return as a submit action, so
  `onSubmitted` never fired and the terminal accepted no commands at all.
- `de54eb0` reverted to `TextInputAction.send` and relied on re-focusing after
  submit. This restored submitting, but reintroduced the keyboard collapse:
  `send`/`done` tells the platform the field is finished, so it closes the
  input connection and hides the IME. Re-requesting focus afterwards races the
  platform teardown — the user sees the keyboard drop, or it stays up but the
  command did not run.

Both `none` and `send` are therefore wrong. There is no `TextInputAction` that
both submits *and* keeps the keyboard up.

## Root cause

1. **Return collapses the keyboard.** `TextInputAction.send` is a
   "terminating" action: the platform treats it as *field finished* and closes
   the input connection. `onSubmitted` may still fire, but the keyboard is
   already being dismissed; the post-submit `requestFocus()` is too late and
   races platform teardown.

2. **Tap re-shows the keyboard unconditionally.** Both tap paths do
   `if (focusNode.hasFocus) SystemChannels.textInput.invokeMethod('TextInput.show')`.
   Calling `TextInput.show` while the field is already focused and connected
   forces the platform to re-evaluate the IME, which visibly pops/jumps the
   keyboard on every single tap. Raising the keyboard is only appropriate when
   the field is **not** already focused.

## Requirements

- R1 — Pressing Return with the soft keyboard open must execute the command and
  keep the soft keyboard open (focus retained, keyboard not dismissed).
- R2 — Pressing Return must never be a no-op: the command must always run.
- R3 — Pressing Return must not insert a newline into the input field.
- R4 — Tapping the terminal canvas while the field is **not** focused must
  focus the field and raise the soft keyboard (existing behaviour preserved).
- R5 — Tapping the terminal canvas while the field **is** already focused must
  not call `TextInput.show` and must not move/jump the keyboard.
- R6 — Hardware Return (desktop / physical keyboards) must still submit.
- R7 — Both surfaces (editor terminal pane, window terminal) share one
  mechanism; no divergence that can regress one but not the other.
- R8 — Text history navigation (arrow up/down), session switching, clear, and
  the running/preparing hidden-prompt states keep working.

## Acceptance Criteria

- [ ] AC1 — `textInputAction` on both terminal inputs is non-terminating
  (`TextInputAction.none`), asserted by widget test, so the platform never
  dismisses the keyboard on Return.
- [ ] AC2 — A Return delivered as a newline character in the input controller
  submits the command (widget test: enter `cmd\n` via the controller → command
  runs, field cleared, no `\n` retained).
- [ ] AC3 — Hardware Return key event (`LogicalKeyboardKey.enter`) submits
  (widget test).
- [ ] AC4 — `onSubmitted` path remains wired so `receiveAction` in existing
  tests still submits (regression guard for AC2/R2).
- [ ] AC5 — Tap-while-focused does **not** invoke `TextInput.show`; tap while
  unfocused does request focus. Verified by code structure + a test asserting
  focus is unchanged and no double-show in the focused case.
- [ ] AC6 — Existing terminal test suites pass unchanged
  (`terminal_pane_test.dart`, `terminal_manager_delegate_test.dart`,
  `shell_command_test.dart`, `editor_run_test.dart`).
- [ ] AC7 — `dart analyze lib test` is clean.

## Out of scope

- Terminal session/PTY logic, shell backends, output rendering.
- The file-explorer sidebar (separate change on this branch).
- Any editor keyboard handling outside the terminal input field.

## Notes

The keyboard-*hiding* half (AC1/AC5) cannot be asserted behaviourally in the
`flutter_test` binding because there is no real IME; tests assert the
configuration and the submit mechanism instead, with comments recording why.
That is the same limitation the prior regression slipped through.

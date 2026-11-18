# Component Guidelines

> How components are built in this project.

---

## Overview

<!--
Document your project's component conventions here.

Questions to answer:
- What component patterns do you use?
- How are props defined?
- How do you handle composition?
- What accessibility standards apply?
-->

(To be filled by the team)

---

## Component Structure

<!-- Standard structure of a component file -->

(To be filled by the team)

---

## Props Conventions

<!-- How props should be defined and typed -->

(To be filled by the team)

---

## Styling Patterns

<!-- How styles are applied (CSS modules, styled-components, Tailwind, etc.) -->

(To be filled by the team)

---

## Accessibility

<!-- A11y requirements and patterns -->

(To be filled by the team)

---

## Terminal Text Input (Flutter-OHOS)

The terminal inputs live in three places and **must** share the same soft-keyboard
behaviour via `lib/terminal/widgets/terminal_input.dart`:

- Editor terminal pane — `lib/editor/terminal_pane.dart`
- Window terminal — `lib/terminal/widgets/terminal_output.dart`
- Online terminal page — `lib/pages/online_terminal_page.dart`

### Convention: terminal Return uses `TerminalInputBehavior.action`

`TerminalInputBehavior.action` is `TextInputAction.unspecified`. Do not hand-pick
a `TextInputAction` on a terminal field.

**Why `unspecified`**: it is the only action that both submits and keeps the soft
keyboard up on this target (Flutter 3.27 `flutter_ohos`):

| `TextInputAction` | Return submits? | Keyboard stays up? |
|---|---|---|
| `done` / `go` / `send` / `search` / `next` / `previous` | ✅ | ❌ Flutter finalizes with `shouldUnfocus: true` |
| `none` | ❌ on OHOS | ✅ in Flutter, but never reached |
| `newline` (single-line) | ✅ | ❌ `shouldUnfocus: true` |
| **`unspecified`** | ✅ | ✅ `shouldUnfocus: false` |

`onSubmitted` stays wired: with `unspecified`, `EditableText.performAction` calls
`_finalizeEditing(shouldUnfocus: false)`, which fires `onSubmitted` and leaves
focus (and the keyboard) in place.

### Gotcha: `TextInputAction.none` silently dead-ends on OHOS

> **Warning**: On the OHOS engine, `TextInputAction.none` maps to
> `EnterKeyType.NONE`, and
> `flutter_ohos/.../plugin/editing/ListenableEditingState.ets`
> `handleFunctionKey` has **no `NONE` branch**. Pressing Return therefore reaches
> no `TextInputChannel.performAction`, so `onSubmitted` never fires and the
> command does not run. It looks like Return is bound but does nothing.
>
> `unspecified` maps to `EnterKeyType.UNSPECIFIED`, which the same switch **does**
> handle (`unspecifiedAction`).

### Convention: only raise the keyboard when unfocused

Use `TerminalInputBehavior.focusAndShowKeyboard(node)` from tap handlers. Calling
`SystemChannels.textInput.invokeMethod('TextInput.show')` while the field is
already focused makes the platform re-evaluate the IME, which visibly pops/jumps
the keyboard on every tap. Tapping an already-focused terminal must be a no-op
for the keyboard.

### Hardware Return

The soft keyboard never delivers a hardware key event; it arrives as
`TextInputClient.performAction`. Desktop/physical keyboards do send
`LogicalKeyboardKey.enter` / `numpadEnter`, so hardware Return must be handled
explicitly (see `TerminalInputBehavior.handleHardwareKey`).

### Testing limitation

The `flutter_test` binding has no real IME: `tester.testTextInput.receiveAction`
bypasses the configured action, and newline characters are stripped before they
reach a single-line field's controller. Keyboard visibility and OHOS action
routing therefore **cannot** be asserted behaviourally. Tests must assert:

- `TextField.textInputAction == TerminalInputBehavior.action`
- `TextField.onSubmitted != null`
- `receiveAction(TextInputAction.unspecified)` runs the command **and** the
  field keeps focus
- a hardware `enter` key submits and clears the field

---

## Common Mistakes

<!-- Component-related mistakes your team has made -->

### Common Mistake: choosing `send` or `none` for a terminal Return key

**Symptom**: Pressing Return either collapses the soft keyboard, or (after
switching to `none`) the command never runs.

**Cause**: `send` is a terminating action (`shouldUnfocus: true` → keyboard
hides). `none` is silently dropped by the OHOS engine's `handleFunctionKey`
(no `NONE` branch). Both look correct in Flutter's own `performAction` switch.

**Fix**: Use `TerminalInputBehavior.action` (`unspecified`).

**Prevention**: Never pick a `TextInputAction` for a terminal field by hand;
assert `textInputAction == TerminalInputBehavior.action` in widget tests, and
remember that `receiveAction` in tests does **not** exercise the action's
platform path.

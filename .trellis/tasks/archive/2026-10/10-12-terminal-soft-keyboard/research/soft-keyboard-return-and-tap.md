# Terminal soft-keyboard: Return & tap behaviour

## Question

Why does Return either collapse the soft keyboard, or (when fixed) fail to run
the command — and why does tapping the terminal re-pop the keyboard every time?

## Evidence from git history

Two prior commits touched exactly this behaviour on the same two fields:

### `b75f656` — first attempt: `TextInputAction.none`

Set `none` to stop the platform dismissing the keyboard on Return. Result:
`none` removes Return as a submit action, so `onSubmitted` never fired and the
terminal accepted **no commands at all**.

### `de54eb0` — revert: `TextInputAction.send`

Commit message (verbatim):

> Commit b75f656 set `TextInputAction.none` on the terminal input fields to
> stop the platform dismissing the soft keyboard after Return. `none` also
> removes Return as a submit action, so `onSubmitted` never fired and the
> terminal accepted no commands at all.
> Restore `TextInputAction.send` at both sites. Keeping the keyboard up was
> already handled independently by re-focusing in `_submit`, so nothing is
> lost by dropping `none`.

That reasoning is incomplete: re-focusing after submit does **not** keep the
keyboard up, because `send` is a terminating action — the platform closes the
input connection first.

## Root cause (this session)

Both `none` and `send` are wrong because they are opposite ends of the same
`TextInputAction` trade-off:

| action | Return submits? | Platform hides keyboard? |
|---|---|---|
| `none`  | ❌ (no `onSubmitted`) | ✅ no  |
| `send`  | ✅ (`onSubmitted`)    | ❌ yes |

There is no built-in action that both submits and keeps the keyboard up.

## Why re-focus after submit does not work

On Android/iOS, a terminating `TextInputAction` (`send`/`done`/`go`) tells the
platform the *field is finished*. The engine closes the input connection and
the IME hides. `onSubmitted` may still be delivered locally, but the
`focusNode.requestFocus()` in `_submit` runs after the platform has already
started teardown. The observable outcomes are exactly the two the user
reported: keyboard drops, or it stays but the command did not run (the two
paths racing).

## Why tapping re-pops the keyboard

Both tap handlers contain:

```dart
if (focusNode.hasFocus) {
  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
}
```

The comment claims this is for "already focused but the keyboard was
dismissed". But it also fires on every ordinary tap while the keyboard is
open, forcing the platform to re-evaluate the IME — a visible pop/jump. The
correct guard is: raise the keyboard only when the field is **not** already
focused.

## Chosen mechanism

1. `textInputAction: TextInputAction.none` — non-terminating, so the platform
   never dismisses on Return.
2. Detect Return from the **newline the soft keyboard inserts** into the
   controller: a controller listener sees `\n` / `\r`, strips it, and submits.
   This makes Return work again without a terminating action.
3. Handle hardware Return via `Focus.onKeyEvent` (`LogicalKeyboardKey.enter`).
4. Keep `onSubmitted` wired for platforms/tests that deliver it.
5. Tap path: only `requestFocus()` when `!hasFocus`; never call `TextInput.show`
   while already focused.

## Why the regression shipped

Every existing test drives submit with
`tester.testTextInput.receiveAction(TextInputAction.done)`, which delivers
`onSubmitted` **regardless of the field's configured action**. A `none` field
still "passes". Prior fix `de54eb0` added a config assertion
(`textInputAction != none`) — that catches `none` but not the keyboard-hide
caused by `send`.

## Test limitation

The `flutter_test` binding has no real IME, so keyboard visibility cannot be
asserted. Tests assert (a) the non-terminating action, (b) the newline-submit
mechanism, (c) hardware Return, (d) the existing `onSubmitted` path. Comments
in the tests record this limitation so the next person does not assume
coverage that is not there.

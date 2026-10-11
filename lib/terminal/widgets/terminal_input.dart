import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared soft-keyboard behaviour for the terminal input fields (the editor
/// terminal pane, the window terminal, and the full-page online terminal).
///
/// Keep every terminal input on [action] and [focusAndShowKeyboard] so one
/// surface cannot regress without the others.
///
/// ## Why [action] is `unspecified`
///
/// The Return key must submit the command **and** keep the soft keyboard up.
/// No `TextInputAction` obviously does both, and two earlier attempts broke in
/// opposite ways:
///
/// - `send` (and `done`/`go`/`search`/`next`/`previous`) tells Flutter the field
///   is finished. `EditableText.performAction` finalizes with
///   `shouldUnfocus: true`, so the platform hides the keyboard on Return;
///   re-focusing afterwards races that teardown.
/// - `none` keeps the keyboard up in Flutter's own code (`shouldUnfocus: false`)
///   but **does not work in this app**: it maps to the OHOS
///   `EnterKeyType.NONE`, and the OHOS engine's `handleFunctionKey` switch has
///   no `NONE` branch (see
///   `flutter_ohos/.../plugin/editing/ListenableEditingState.ets`), so Return is
///   silently dropped and no command is sent.
///
/// `unspecified` is the one action that satisfies both:
/// - Flutter: `performAction` → `_finalizeEditing(shouldUnfocus: false)`, which
///   invokes `onSubmitted` **without** dismissing the keyboard.
/// - OHOS: maps to `EnterKeyType.UNSPECIFIED`, which the engine *does* handle
///   (`handleFunctionKey` → `unspecifiedAction` → `performAction`), unlike
///   `NONE`.
///
/// So the fields keep `onSubmitted` wired and use [action]; Return submits and
/// the keyboard stays up.
class TerminalInputBehavior {
  TerminalInputBehavior._();

  /// Non-dismissing, submit-capable action; see the class doc for the full
  /// reasoning and the two actions that must not be used.
  static const TextInputAction action = TextInputAction.unspecified;

  /// Handles a hardware Return (desktop, or a physical keyboard on mobile) on a
  /// terminal input's enclosing [Focus].
  ///
  /// Returns [KeyEventResult.handled] when the key was Return, so the field does
  /// not also receive it.
  static KeyEventResult handleHardwareKey(
    KeyEvent event,
    VoidCallback onReturn,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    onReturn();
    return KeyEventResult.handled;
  }

  /// Focuses [focusNode] and raises the soft keyboard, but only when the field
  /// is not already focused.
  ///
  /// Calling `TextInput.show` while the field is already focused forces the
  /// platform to re-evaluate the IME, which visibly pops/jumps the keyboard on
  /// every tap. Tapping a terminal whose keyboard is already open must be a
  /// no-op for the keyboard.
  static void focusAndShowKeyboard(FocusNode focusNode) {
    if (focusNode.hasFocus) return;
    if (!focusNode.canRequestFocus) return;
    focusNode.requestFocus();
  }
}

// Turns terminal input bytes into Herdr input operations.
//
// A Herdr pane is driven through two different CLI verbs: literal text goes to
// `pane send-text`, and keys go to `pane send-keys` by name. Raw terminal input
// from the key bar or a hardware keyboard is a byte string, so something has to
// decide which bytes are text and which are keys — this file, in one place, so
// the local host and the remote host cannot disagree.
//
// Unknown escape sequences are dropped instead of forwarded as text: sending
// `ESC [ 1 5 ~` literally into a shell would type garbage, whereas dropping it
// only loses a key Herdr never advertised.

import 'dart:convert';
import 'dart:typed_data';

/// One thing to do with a chunk of terminal input.
sealed class HerdrInputOp {
  const HerdrInputOp();
}

/// Type this text literally.
final class HerdrSendTextOp extends HerdrInputOp {
  const HerdrSendTextOp(this.text);

  final String text;
}

/// Press these logical keys, in order.
final class HerdrSendKeysOp extends HerdrInputOp {
  const HerdrSendKeysOp(this.keys);

  final List<String> keys;
}

/// Converts raw terminal bytes into [HerdrInputOp]s.
class HerdrInputTranslator {
  const HerdrInputTranslator();

  /// Translates [data]. Never returns empty ops for printable input, and merges
  /// consecutive printable characters into a single text op so typing a word is
  /// one `pane send-text` call instead of one per character.
  List<HerdrInputOp> translate(Uint8List data) =>
      translateText(utf8.decode(data, allowMalformed: true));

  /// Same as [translate] for already-decoded input (xterm hands out strings).
  List<HerdrInputOp> translateText(String data) {
    final ops = <HerdrInputOp>[];
    final text = StringBuffer();
    var i = 0;

    void flushText() {
      if (text.isEmpty) return;
      ops.add(HerdrSendTextOp(text.toString()));
      text.clear();
    }

    void addKey(String key) {
      flushText();
      ops.add(HerdrSendKeysOp(<String>[key]));
    }

    while (i < data.length) {
      final code = data.codeUnitAt(i);
      if (code == 0x1b) {
        final parsed = _parseEscape(data, i);
        if (parsed == null) {
          // Lone ESC (or an unknown sequence ending here): Escape key.
          addKey('esc');
          i += 1;
          continue;
        }
        if (parsed.key != null) {
          addKey(parsed.key!);
        } else if (parsed.text != null) {
          // Literal bytes Herdr has no key name for (Alt+char): keep the order
          // around them, they merge with neighbouring text.
          flushText();
          ops.add(HerdrSendTextOp(parsed.text!));
        }
        // A recognised-but-unmapped sequence is consumed and dropped.
        i = parsed.next;
        continue;
      }
      if (code == 0x0d || code == 0x0a) {
        addKey('enter');
        i += 1;
        continue;
      }
      if (code == 0x09) {
        addKey('tab');
        i += 1;
        continue;
      }
      if (code == 0x7f || code == 0x08) {
        addKey('backspace');
        i += 1;
        continue;
      }
      if (code >= 0x01 && code <= 0x1a) {
        // Ctrl-A..Ctrl-Z, except the special cases handled above.
        addKey('ctrl+${String.fromCharCode(0x60 + code)}');
        i += 1;
        continue;
      }
      text.writeCharCode(code);
      i += 1;
    }
    flushText();
    return ops;
  }

  /// Parses one escape sequence starting at [start].
  ///
  /// Returns null when this is a bare ESC, so the caller reports Escape.
  _Escape? _parseEscape(String data, int start) {
    if (start + 1 >= data.length) return null;
    final next = data.codeUnitAt(start + 1);
    // SS3: ESC O A..D (application cursor mode).
    if (next == 0x4f) {
      if (start + 2 >= data.length) return null;
      final finalByte = data.codeUnitAt(start + 2);
      return _Escape(_arrowFor(finalByte), start + 3);
    }
    if (next != 0x5b) {
      // ESC followed by a printable char is Alt+key. Herdr has no Alt verb, but
      // `pane send-text` writes literal bytes, so ESC+char reaches the pane as
      // the same Alt combination a local terminal would send.
      if (next >= 0x20 && next <= 0x7e) {
        return _Escape(null, start + 2, text: '\u001b${data[start + 1]}');
      }
      return _Escape(null, start + 2);
    }
    // CSI: ESC [ params final.
    var i = start + 2;
    final params = StringBuffer();
    while (i < data.length) {
      final code = data.codeUnitAt(i);
      if (code >= 0x40 && code <= 0x7e) {
        final key = _keyForCsi(params.toString(), String.fromCharCode(code));
        return _Escape(key, i + 1);
      }
      params.writeCharCode(code);
      i += 1;
    }
    return _Escape(null, i);
  }

  static String? _arrowFor(int finalByte) {
    switch (finalByte) {
      case 0x41:
        return 'up';
      case 0x42:
        return 'down';
      case 0x43:
        return 'right';
      case 0x44:
        return 'left';
      case 0x48:
        return 'home';
      case 0x46:
        return 'end';
      default:
        return null;
    }
  }

  static String? _keyForCsi(String params, String finalByte) {
    if (finalByte == 'A') return 'up';
    if (finalByte == 'B') return 'down';
    if (finalByte == 'C') return 'right';
    if (finalByte == 'D') return 'left';
    if (finalByte == 'H') return 'home';
    if (finalByte == 'F') return 'end';
    if (finalByte == 'Z') return 'shift+tab';
    if (finalByte == '~') {
      switch (params) {
        case '1':
        case '7':
          return 'home';
        case '2':
          return null; // Insert: Herdr has no key name for it.
        case '3':
          return 'delete';
        case '4':
        case '8':
          return 'end';
        case '5':
          return 'pageup';
        case '6':
          return 'pagedown';
        default:
          return null;
      }
    }
    return null;
  }
}

class _Escape {
  const _Escape(this.key, this.next, {this.text});

  /// Key name, or null when the sequence is recognised but unmapped.
  final String? key;

  /// Literal bytes to type instead of a key press (Alt combinations).
  final String? text;

  /// Index just past the sequence.
  final int next;
}

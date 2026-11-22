// 手机端终端按键栏：Esc、Tab、Ctrl、Alt、方向键和粘贴。
//
// 从远程电脑模块（lib/remote_control/widgets/remote_terminal_pane.dart）的
// 底部按键行移植，并补上 Ctrl/Alt 两个修饰键开关：手机键盘没有它们，
// 而 tmux、vim 和 shell 行编辑都离不开。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// 按键栏。修饰键是粘滞开关：打开后一直生效，再点一次关闭。
///
/// [onKey] 收到的是逻辑键和当前修饰键状态，由调用方交给 xterm 的
/// `Terminal.keyInput`。
class HubTerminalKeyBar extends StatefulWidget {
  const HubTerminalKeyBar({
    super.key,
    required this.onKey,
    required this.onPaste,
    this.enabled = true,
  });

  final void Function(TerminalKey key, {required bool ctrl, required bool alt})
  onKey;

  /// 粘贴文本。按键栏自己从剪贴板取内容。
  final void Function(String text) onPaste;

  final bool enabled;

  @override
  State<HubTerminalKeyBar> createState() => _HubTerminalKeyBarState();
}

class _HubTerminalKeyBarState extends State<HubTerminalKeyBar> {
  bool _ctrl = false;
  bool _alt = false;

  void _key(TerminalKey key) {
    if (!widget.enabled) return;
    widget.onKey(key, ctrl: _ctrl, alt: _alt);
  }

  Future<void> _paste() async {
    if (!widget.enabled) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    widget.onPaste(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('hub-terminal-key-bar'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              _button('Esc', () => _key(TerminalKey.escape), key: 'esc'),
              _button('Tab', () => _key(TerminalKey.tab), key: 'tab'),
              _button(
                'Ctrl',
                () => setState(() => _ctrl = !_ctrl),
                key: 'ctrl',
                active: _ctrl,
              ),
              _button(
                'Alt',
                () => setState(() => _alt = !_alt),
                key: 'alt',
                active: _alt,
              ),
              _button('←', () => _key(TerminalKey.arrowLeft), key: 'left'),
              _button('↑', () => _key(TerminalKey.arrowUp), key: 'up'),
              _button('↓', () => _key(TerminalKey.arrowDown), key: 'down'),
              _button('→', () => _key(TerminalKey.arrowRight), key: 'right'),
              _button('粘贴', _paste, key: 'paste'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(
    String label,
    VoidCallback onTap, {
    required String key,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      key: ValueKey('hub-key-$key'),
      onPressed: widget.enabled ? onTap : null,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: active ? scheme.primary : scheme.onSurfaceVariant,
        backgroundColor: active
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      child: Text(label),
    );
  }
}

// 会话的终端标签：把 hub 的原始字节通道接到 xterm。
//
// 渲染与输入层沿用远程电脑迁入的那一套（vendor/xterm + RemoteTheme 的
// 终端样式），远端与 Herdr 会话因此和手机端远程终端看起来一样。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../remote_control/theme/remote_theme.dart';
import '../harness_host.dart';
import 'hub_terminal_key_bar.dart';

/// 把解码出来的文本交给终端，并在流结束时报告一次。
class _TerminalSink implements Sink<String> {
  _TerminalSink({required this.onText, required this.onDone});

  final void Function(String text) onText;
  final VoidCallback onDone;

  @override
  void add(String data) => onText(data);

  @override
  void close() => onDone();
}

/// 一个 hub 会话的终端视图。
///
/// 通道由 [HarnessSessionHandle.terminal] 提供，本组件只负责字节与 xterm 之间
/// 的搬运，不自己起进程。
class HubTerminalView extends StatefulWidget {
  const HubTerminalView({
    super.key,
    required this.channel,
    this.compact = false,
    this.onClosed,
  });

  final HarnessTerminalChannel channel;

  /// 手机端：底部显示按键栏。
  final bool compact;

  /// 通道结束时的回调（主机报告会话退出）。
  final VoidCallback? onClosed;

  @override
  State<HubTerminalView> createState() => _HubTerminalViewState();
}

class _HubTerminalViewState extends State<HubTerminalView> {
  /// 滚动回看行数上限：终端输出可能很长，界面只保留最近的一段。
  static const int _maxLines = 5000;

  late final Terminal _terminal = Terminal(maxLines: _maxLines);
  StreamSubscription<Uint8List>? _raw;

  /// 当前流的解码器；流结束时由它自己的 sink 关闭，销毁时也要关。
  ByteConversionSink? _decoder;

  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _write;
    _terminal.onResize = _resize;
    _bind(widget.channel);
  }

  void _bind(HarnessTerminalChannel channel) {
    unawaited(_raw?.cancel());
    _raw = null;
    _closeDecoder();
    // 自己拼 UTF-8：被拆在两个数据块里的多字节字符也要能完整解出来，
    // 所以用带状态的 chunked 解码器而不是每块单独 convert。
    final decoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(
          _TerminalSink(
            onText: (text) {
              if (mounted) _terminal.write(text);
            },
            onDone: () => widget.onClosed?.call(),
          ),
        );
    _decoder = decoder;
    _raw = channel.output.listen(
      (bytes) {
        try {
          decoder.add(bytes);
        } on Object catch (error) {
          if (!mounted) return;
          setState(() => _error = '终端输出中断：$error');
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = '终端输出中断：$error');
        widget.onClosed?.call();
      },
      onDone: () {
        _closeDecoder();
      },
      cancelOnError: false,
    );
  }

  /// 关闭当前的解码器；重复调用无副作用。
  ///
  /// 流正常结束时 sink 会收到 close，销毁时则要主动关一次，两边行为一致。
  void _closeDecoder() {
    final decoder = _decoder;
    _decoder = null;
    if (decoder == null) return;
    try {
      decoder.close();
    } on Object {
      // 已经关过了：忽略。
    }
  }

  void _write(String data) {
    try {
      widget.channel.write(utf8.encode(data));
      if (_error != null && mounted) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '输入没有送出去：$error');
    }
  }

  void _resize(int columns, int rows, int pixelWidth, int pixelHeight) {
    try {
      widget.channel.resize(columns, rows);
    } on Object {
      // 通道已经关闭时忽略尺寸变化：界面重建不该把错误顶到用户脸上。
    }
  }

  @override
  void dispose() {
    unawaited(_raw?.cancel());
    _raw = null;
    _closeDecoder();
    if (_terminal.onOutput == _write) _terminal.onOutput = null;
    if (_terminal.onResize == _resize) _terminal.onResize = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: scheme.secondaryContainer,
            child: Text(_error!),
          ),
        Expanded(
          child: TerminalView(
            _terminal,
            key: ObjectKey(_terminal),
            deleteDetection: true,
            textStyle: RemoteTheme.terminalStyle(fontSize: 13),
            padding: const EdgeInsets.all(8),
          ),
        ),
        if (widget.compact)
          HubTerminalKeyBar(
            onKey: (key, {required ctrl, required alt}) =>
                _terminal.keyInput(key, ctrl: ctrl, alt: alt),
            onPaste: _terminal.paste,
          ),
      ],
    );
  }
}

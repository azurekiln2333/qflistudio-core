import 'package:flutter/material.dart';
import '../editor/editor_fonts.dart';

import '../services/api_client.dart';
import '../store/auth_store.dart';

/// Commands run in an isolated, ephemeral session through the business API.
class OnlineTerminalPage extends StatefulWidget {
  const OnlineTerminalPage({super.key, required this.auth});

  final AuthStore auth;

  @override
  State<OnlineTerminalPage> createState() => _OnlineTerminalPageState();
}

class _OnlineTerminalPageState extends State<OnlineTerminalPage> {
  final _outputLines = <_TermLine>[];
  final _inputController = TextEditingController();
  final _listController = ScrollController();
  final _history = <String>[];
  ApiClient _api = ApiClient();
  int _generation = 0;
  bool _running = false;
  bool _resetting = false;
  String? _cwd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _printCwd());
  }

  @override
  void dispose() {
    _generation++;
    _api.close();
    _inputController.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _printCwd() async {
    final generation = _generation;
    final token = widget.auth.token;
    if (token == null) return;
    try {
      final result = await _api.terminalInfo(token);
      if (!mounted || generation != _generation) return;
      setState(() {
        _cwd = result['cwd'] as String? ?? '/workspace';
        _append(
          _TermLine(
            text: '$_cwd · 临时会话 · ${result['workspaceMiB']} MiB',
            kind: _LineKind.info,
          ),
        );
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _append(_TermLine(text: e.message, kind: _LineKind.stderr));
      });
    }
  }

  Future<void> _run(String command) async {
    final trimmed = command.trim();
    final token = widget.auth.token;
    if (trimmed.isEmpty || _running || _resetting || token == null) return;
    final generation = _generation;
    _history.add(trimmed);
    if (_history.length > 100) _history.removeAt(0);
    _inputController.clear();
    setState(() {
      _append(_TermLine(text: '\$ $trimmed', kind: _LineKind.command));
      _running = true;
    });
    _scrollToBottom();
    try {
      final result = await _api.terminalExec(token, trimmed);
      if (!mounted || generation != _generation) return;
      setState(() {
        for (final line in result.stdout.split('\n')) {
          if (line.isNotEmpty) {
            _append(_TermLine(text: line, kind: _LineKind.stdout));
          }
        }
        for (final line in result.stderr.split('\n')) {
          if (line.isNotEmpty) {
            _append(_TermLine(text: line, kind: _LineKind.stderr));
          }
        }
        _append(
          _TermLine(
            text: result.exitCode == 0 ? '（退出码 0）' : '（退出码 ${result.exitCode}）',
            kind: result.exitCode == 0 ? _LineKind.info : _LineKind.stderr,
          ),
        );
        _running = false;
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      // Closing the page-owned client also cancels any request left by a timeout.
      _api.close();
      _api = ApiClient();
      setState(() {
        _append(_TermLine(text: e.message, kind: _LineKind.stderr));
        _running = false;
      });
      _scrollToBottom();
    }
  }

  int _outputCharacters = 0;

  void _append(_TermLine line) {
    _outputLines.add(line);
    _outputCharacters += line.text.length;
    while (_outputLines.length > 2000 || _outputCharacters > 512 * 1024) {
      _outputCharacters -= _outputLines.removeAt(0).text.length;
    }
  }

  void _clearOutput() {
    _outputLines.clear();
    _outputCharacters = 0;
  }

  Future<void> _resetSession() async {
    if (_resetting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置终端会话？'),
        content: const Text('正在运行的命令和终端临时文件将被清除。云项目不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final token = widget.auth.token;
    if (token == null) return;
    final generation = ++_generation;
    _api.close();
    _api = ApiClient();
    setState(() {
      _resetting = true;
      _running = false;
    });
    try {
      await _api.resetTerminal(token);
      if (!mounted || generation != _generation) return;
      setState(() {
        _clearOutput();
        _history.clear();
        _cwd = '/workspace';
        _append(const _TermLine(text: '终端会话已重置', kind: _LineKind.info));
      });
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      _api.close();
      _api = ApiClient();
      setState(
        () => _append(_TermLine(text: e.message, kind: _LineKind.stderr)),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _resetting = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listController.hasClients) {
        _listController.jumpTo(_listController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线终端'),
        actions: [
          IconButton(
            tooltip: '清屏',
            onPressed: () => setState(_clearOutput),
            icon: const Icon(Icons.clear_all),
          ),
          IconButton(
            tooltip: '重置会话',
            onPressed: _resetting ? null : _resetSession,
            icon: const Icon(Icons.restart_alt),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _outputLines.isEmpty
                ? Center(
                    child: Text(
                      _cwd ?? '/workspace',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _listController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _outputLines.length,
                    itemBuilder: (context, i) {
                      final line = _outputLines[i];
                      return SelectableText(
                        line.text,
                        style: TextStyle(
                          fontFamily: EditorFonts.bundledFamily,
                          fontFamilyFallback: EditorFonts.fallbacks,
                          fontSize: 12.5,
                          height: 1.45,
                          color: switch (line.kind) {
                            _LineKind.command => scheme.primary,
                            _LineKind.stderr => scheme.error,
                            _LineKind.info => scheme.onSurfaceVariant,
                            _LineKind.stdout => scheme.onSurface,
                          },
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '~>',
                    style: TextStyle(
                      fontFamily: EditorFonts.bundledFamily,
                      fontSize: 12,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_running && !_resetting,
                      maxLength: 2000,
                      style: const TextStyle(
                        fontFamily: EditorFonts.bundledFamily,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        counterText: '',
                        hintText: _resetting
                            ? '重置中…'
                            : _running
                            ? '执行中…'
                            : '命令',
                        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      onSubmitted: _run,
                    ),
                  ),
                  IconButton(
                    tooltip: '执行',
                    onPressed: _running || _resetting
                        ? null
                        : () => _run(_inputController.text),
                    icon: const Icon(Icons.play_arrow, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LineKind { command, stdout, stderr, info }

class _TermLine {
  const _TermLine({required this.text, required this.kind});

  final String text;
  final _LineKind kind;
}

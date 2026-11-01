/// Progress surface for a cross-app compile/run.
///
/// A sibling app can take 30 s to start its toolchain. The user needs to see
/// real stage lines and real output, and be able to stop the run, so this
/// dialog owns the run's streams from the first accepted event to the exit
/// code. It never shows a success state it was not told about.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'interop_runner.dart';
import 'interop_targets.dart';

/// Shows the running state and returns the real exit code when the user
/// closes it, or null when the platform has no receiver for [language].
Future<int?> showInteropRunDialog({
  required BuildContext context,
  required String projectRoot,
  required String language,
  required String entryFile,
  InteropRunner? runner,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final target = InteropTargets.forLanguage(language);
  if (target == null) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('无法在本机运行'),
        content: Text(InteropTargets.installHint(language)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return null;
  }
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InteropRunDialog(
      runner: runner ?? const InteropRunner(),
      projectRoot: projectRoot,
      language: language,
      entryFile: entryFile,
      timeout: timeout,
    ),
  );
}

/// Dialog body: starts the run once, streams output, and cancels on request.
class InteropRunDialog extends StatefulWidget {
  const InteropRunDialog({
    super.key,
    required this.runner,
    required this.projectRoot,
    required this.language,
    required this.entryFile,
    this.timeout = const Duration(seconds: 60),
  });

  final InteropRunner runner;
  final String projectRoot;
  final String language;
  final String entryFile;
  final Duration timeout;

  @override
  State<InteropRunDialog> createState() => _InteropRunDialogState();
}

class _InteropRunDialogState extends State<InteropRunDialog> {
  final List<String> _lines = <String>[];
  InteropRun? _run;
  StreamSubscription<String>? _out;
  StreamSubscription<String>? _err;
  int? _exitCode;
  bool _started = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    // Starting in initState keeps the dialog from showing an idle frame that
    // the user could interpret as "nothing happened".
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    unawaited(_out?.cancel());
    unawaited(_err?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final run = await widget.runner.run(
      projectRoot: widget.projectRoot,
      language: widget.language,
      entryFile: widget.entryFile,
      timeout: widget.timeout,
    );
    if (!mounted) return;
    setState(() {
      _run = run;
      _lines.addAll(run.diagnostics);
    });
    _out = run.stdout.listen((line) {
      if (!mounted) return;
      setState(() => _lines.add(line));
    });
    _err = run.stderr.listen((line) {
      if (!mounted) return;
      setState(() => _lines.add(line));
    });
    final code = await run.exitCode;
    if (!mounted) return;
    setState(() => _exitCode = code);
  }

  Future<void> _cancel() async {
    final run = _run;
    if (run == null || _exitCode != null || _cancelling) return;
    setState(() => _cancelling = true);
    await run.cancel?.call();
    if (!mounted) return;
    setState(() => _cancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final target = InteropTargets.forLanguage(widget.language);
    // The title names the app the run happens in, so the dialog can never look
    // like a run that stayed inside Studio.
    final app = target?.productName ?? widget.language;
    return AlertDialog(
      title: Text(_exitCode == null ? '正在本机运行 · $app' : '运行结束 · $app'),
      content: SizedBox(
        width: 520,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              target == null
                  ? widget.language
                  : '${target.productName} · ${target.bundleName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    _lines.isEmpty ? '正在连接 $app…' : _lines.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _exitCode == null
                      ? (_cancelling ? '正在停止…' : '运行中')
                      : _exitCode == kInteropNotRunExitCode
                      ? '程序没有运行（退出码 $_exitCode）'
                      : '退出码 $_exitCode',
                ),
                Row(
                  children: <Widget>[
                    if (_exitCode == null)
                      TextButton(
                        onPressed: _cancelling ? null : _cancel,
                        child: const Text('停止'),
                      ),
                    FilledButton(
                      onPressed: _exitCode == null
                          ? null
                          : () => Navigator.of(context).pop(_exitCode),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

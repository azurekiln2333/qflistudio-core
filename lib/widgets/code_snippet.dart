import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../editor/editor_fonts.dart';
import '../editor/retained_editor_host.dart';
import '../i18n/studio_localizations.dart';
import '../models/tutorial.dart';
import '../services/code_import_service.dart';
import '../services/demo_run_service.dart';
import '../services/runner_service.dart';
import '../services/task_activity_service.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';

/// A detail-page code surface whose actions use the currently displayed code.
class CodeSnippet extends StatefulWidget {
  const CodeSnippet({
    super.key,
    required this.example,
    this.controller,
    this.store,
    this.auth,
    this.settings,
  });

  final ExampleCode example;
  final TextEditingController? controller;
  final ProjectStore? store;
  final AuthStore? auth;
  final SettingsStore? settings;

  @override
  State<CodeSnippet> createState() => _CodeSnippetState();
}

class _CodeSnippetState extends State<CodeSnippet> {
  final _codeFocusNode = FocusNode();
  final _codeFieldKey = GlobalKey();
  ScrollPosition? _ancestorScrollPosition;
  bool _visibilityCheckScheduled = false;
  bool _importing = false;

  /// Per-block run controller. Null when the run panel has never been opened.
  _DemoRunController? _runController;
  String get _code => widget.controller?.text ?? widget.example.code;
  bool get _canImport =>
      widget.store != null && widget.auth != null && widget.settings != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _ancestorScrollPosition)) return;
    _ancestorScrollPosition?.removeListener(_scheduleVisibilityCheck);
    _ancestorScrollPosition = position;
    position?.addListener(_scheduleVisibilityCheck);
  }

  void _scheduleVisibilityCheck() {
    if (!_codeFocusNode.hasFocus || _visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted || !_codeFocusNode.hasFocus) return;
      final field = _codeFieldKey.currentContext?.findRenderObject();
      if (field is! RenderBox || !field.attached || !field.hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(field);
      if (viewport == null) return;
      final bounds = MatrixUtils.transformRect(
        field.getTransformTo(viewport),
        Offset.zero & field.size,
      );
      // A retained, unpainted ListView child has a zero paint transform, which
      // produces non-finite bounds instead of an ordinary offscreen rectangle.
      if (!bounds.isFinite || !bounds.overlaps(viewport.paintBounds)) {
        _codeFocusNode.unfocus();
      }
    });
  }

  @override
  void dispose() {
    _ancestorScrollPosition?.removeListener(_scheduleVisibilityCheck);
    _codeFocusNode.dispose();
    _runController?.removeListener(_onRunChanged);
    unawaited(_runController?._disposeAsync() ?? Future<void>.value());
    super.dispose();
  }

  /// Rebuilds the action row (Run button/spinner) whenever the run state
  /// changes, so completion/exit/failure/cancel automatically returns to idle
  /// without any further user interaction.
  void _onRunChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _runDemo() async {
    // Reuse the existing controller so a rerun keeps the inline panel and only
    // one run is active per code block.
    var controller = _runController;
    if (controller == null) {
      controller = _DemoRunController();
      controller.addListener(_onRunChanged);
      _runController = controller;
      setState(() {});
    }
    await controller.run(widget.example.copyWith(code: _code));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = StudioLocalizations.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: EditorFonts.bundledFamily,
      height: 1.5,
      letterSpacing: 0,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.example.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (CodeImportService.isJavaType(widget.example.type))
                  IconButton(
                    tooltip: l10n.runExample,
                    icon: (_runController?.running ?? false)
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_outlined),
                    onPressed: (_runController?.running ?? false)
                        ? null
                        : _runDemo,
                  ),
                IconButton(
                  tooltip: l10n.copyExample,
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: _copy,
                ),
                IconButton(
                  tooltip: l10n.importCodeEditor,
                  icon: const Icon(Icons.edit_note_outlined),
                  onPressed: _canImport && !_importing
                      ? () => _import(intoProject: false)
                      : null,
                ),
                IconButton(
                  tooltip: l10n.importCodeProject,
                  icon: const Icon(Icons.drive_file_move_outlined),
                  onPressed: _canImport && !_importing
                      ? () => _import(intoProject: true)
                      : null,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (widget.controller != null)
            SizedBox(
              height: 360,
              child: TextField(
                key: _codeFieldKey,
                controller: widget.controller,
                focusNode: _codeFocusNode,
                onTapOutside: (_) => _codeFocusNode.unfocus(),
                expands: true,
                minLines: null,
                maxLines: null,
                style: style,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                  hintText: l10n.sampleCode,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                primary: false,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(widget.example.code, style: style),
                ),
              ),
            ),
          // Inline run output lives directly below the code block, in the same
          // page; there is no run dialog, sheet, or editor navigation.
          if (_runController != null)
            _InlineRunPanel(controller: _runController!),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    _codeFocusNode.unfocus();
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(StudioLocalizations.of(context).exampleCopied)),
    );
  }

  Future<void> _import({required bool intoProject}) async {
    if (_importing || !_canImport) return;
    setState(() => _importing = true);
    try {
      final example = widget.example.copyWith(code: _code);
      final result = await showDialog<CodeImportResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CodeImportDialog(
          example: example,
          intoProject: intoProject,
          store: widget.store!,
          auth: widget.auth!,
        ),
      );
      if (result == null || !mounted) return;
      widget.store!.touch(result.project);
      TaskActivityService.report(widget.auth!, 'open_project');
      widget.store!.setBrowsedProject(result.project);
      await openEditorPage(
        context,
        project: result.project,
        auth: widget.auth!,
        store: widget.store!,
        settings: widget.settings!,
        initialOpenPath: result.path,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _CodeImportDialog extends StatefulWidget {
  const _CodeImportDialog({
    required this.example,
    required this.intoProject,
    required this.store,
    required this.auth,
  });

  final ExampleCode example;
  final bool intoProject;
  final ProjectStore store;
  final AuthStore auth;

  @override
  State<_CodeImportDialog> createState() => _CodeImportDialogState();
}

class _CodeImportDialogState extends State<_CodeImportDialog> {
  final _form = GlobalKey<FormState>();
  bool get _isJava => CodeImportService.isJavaType(widget.example.type);
  late final _fileName = TextEditingController(
    text: _isJava
        ? CodeImportService.suggestedClassName(widget.example.code)
        : CodeImportService.suggestedFileName(
            widget.example.type,
            code: widget.example.code,
          ),
  );
  late final _projectName = TextEditingController(
    text: widget.example.title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .trim(),
  );
  String? _projectId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _fileName.dispose();
    _projectName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          widget.intoProject ? l10n.importCodeProject : l10n.importCodeEditor,
        ),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.intoProject) ...[
                    DropdownButtonFormField<String>(
                      key: const ValueKey('import-target-project'),
                      initialValue: _projectId ?? '',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.targetProject,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(l10n.createProject),
                        ),
                        for (final project in widget.store.projects)
                          if (!project.isCloud)
                            DropdownMenuItem(
                              value: project.id,
                              child: Text(
                                project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _projectId = value?.isEmpty == true
                                  ? null
                                  : value;
                              _error = null;
                            }),
                    ),
                    const SizedBox(height: 16),
                    if (_projectId == null) ...[
                      TextFormField(
                        key: const ValueKey('import-project-name'),
                        controller: _projectName,
                        enabled: !_saving,
                        decoration: InputDecoration(
                          labelText: l10n.projectName,
                        ),
                        validator: (value) =>
                            value != null &&
                                CodeImportService.isValidFileName(value)
                            ? null
                            : l10n.invalidProjectName,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                  TextFormField(
                    key: const ValueKey('import-file-name'),
                    controller: _fileName,
                    autofocus: !widget.intoProject,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: _isJava ? l10n.className : l10n.fileName,
                    ),
                    validator: (value) =>
                        value != null &&
                            (_isJava
                                ? _validateJavaClassInput(value)
                                : CodeImportService.isValidFileName(value))
                        ? null
                        : l10n.invalidFileName,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            key: const ValueKey('import-code-confirm'),
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            label: Text(l10n.importAndOpen),
          ),
        ],
      ),
    );
  }

  /// Validates a Java class-name field, tolerating a pasted `.java` suffix.
  bool _validateJavaClassInput(String value) {
    try {
      CodeImportService.normalizeClassNameInput(value);
      return true;
    } on CodeImportException {
      return false;
    }
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final CodeImportResult imported;
      if (!widget.intoProject) {
        final snippet = await CodeImportService.openInEditor(
          example: widget.example,
          fileName: _fileName.text.trim(),
        );
        try {
          final registered = await widget.store.addExisting(
            snippet.project.path,
          );
          if (registered.error != null || registered.project == null) {
            throw FileSystemException(
              registered.error ?? 'Project registration failed',
            );
          }
          imported = (project: registered.project!, path: snippet.path);
        } catch (_) {
          try {
            await Directory(snippet.project.path).delete(recursive: true);
          } on FileSystemException {
            // This directory belongs to the failed import, not an existing project.
          }
          rethrow;
        }
        TaskActivityService.report(widget.auth, 'create_project');
      } else if (_projectId != null) {
        final project = widget.store.projectById(_projectId);
        if (project == null) {
          throw const CodeImportException(CodeImportFailure.projectUnavailable);
        }
        // Resolve the class/file name once so the overwrite pre-check and the
        // write target agree (Java dialog shows the class name; the file is
        // `<Class>.java`).
        final resolved = CodeImportService.resolveImport(
          widget.example,
          _fileName.text.trim(),
        );
        final targets = CodeImportService.destinationPaths(
          project: project,
          example: widget.example,
          fileName: resolved.fileName,
        );
        var overwrite = false;
        final existing = <String>[];
        for (final target in targets) {
          if (await FileSystemEntity.type(target, followLinks: false) ==
              FileSystemEntityType.file) {
            existing.add(p.relative(target, from: project.path));
          }
        }
        if (existing.isNotEmpty) {
          if (!mounted) return;
          overwrite = await _confirmReplacement(existing.join('\n'));
          if (!mounted || !overwrite) return;
        }
        imported = await CodeImportService.importIntoProject(
          project: project,
          example: widget.example,
          fileName: resolved.fileName,
          overwrite: overwrite,
        );
      } else {
        final result = await widget.store.createProjectFromExample(
          name: _projectName.text.trim(),
          example: widget.example,
          fileName: _fileName.text.trim(),
        );
        final project = result.project;
        if (result.error != null || project == null) {
          throw FileSystemException(result.error ?? 'Project creation failed');
        }
        final path = RunnerService.findEntry(project.path);
        if (path == null) {
          throw const CodeImportException(CodeImportFailure.projectUnavailable);
        }
        imported = (project: project, path: path);
        TaskActivityService.report(widget.auth, 'create_project');
      }
      if (!mounted) return;
      // Allow the confirmed result to pop while back/cancel were blocked during I/O.
      setState(() => _saving = false);
      Navigator.of(context).pop(imported);
    } catch (error) {
      if (!mounted) return;
      final l10n = StudioLocalizations.of(context);
      setState(() {
        _saving = false;
        _error = switch (error) {
          CodeImportException(reason: CodeImportFailure.invalidFileName) =>
            l10n.invalidFileName,
          CodeImportException(reason: CodeImportFailure.fileExists) =>
            l10n.fileAlreadyExists,
          CodeImportException(reason: CodeImportFailure.projectUnavailable) =>
            l10n.projectUnavailable,
          CodeImportException(reason: CodeImportFailure.storageUnavailable) =>
            l10n.codeStorageUnavailable,
          FileSystemException() => l10n.codeImportFailed(error.message),
          _ => l10n.codeImportFailed('$error'),
        };
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmReplacement(String fileName) async {
    final l10n = StudioLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.replaceExistingResource),
            content: Text(l10n.replaceResourceMessage(fileName)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.replaceResource),
              ),
            ],
          ),
        ) ??
        false;
  }
}

/// Owns one code block's run lifecycle: streaming stdout/stderr, exit status,
/// cancellation and scratch cleanup. Decoupled from presentation so the inline
/// panel (or a test) can observe the state.
class _DemoRunController extends ChangeNotifier {
  final _stdout = <String>[];
  final _stderr = <String>[];
  DemoRunSession? _session;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;
  int? _exitCode;
  String? _error;
  bool _running = false;
  bool _disposed = false;
  String _title = '';
  String? _hint;

  /// Monotonic run id. Stale async callbacks from an earlier run are ignored so
  /// they cannot overwrite a newer run's state.
  int _generation = 0;

  /// Set when a cancel is requested before the session exists (startup pending).
  bool _cancelRequested = false;

  List<String> get stdout => List.unmodifiable(_stdout);
  List<String> get stderr => List.unmodifiable(_stderr);
  int? get exitCode => _exitCode;
  String? get error => _error;
  String? get hint => _hint;
  String get title => _title;
  bool get running => _running;
  bool get hasResult => _session != null;

  Future<void> run(ExampleCode example) async {
    if (_running || _disposed) return;
    final generation = ++_generation;
    _cancelRequested = false;
    await _clearSession();
    _stdout.clear();
    _stderr.clear();
    _exitCode = null;
    _error = null;
    _title = '';
    _hint = null;
    _running = true;
    _safeNotify();
    try {
      final session = await DemoRunService.start(example);
      if (_disposed || generation != _generation || _cancelRequested) {
        // Disposed or superseded or cancelled during startup: drop this run and
        // clean its scratch files without touching the current run.
        _safeDispose(session);
        if (generation == _generation) {
          _running = false;
          _safeNotify();
        }
        return;
      }
      _session = session;
      final result = session.result;
      _title = result.title;
      _hint = result.hint;
      final stdout = result.stdout;
      final stderr = result.stderr;
      if (stdout != null) {
        _outSub = stdout.listen((line) {
          if (_disposed || generation != _generation) return;
          _stdout.add(line);
          _safeNotify();
        }, onError: (Object error) => _fail(generation, error));
      }
      if (stderr != null) {
        _errSub = stderr.listen((line) {
          if (_disposed || generation != _generation) return;
          _stderr.add(line);
          _safeNotify();
        }, onError: (Object error) => _fail(generation, error));
      }
      final exitCode = result.exitCode;
      if (exitCode != null) {
        // Observe BOTH resolution and rejection. A rejecting exit future (e.g.
        // an OHOS monitor failure) must not strand the spinner or leak an
        // unhandled async error.
        unawaited(
          exitCode.then(
            (code) => _finish(generation, exitCodeValue: code),
            onError: (Object error) => _fail(generation, error),
          ),
        );
      } else {
        // A hint means no local/online runtime could run it; not a live process.
        _finish(generation);
      }
    } on DemoRunFailure catch (failure) {
      _fail(generation, failure.message);
    } catch (error) {
      // U1: a raw throw (filesystem/start preparation) outside DemoRunFailure
      // must still clear the running state.
      _fail(generation, error);
    }
  }

  /// Publishes a successful completion independently of cleanup, then runs
  /// cleanup as best-effort so a cleanup failure can never suppress the rebuild.
  void _finish(int generation, {int? exitCodeValue}) {
    if (_disposed || generation != _generation) return;
    if (exitCodeValue != null) _exitCode = exitCodeValue;
    _running = false;
    _safeNotify();
    // Cleanup must not be able to strand the spinner or surface as an unhandled
    // error; _clearSession already swallows file-system failures.
    unawaited(_clearSession().catchError((Object _) {}));
  }

  /// Publishes an error/failure outcome independently of cleanup.
  void _fail(int generation, Object error) {
    if (_disposed || generation != _generation) return;
    _running = false;
    _error = error is DemoRunFailure ? error.message : '$error';
    _safeNotify();
    unawaited(_clearSession().catchError((Object _) {}));
  }

  /// Cancels stream subscriptions and removes scratch files, swallowing any
  /// file-system error so it is never rethrown from a run callback.
  Future<void> _safeDispose(DemoRunSession session) async {
    try {
      await session.dispose();
    } on Object {
      // Scratch cleanup is best-effort; the OS temp dir will reclaim it.
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    final session = _session;
    if (session != null) {
      _session = null;
      await _safeDispose(session);
    }
    if (!_disposed) {
      _running = false;
      _safeNotify();
    }
  }

  /// Cancels stream subscriptions and removes scratch files. Rendered output
  /// lines are left intact so a finished run keeps showing its result until the
  /// next run replaces it.
  Future<void> _clearSession() async {
    try {
      await _outSub?.cancel();
    } on Object {
      // A stream that fails to cancel must not block session cleanup.
    }
    try {
      await _errSub?.cancel();
    } on Object {
      // See above.
    }
    _outSub = null;
    _errSub = null;
    final session = _session;
    _session = null;
    if (session != null) await _safeDispose(session);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_clearSession());
    super.dispose();
  }

  /// Async-safe disposal for callers that can await cleanup (tests, teardown).
  Future<void> _disposeAsync() async {
    _disposed = true;
    _generation++;
    await _clearSession();
    dispose();
  }
}

/// Renders a code block's run output inline, immediately below the code.
class _InlineRunPanel extends StatefulWidget {
  const _InlineRunPanel({required this.controller});

  final _DemoRunController controller;

  @override
  State<_InlineRunPanel> createState() => _InlineRunPanelState();
}

class _InlineRunPanelState extends State<_InlineRunPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = StudioLocalizations.of(context);
    final controller = widget.controller;
    final mono = TextStyle(
      fontFamily: EditorFonts.bundledFamily,
      fontFamilyFallback: EditorFonts.fallbacks,
      fontSize: 12.5,
      height: 1.45,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Icon(
                Icons.terminal,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  controller.title.isEmpty ? l10n.runExample : controller.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (controller.running)
                IconButton(
                  tooltip: l10n.cancel,
                  icon: const Icon(Icons.stop, size: 18),
                  onPressed: () => unawaited(controller.cancel()),
                ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.running &&
                      controller.stdout.isEmpty &&
                      controller.stderr.isEmpty)
                    Text(l10n.runExample, style: mono),
                  for (final line in controller.stdout)
                    SelectableText(line, style: mono),
                  if (controller.exitCode != null && controller.exitCode != 0)
                    SelectableText(
                      'exit code ${controller.exitCode}',
                      style: mono.copyWith(color: theme.colorScheme.error),
                    ),
                  for (final line in controller.stderr)
                    SelectableText(
                      line,
                      style: mono.copyWith(color: theme.colorScheme.error),
                    ),
                  if (controller.error != null)
                    SelectableText(
                      controller.error!,
                      style: mono.copyWith(color: theme.colorScheme.error),
                    ),
                  if (!controller.running &&
                      controller.stdout.isEmpty &&
                      controller.stderr.isEmpty &&
                      controller.error == null &&
                      controller.hint != null)
                    SelectableText(
                      controller.hint!,
                      style: mono.copyWith(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

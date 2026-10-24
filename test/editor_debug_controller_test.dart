import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_debug_controller.dart';
import 'package:qfli_studio_core/editor/open_file.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

const _capabilities = DebugCapabilities(
  breakpointUpdate: DebugBreakpointUpdate.live,
  outputDelivery: DebugOutputDelivery.live,
  supportsPause: true,
  supportsStepInto: true,
  supportsStepOver: true,
  supportsStepOut: true,
  supportsDocumentSnapshots: true,
  supportsStopOnEntry: true,
  supportsStackFrames: true,
  supportsVariables: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Editor editor;
  late StudioProfile? previousProfile;
  final controllers = <EditorDebugController>[];
  final providers = <_Debugger>[];
  setUp(() {
    root = Directory.systemTemp.createTempSync('qfli_editor_debug_');
    editor = _Editor(
      Project.create(
        name: 'First owner',
        path: root.path,
        type: 'python',
        language: 'Python',
      ),
    );
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'debug-test',
      appTitle: 'Debug test',
      templates: [],
      isOffline: true,
      entryFileNames: ['main.py'],
    );
  });
  tearDown(() async {
    editor.releaseGates();
    for (final provider in providers) {
      provider.releaseLaunch();
      provider.session.releaseGates();
      provider.session.finish();
    }
    for (final controller in controllers) {
      await controller.close();
      controller.dispose();
    }
    controllers.clear();
    providers.clear();
    editor.dispose();
    StudioProfile.current = previousProfile;
    root.deleteSync(recursive: true);
  });

  _Debugger provider({DebugCapabilities capabilities = _capabilities}) {
    final value = _Debugger(capabilities);
    providers.add(value);
    return value;
  }

  EditorDebugController controller([_Debugger? provider]) {
    final value = EditorDebugController(editor: editor, debugger: provider);
    controllers.add(value);
    return value;
  }

  Future<OpenFile> open(
    String name,
    String text, {
    String? owner,
    bool readOnly = false,
  }) async {
    final path = p.join(owner ?? root.path, name);
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(text);
    expect(
      await editor.openPath(
        path,
        ownerProjectPath: owner,
        ownerProjectName: owner == null ? null : 'Second owner',
        ownerProjectType: 'python',
        readOnly: readOnly,
      ),
      isNull,
    );
    return editor.current!;
  }

  test(
    'launch captures active owner, configured entry and exact unsaved buffers',
    () async {
      final foreign = await open('main.py', 'foreign disk');
      foreign.controller.text = 'foreign unsaved';
      final secondRoot = Directory(p.join(root.path, 'second'))..createSync();
      final entry = await open(
        'src/actual.py',
        'entry disk',
        owner: secondRoot.path,
      );
      final active = await open(
        'module.py',
        'saved\r\n',
        owner: secondRoot.path,
      );
      active.controller.text = '😀\r\nunsaved\r\n';
      await ProjectConfig.write(
        projectRoot: secondRoot.path,
        name: 'Second owner',
        language: 'Python',
        type: 'python',
        entryFile: 'src/actual.py',
        strict: true,
      );
      await open(
        'history.py',
        'old snapshot',
        owner: secondRoot.path,
        readOnly: true,
      );
      editor.select(editor.files.indexOf(active));
      final backend = provider();
      final debug = controller(backend);
      await debug.start(stopOnEntry: true);
      final request = backend.requests.single;
      expect(request.projectPath, secondRoot.resolveSymbolicLinksSync());
      expect(
        request.entryFilePath,
        File(entry.path).resolveSymbolicLinksSync(),
      );
      expect(request.language, 'python');
      expect(request.stopOnEntry, isTrue);
      expect(request.documents.map((d) => d.path), [
        File(entry.path).resolveSymbolicLinksSync(),
        File(active.path).resolveSymbolicLinksSync(),
      ]);
      expect(request.documents.last.text, '😀\r\nunsaved\r\n');
      expect(request.documents.last.revision, active.revision);
      expect(() => request.documents.clear(), throwsUnsupportedError);
      expect(File(active.path).readAsStringSync(), 'saved\r\n');
      expect(File(foreign.path).readAsStringSync(), 'foreign disk');
      expect(editor.saved, isEmpty);
      expect(debug.busy, isTrue);
    },
  );

  test(
    'disk-only provider saves only captured owner despite a tab switch',
    () async {
      final active = await open('main.py', 'saved');
      active.controller.text = 'owner unsaved';
      final secondRoot = Directory(p.join(root.path, 'second'))..createSync();
      final foreign = await open(
        'main.py',
        'foreign disk',
        owner: secondRoot.path,
      );
      foreign.controller.text = 'foreign unsaved';
      editor.select(editor.files.indexOf(active));
      final backend = provider(
        capabilities: const DebugCapabilities(
          breakpointUpdate: DebugBreakpointUpdate.launchOnly,
          outputDelivery: DebugOutputDelivery.exitOnly,
        ),
      );
      editor.saveGate = Completer<void>();
      final debug = controller(backend);
      final starting = debug.start();
      expect(debug.starting, isTrue);
      editor.select(editor.files.indexOf(foreign));
      editor.saveGate!.complete();
      await starting;
      expect(
        backend.requests.single.projectPath,
        root.resolveSymbolicLinksSync(),
      );
      expect(backend.requests.single.documents, isEmpty);
      expect(editor.saved, [active.path]);
      expect(File(active.path).readAsStringSync(), 'owner unsaved');
      expect(File(foreign.path).readAsStringSync(), 'foreign disk');
    },
  );

  test(
    'C++ owner headers accept C++ breakpoints and the configured C++ entry',
    () async {
      StudioProfile.current = const StudioProfile(
        id: 'cpp-debug-test',
        appTitle: 'C++ debug test',
        templates: [],
        isOffline: true,
        entryFileNames: ['main.cpp'],
      );
      File(p.join(root.path, 'main.cpp')).writeAsStringSync(
        '#include "local.h"\nint main() { return value(); }\n',
      );
      final header = File(p.join(root.path, 'local.h'))
        ..writeAsStringSync('inline int value() { return 42; }\n');
      expect(
        await editor.openPath(header.path, ownerProjectType: 'cpp'),
        isNull,
      );
      final backend = provider();
      backend.languages = {'cpp'};
      final debug = controller(backend);
      expect(debug.canToggleBreakpoint(editor.current!), isTrue);
      await debug.toggleBreakpoint(editor.current!, 1);
      await debug.start();
      expect(backend.requests.single.language, 'cpp');
      expect(
        backend.requests.single.breakpoints.single.filePath,
        header.resolveSymbolicLinksSync(),
      );
      expect(
        backend.requests.single.entryFilePath,
        File(p.join(root.path, 'main.cpp')).resolveSymbolicLinksSync(),
      );
    },
  );

  test(
    'mid-save edits prevent launch instead of executing stale disk text',
    () async {
      final file = await open('main.py', 'saved');
      file.controller.text = 'first edit';
      final backend = provider(
        capabilities: const DebugCapabilities(
          breakpointUpdate: DebugBreakpointUpdate.launchOnly,
          outputDelivery: DebugOutputDelivery.exitOnly,
        ),
      );
      final debug = controller(backend);
      editor.saveGate = Completer<void>();
      final starting = debug.start();
      file.controller.text = 'changed while saving';
      editor.saveGate!.complete();
      await starting;
      expect(backend.requests, isEmpty);
      expect(debug.busy, isFalse);
      expect(debug.error, contains('发生变化'));
      expect(File(file.path).readAsStringSync(), 'saved');
    },
  );

  test('queued save rechecks physical confinement before writing', () async {
    final file = await open('main.py', 'saved');
    file.controller.text = 'unsaved source';
    final pending = Completer<String?>();
    file.pendingSave = pending.future;
    final backend = provider(
      capabilities: const DebugCapabilities(
        breakpointUpdate: DebugBreakpointUpdate.launchOnly,
        outputDelivery: DebugOutputDelivery.exitOnly,
      ),
    );
    final debug = controller(backend);
    final starting = debug.start();
    await _tick();
    final outside = File(
      p.join(root.parent.path, '${p.basename(root.path)}_queued.py'),
    )..writeAsStringSync('outside source');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });
    File(file.path).deleteSync();
    Link(file.path).createSync(outside.path);
    pending.complete(null);
    await starting;
    expect(backend.requests, isEmpty);
    expect(debug.error, contains('越出'));
    expect(debug.busy, isFalse);
    expect(file.dirty, isTrue);
    expect(outside.readAsStringSync(), 'outside source');
  });

  test(
    'a removed owner cancels queued debugger saves before disk writes',
    () async {
      final file = await open('main.py', 'saved');
      file.controller.text = 'unsaved recovery buffer';
      final pending = Completer<String?>();
      file.pendingSave = pending.future;
      final backend = provider(
        capabilities: const DebugCapabilities(
          breakpointUpdate: DebugBreakpointUpdate.launchOnly,
          outputDelivery: DebugOutputDelivery.exitOnly,
        ),
      );
      var available = true;
      final debug = EditorDebugController(
        editor: editor,
        debugger: backend,
        isFileAvailable: (_) => available,
      );
      controllers.add(debug);
      final starting = debug.start();
      await _tick();
      available = false;
      pending.complete(null);
      await starting;
      expect(backend.requests, isEmpty);
      expect(debug.busy, isFalse);
      expect(file.dirty, isTrue);
      expect(File(file.path).readAsStringSync(), 'saved');
      expect(debug.canToggleBreakpoint(file), isFalse);
    },
  );

  test(
    'a rejected save guard reports cancellation and retains dirty text',
    () async {
      final file = await open('main.py', 'saved');
      file.controller.text = 'unsaved source';
      final result = await editor.saveFile(file, shouldSave: () => false);
      expect(result, contains('取消'));
      expect(file.dirty, isTrue);
      expect(File(file.path).readAsStringSync(), 'saved');
    },
  );

  test(
    'missing providers, read-only files, foreign paths and languages never launch',
    () async {
      final file = await open('main.py', 'print(1)');
      final absent = controller();
      await absent.start();
      expect(absent.error, contains('未安装'));
      final backend = provider();
      final debug = controller(backend);
      final history = await open('history.py', 'old', readOnly: true);
      await debug.start();
      expect(debug.error, contains('可编辑'));
      editor.closeAt(editor.files.indexOf(history));
      await open('notes.txt', 'unsupported');
      await debug.start();
      expect(debug.error, contains('不支持'));
      final foreignRoot = Directory(p.join(root.path, 'foreign'))..createSync();
      final misleading = OpenFile(
        path: file.path,
        content: 'text',
        highlightTheme: null,
        projectRootPath: foreignRoot.path,
        projectType: 'python',
      );
      editor.files.add(misleading);
      editor.select(editor.files.length - 1);
      await debug.start();
      expect(debug.error, contains('越出'));
      expect(backend.requests, isEmpty);
      expect(debug.busy, isFalse);
    },
  );

  test(
    'physical symlink escapes are rejected for configured and default entries',
    () async {
      final active = await open('module.py', 'local');
      final outside = File(
        p.join(root.parent.path, '${p.basename(root.path)}_outside.py'),
      )..writeAsStringSync('private');
      addTearDown(() {
        if (outside.existsSync()) outside.deleteSync();
      });
      final link = Link(p.join(root.path, 'main.py'));
      link.createSync(outside.path);
      final backend = provider();
      final debug = controller(backend);
      editor.select(editor.files.indexOf(active));
      await debug.start();
      expect(debug.error, contains('越出'));
      expect(backend.requests, isEmpty);
    },
  );

  test(
    'duplicate aliases and bounded source capture reject before provider launch',
    () async {
      final file = await open('main.py', 'pass');
      final backend = provider();
      final debug = controller(backend);
      final duplicate = OpenFile(
        path: file.path,
        content: 'pass',
        highlightTheme: null,
        projectRootPath: root.path,
        projectType: 'python',
      );
      editor.files.add(duplicate);
      await debug.start();
      expect(debug.error, contains('重复'));
      editor.closeAt(editor.files.indexOf(duplicate));
      file.controller.text = 'x' * (EditorDebugController.maxSourceUnits + 1);
      await debug.start();
      expect(debug.error, contains('超出'));
      expect(backend.requests, isEmpty);
    },
  );

  test(
    'subscribes before getter; stale revisions/session IDs cannot replace output',
    () async {
      final file = await open('main.py', 'pass');
      final backend = provider();
      backend.session.onRead = () {
        backend.session.onRead = null;
        expect(backend.session.events.hasListener, isTrue);
        backend.session.pause(file.path, generation: 1, stdout: 'rolling tail');
      };
      final debug = controller(backend);
      await debug.start();
      expect(debug.snapshot!.phase, DebugPhase.paused);
      expect(debug.snapshot!.stdout, 'rolling tail');
      final revision = debug.snapshot!.revision;
      backend.session.emit(
        DebugSnapshot(
          sessionId: 'foreign',
          revision: 999,
          phase: DebugPhase.running,
          stdout: 'foreign output',
        ),
      );
      backend.session.emit(
        DebugSnapshot(
          sessionId: backend.session.id,
          revision: revision,
          phase: DebugPhase.running,
          stdout: 'stale output',
        ),
      );
      expect(debug.snapshot!.stdout, 'rolling tail');
      backend.session.emit(
        DebugSnapshot(
          sessionId: backend.session.id,
          revision: revision + 1,
          phase: DebugPhase.running,
          stdout: 'tail',
        ),
      );
      expect(debug.snapshot!.stdout, 'tail');
      expect(debug.selectedFrame, isNull);
      backend.session.emit(
        DebugSnapshot(
          sessionId: backend.session.id,
          revision: revision + 2,
          phase: DebugPhase.terminated,
          stdout: 'final',
        ),
      );
      backend.session.emit(
        DebugSnapshot(
          sessionId: backend.session.id,
          revision: revision + 3,
          phase: DebugPhase.running,
          stdout: 'late running',
        ),
      );
      expect(debug.snapshot!.stdout, 'final');
      expect(
        debug.busy,
        isTrue,
        reason: 'A terminal snapshot does not prove disposal',
      );
    },
  );

  test(
    'stop bypasses pending commands and busy lasts through done AND disposal',
    () async {
      final file = await open('main.py', 'pass');
      final backend = provider();
      backend.session.pause(file.path, generation: 1);
      backend.session.commandGate = Completer<void>();
      backend.session.disposeGate = Completer<void>();
      final debug = controller(backend);
      await debug.start();
      backend.session.onCommand = (command) {
        if (command == DebugCommand.resume) backend.session.running();
      };
      final resuming = debug.command(DebugCommand.resume);
      expect(debug.canCommand(DebugCommand.pause), isTrue);
      final pausing = debug.command(DebugCommand.pause);
      expect(backend.session.commands.map((c) => c.$1), [
        DebugCommand.resume,
        DebugCommand.pause,
      ]);
      var stopped = false;
      final stopping = debug.stop().then((_) => stopped = true);
      expect(backend.session.stopCalls, 1);
      expect(debug.stopping, isTrue);
      await debug.start();
      expect(backend.requests, hasLength(1));
      await _tick();
      expect(stopped, isFalse);
      backend.session.finish(exitCode: null);
      await _tick();
      expect(debug.busy, isTrue);
      expect(backend.session.disposeCalls, 1);
      backend.session.disposeGate!.complete();
      await stopping;
      expect(debug.busy, isFalse);
      expect(debug.snapshot!.exitCode, isNull);
      backend.session.commandGate!.complete();
      await Future.wait([resuming, pausing]);
    },
  );

  test(
    'dispose during launch stops returned worker without late notifications',
    () async {
      await open('main.py', 'pass');
      final backend = provider()..launchGate = Completer<void>();
      final debug = controller(backend);
      var notifications = 0;
      debug.addListener(() => notifications++);
      final starting = debug.start();
      debug.dispose();
      final before = notifications;
      backend.releaseLaunch();
      await starting;
      expect(backend.session.stopCalls, 1);
      expect(debug.busy, isTrue);
      backend.session.finish();
      await debug.close();
      expect(debug.busy, isFalse);
      expect(notifications, before);
      expect(backend.session.disposeCalls, 1);
    },
  );

  test(
    'cleanup failure retains lane and a later stop retries disposal',
    () async {
      await open('main.py', 'pass');
      final backend = provider();
      final debug = controller(backend);
      await debug.start();
      backend.session.disposeFailures = 1;
      backend.session.finish();
      await _tick();
      expect(debug.busy, isTrue);
      expect(debug.error, contains('清理尚未完成'));
      await debug.stop();
      expect(backend.session.disposeCalls, 2);
      expect(debug.busy, isFalse);
    },
  );

  test(
    'close retries transient disposal failure after the page is gone',
    () async {
      await open('main.py', 'pass');
      final backend = provider();
      final debug = controller(backend);
      await debug.start();
      backend.session.disposeFailures = 1;
      debug.dispose();
      backend.session.finish();
      await debug.close();
      expect(backend.session.disposeCalls, 2);
      expect(debug.busy, isFalse);
    },
  );

  test(
    'close bounds disposal retries and repeated close retries retained cleanup',
    () async {
      await open('main.py', 'pass');
      final backend = provider();
      final debug = controller(backend);
      await debug.start();
      backend.session.disposeFailures = 3;
      final exhausted = Completer<void>();
      backend.session.onDispose = () {
        if (backend.session.disposeCalls == 3) exhausted.complete();
      };
      var closed = false;
      final closing = debug.close();
      unawaited(closing.then((_) => closed = true));
      backend.session.finish();
      await exhausted.future;
      await _tick();
      expect(debug.busy, isTrue);
      expect(closed, isFalse);
      expect(debug.error, contains('自动重试已用尽'));
      final retry = debug.close();
      expect(identical(retry, closing), isTrue);
      await retry;
      expect(backend.session.disposeCalls, 4);
      expect(debug.busy, isFalse);
    },
  );

  test(
    'launch-only breakpoints stay pending until truthful backend verification',
    () async {
      final file = await open('main.py', 'one\ntwo\nthree');
      final backend = provider(
        capabilities: const DebugCapabilities(
          breakpointUpdate: DebugBreakpointUpdate.launchOnly,
          outputDelivery: DebugOutputDelivery.exitOnly,
          supportsDocumentSnapshots: true,
        ),
      );
      final debug = controller(backend);
      await debug.toggleBreakpoint(file, 2);
      expect(
        debug.breakpointFor(file.path, 2)!.status,
        DebugBreakpointStatus.pending,
      );
      await debug.start();
      expect(backend.requests.single.breakpoints.single.line, 2);
      expect(debug.canToggleBreakpoint(file), isFalse);
      await debug.toggleBreakpoint(file, 1);
      expect(backend.session.breakpointCalls, isEmpty);
      expect(debug.breakpoints.single.line, 2);
    },
  );

  test(
    'finished-session breakpoint updates cannot block or overwrite new requests',
    () async {
      final file = await open('main.py', 'one\ntwo\nthree');
      final backend = provider();
      final debug = controller(backend);
      await debug.start();
      backend.session.breakpointGate = Completer<void>();
      final updating = debug.toggleBreakpoint(file, 1);
      expect(debug.canToggleBreakpoint(file), isFalse);
      expect(
        () => backend.session.breakpointCalls.single.clear(),
        throwsUnsupportedError,
      );
      final stopping = debug.stop();
      backend.session.finish();
      await stopping;
      expect(debug.canToggleBreakpoint(file), isTrue);
      await debug.toggleBreakpoint(file, 2);
      expect(debug.breakpoints.single.line, 2);
      backend.session.breakpointGate!.complete();
      await updating;
      expect(debug.breakpoints.single.line, 2);
    },
  );

  test(
    'pending breakpoint replacement preserves the pause until commands are safe',
    () async {
      final file = await open('main.py', 'one\ntwo');
      final backend = provider();
      backend.session.pause(file.path, generation: 1);
      final debug = controller(backend);
      await debug.start();
      final token = debug.snapshot!.pauseToken;
      backend.session.breakpointGate = Completer<void>();
      final updating = debug.toggleBreakpoint(file, 2);
      for (final command in [
        DebugCommand.resume,
        DebugCommand.stepInto,
        DebugCommand.stepOver,
        DebugCommand.stepOut,
      ]) {
        expect(debug.canCommand(command), isFalse);
        await debug.command(command);
      }
      expect(backend.session.commands, isEmpty);
      expect(debug.paused, isTrue);
      expect(debug.snapshot!.pauseToken, token);

      backend.session.breakpointGate!.complete();
      await updating;
      expect(debug.canCommand(DebugCommand.resume), isTrue);
      expect(debug.canCommand(DebugCommand.stepInto), isTrue);
      expect(debug.canCommand(DebugCommand.stepOver), isTrue);
      expect(debug.canCommand(DebugCommand.stepOut), isTrue);
      await debug.command(DebugCommand.resume);
      expect(backend.session.commands.single.$2, token);
      expect(debug.error, isNull);
    },
  );

  test(
    'capabilities, selected thread and consumed pause tokens gate commands',
    () async {
      final file = await open('main.py', 'pass');
      final backend = provider(
        capabilities: const DebugCapabilities(
          breakpointUpdate: DebugBreakpointUpdate.paused,
          outputDelivery: DebugOutputDelivery.pauseOrExit,
          supportsDocumentSnapshots: true,
          supportsStepInto: true,
          supportsStackFrames: true,
        ),
      );
      final debug = controller(backend);
      await debug.start(stopOnEntry: true);
      expect(backend.requests, isEmpty);
      expect(debug.error, contains('入口暂停'));
      backend.session.pause(file.path, generation: 1);
      await debug.start();
      final oldFrame = debug.selectedFrame!;
      expect(debug.canCommand(DebugCommand.stepOver), isFalse);
      expect(debug.canCommand(DebugCommand.pause), isFalse);
      expect(debug.canToggleBreakpoint(file), isTrue);
      await debug.toggleBreakpoint(file, 1);
      expect(backend.session.breakpointCalls.single.single.line, 1);
      expect(
        debug.breakpointFor(file.path, 1)!.status,
        DebugBreakpointStatus.verified,
      );
      await debug.command(DebugCommand.stepInto);
      expect(
        backend.session.commands.single.$2,
        const DebugPauseToken(sessionId: 'test-session', generation: 1),
      );
      expect(backend.session.commands.single.$3, 'worker');
      expect(debug.canCommand(DebugCommand.resume), isFalse);
      debug.selectFrame(oldFrame);
      expect(debug.selectedFrame, isNull);
      backend.session.pause(file.path, generation: 2);
      expect(debug.canCommand(DebugCommand.resume), isTrue);
      debug.selectFrame(oldFrame);
      expect(debug.selectedFrame, isNot(same(oldFrame)));
    },
  );

  test(
    'execution location requires a valid pause and exact launch source owner',
    () async {
      final file = await open('main.py', 'saved\nsource');
      file.controller.text = 'unsaved\nsource';
      final backend = provider();
      backend.session.pause(file.path, generation: 1, line: 2);
      final debug = controller(backend);
      await debug.start();
      expect(debug.paused, isTrue);
      expect(debug.executionLocationFor(file)?.line, 2);
      expect(file.dirty, isTrue);
      file.controller.text = 'changed\nsource';
      expect(debug.executionLocationFor(file), isNull);
      file.controller.text = 'unsaved\nsource';
      expect(debug.executionLocationFor(file)?.line, 2);

      final foreignRoot = Directory(p.join(root.path, 'foreign'))..createSync();
      final foreignOwner = OpenFile(
        path: file.path,
        content: file.controller.text,
        highlightTheme: null,
        projectRootPath: foreignRoot.path,
        projectType: 'python',
      );
      editor.files.add(foreignOwner);
      expect(debug.executionLocationFor(foreignOwner), isNull);
      final readOnly = OpenFile(
        path: file.path,
        content: file.controller.text,
        highlightTheme: null,
        projectRootPath: root.path,
        projectType: 'python',
        readOnly: true,
      );
      editor.files.add(readOnly);
      expect(debug.executionLocationFor(readOnly), isNull);
      final module = await open('module.py', 'module');
      backend.session.pause(module.path, generation: 2);
      expect(debug.executionLocationFor(module), isNull);
      backend.session.pause(file.path, generation: 3, line: 2);
      expect(debug.executionLocationFor(file)?.line, 2);

      backend.session.commandGate = Completer<void>();
      final resuming = debug.command(DebugCommand.resume);
      expect(debug.snapshot!.phase, DebugPhase.paused);
      expect(debug.paused, isFalse);
      expect(debug.executionLocationFor(file), isNull);
      backend.session.commandGate!.complete();
      await resuming;
      expect(debug.paused, isFalse);
      backend.session.pause(file.path, generation: 4, line: 2);
      expect(debug.executionLocationFor(file)?.line, 2);
      final stopping = debug.stop();
      expect(debug.paused, isFalse);
      expect(debug.executionLocationFor(file), isNull);
      backend.session.finish();
      await stopping;
    },
  );

  test(
    'navigation expands physical folded lines and preserves captured ownership',
    () async {
      const source = 'def f():\r\n  first\r\n  second\r\n  third\r\nend';
      final file = await open('main.py', source);
      file.controller.collapseChunk(0, 3);
      expect(file.controller.codeLines.length, lessThan(5));
      final backend = provider();
      backend.session.pause(file.path, generation: 1, line: 3, column: 3);
      final debug = controller(backend);
      await debug.start();
      final foreignRoot = Directory(p.join(root.path, 'second'))..createSync();
      await open('foreign.py', 'foreign', owner: foreignRoot.path);
      await debug.navigate(debug.selectedFrame!);
      expect(editor.current, same(file));
      expect(file.controller.selection.baseIndex, 2);
      expect(file.controller.selection.baseOffset, 2);
      expect(file.controller.text, source);
      expect(File(file.path).readAsStringSync(), source);
    },
  );

  test(
    'guarded open leaves existing and pending disk tabs inactive when stale',
    () async {
      final first = await open('main.py', 'entry');
      final second = await open('module.py', 'module');
      final plainEditor = EditorController(project: editor.project);
      addTearDown(plainEditor.dispose);
      expect(await plainEditor.openPath(first.path), isNull);
      final selected = plainEditor.current;
      expect(await plainEditor.openPath(second.path), isNull);
      plainEditor.select(0);
      expect(
        await plainEditor.openPath(second.path, shouldOpen: () => false),
        isNull,
      );
      expect(plainEditor.current, same(selected));

      final pending = File(p.join(root.path, 'pending.py'))
        ..writeAsStringSync('new module');
      var current = true;
      final opening = plainEditor.openPath(
        pending.path,
        shouldOpen: () => current,
      );
      current = false;
      expect(await opening, isNull);
      expect(plainEditor.files, hasLength(2));
      expect(plainEditor.current, same(selected));
    },
  );

  test(
    'Stop remains independent of a pending paused breakpoint replacement',
    () async {
      final file = await open('main.py', 'one\ntwo');
      final backend = provider();
      backend.session.pause(file.path, generation: 1);
      final debug = controller(backend);
      await debug.start();
      backend.session.breakpointGate = Completer<void>();
      final updating = debug.toggleBreakpoint(file, 2);
      final stopping = debug.stop();
      expect(backend.session.stopCalls, 1);
      expect(debug.stopping, isTrue);
      backend.session.finish();
      await stopping;
      expect(debug.busy, isFalse);
      backend.session.breakpointGate!.complete();
      await updating;
    },
  );

  test(
    'navigation rechecks pause after await and refuses foreign/changed source',
    () async {
      final file = await open('main.py', 'one\ntwo\nthree');
      final path = p.join(root.path, 'module.py');
      File(path).writeAsStringSync('first\nsecond\nthird');
      final backend = provider();
      backend.session.pause(path, generation: 1, line: 3);
      final debug = controller(backend);
      await debug.start();
      editor.openGate = Completer<void>();
      final navigation = debug.navigate(debug.selectedFrame!);
      backend.session.pause(file.path, generation: 2);
      editor.openGate!.complete();
      await navigation;
      expect(editor.files.any((f) => f.path == path), isFalse);
      expect(editor.current, same(file));
      expect(debug.error, isNull);
      file.controller.text = 'changed\nsource';
      await debug.navigate(debug.selectedFrame!);
      expect(debug.error, contains('源文件已改变'));
      final foreignRoot = Directory(p.join(root.path, 'outside-owner'))
        ..createSync();
      final outside = File(p.join(foreignRoot.path, 'outside.py'))
        ..writeAsStringSync('secret');
      // Its physical path is project-local, but an already-open foreign owner
      // must not be relabelled or used as the session's source.
      await editor.openPath(
        outside.path,
        ownerProjectPath: foreignRoot.path,
        ownerProjectType: 'python',
      );
      backend.session.pause(outside.path, generation: 3);
      await debug.navigate(debug.selectedFrame!);
      expect(debug.error, contains('其他项目'));
    },
  );

  for (final action in ['selection', 'navigation']) {
    test(
      'new frame $action cancels older navigation within the same pause',
      () async {
        final file = await open('main.py', 'one\ntwo\nthree');
        final path = p.join(root.path, 'module.py');
        final pendingSource = File(path)..writeAsStringSync('module');
        final first = DebugFrame(
          id: 'pending',
          threadId: 'worker',
          name: 'pending source',
          location: DebugSourceLocation(filePath: path, line: 1),
        );
        final second = DebugFrame(
          id: 'existing',
          threadId: 'worker',
          name: 'existing source',
          location: DebugSourceLocation(filePath: file.path, line: 2),
        );
        final backend = provider();
        backend.session.pause(path, generation: 1, frames: [first, second]);
        final debug = controller(backend);
        await debug.start();
        final token = debug.snapshot!.pauseToken;
        editor.openGate = Completer<void>();
        final navigation = debug.navigate(first);
        if (action == 'selection') {
          debug.selectFrame(second);
        } else {
          await debug.navigate(second);
          expect(file.controller.selection.baseIndex, 1);
        }
        pendingSource.deleteSync();
        editor.openGate!.complete();
        await navigation;
        expect(debug.snapshot!.pauseToken, token);
        expect(editor.files, [file]);
        expect(editor.current, same(file));
        expect(debug.error, isNull);
        if (action == 'selection') {
          expect(debug.selectedFrame, same(second));
        }
      },
    );
  }

  for (final removal in ['before', 'during']) {
    test(
      'a clean closed source stays closed when its owner leaves $removal navigation',
      () async {
        final file = await open('main.py', 'one\ntwo');
        final path = file.path;
        final backend = provider();
        backend.session.pause(path, generation: 1, line: 2);
        var available = true;
        final debug = EditorDebugController(
          editor: editor,
          debugger: backend,
          isProjectAvailable: (owner) =>
              p.equals(owner, root.path) && available,
        );
        controllers.add(debug);
        await debug.start();
        final frame = debug.selectedFrame!;
        editor.closeAt(editor.files.indexOf(file));
        expect(editor.files, isEmpty);
        available = removal == 'during';
        editor.openGate = Completer<void>();
        final navigation = debug.navigate(frame);
        available = false;
        editor.openGate!.complete();
        await navigation;
        expect(editor.files, isEmpty);
        expect(editor.current, isNull);
        expect(File(path).readAsStringSync(), 'one\ntwo');
        expect(debug.error, isNull);
        expect(backend.requests, hasLength(1));
      },
    );
  }

  for (final action in ['resume', 'stop', 'close']) {
    test(
      'pending navigation cannot open or activate a tab after $action',
      () async {
        final file = await open('main.py', 'entry');
        final path = p.join(root.path, 'module.py');
        File(path).writeAsStringSync('module');
        final backend = provider();
        backend.session.pause(path, generation: 1);
        final debug = controller(backend);
        await debug.start();
        editor.openGate = Completer<void>();
        final navigation = debug.navigate(debug.selectedFrame!);
        if (action == 'resume') {
          backend.session.onCommand = (_) => backend.session.running();
          await debug.command(DebugCommand.resume);
        } else {
          final stopping = action == 'close' ? debug.close() : debug.stop();
          backend.session.finish();
          await stopping;
        }
        editor.openGate!.complete();
        await navigation;
        expect(editor.files.any((f) => f.path == path), isFalse);
        expect(editor.current, same(file));
        expect(debug.error, isNull);
      },
    );
  }

  test(
    'stop during source preparation cancels launch before saving more buffers',
    () async {
      await open('main.py', 'entry');
      await open('module.py', 'module');
      final backend = provider(
        capabilities: const DebugCapabilities(
          breakpointUpdate: DebugBreakpointUpdate.launchOnly,
          outputDelivery: DebugOutputDelivery.exitOnly,
        ),
      );
      final debug = controller(backend);
      editor.saveGate = Completer<void>();
      final starting = debug.start();
      final stopping = debug.stop();
      expect(debug.busy, isTrue);
      editor.saveGate!.complete();
      await Future.wait([starting, stopping]);
      expect(editor.saved, hasLength(1));
      expect(backend.requests, isEmpty);
      expect(debug.busy, isFalse);
    },
  );

  test(
    'new owner buffers during a save require a fresh bounded capture',
    () async {
      await open('main.py', 'entry');
      final backend = provider(
        capabilities: const DebugCapabilities(
          breakpointUpdate: DebugBreakpointUpdate.launchOnly,
          outputDelivery: DebugOutputDelivery.exitOnly,
        ),
      );
      final debug = controller(backend);
      editor.saveGate = Completer<void>();
      final starting = debug.start();
      final module = await open('new.py', 'disk');
      module.controller.text = 'unsaved imported module';
      editor.saveGate!.complete();
      await starting;
      expect(backend.requests, isEmpty);
      expect(debug.error, contains('打开的项目文件发生变化'));
      expect(debug.busy, isFalse);
    },
  );

  test(
    'stale foreign tabs do not prevent navigating current project source',
    () async {
      final foreignRoot = Directory(p.join(root.path, 'foreign'))..createSync();
      final stale = await open('stale.py', 'old', owner: foreignRoot.path);
      final file = await open('main.py', 'one\ntwo');
      File(stale.path).deleteSync();
      final backend = provider();
      backend.session.pause(file.path, generation: 1, line: 2);
      final debug = controller(backend);
      await debug.start();
      await debug.navigate(debug.selectedFrame!);
      expect(debug.error, isNull);
      expect(file.controller.selection.baseIndex, 1);
    },
  );

  test(
    'launch failures release preparation lane and expose the real reason',
    () async {
      await open('main.py', 'pass');
      final backend = provider()
        ..launchError = StateError('native library unavailable');
      final debug = controller(backend);
      await debug.start();
      expect(debug.busy, isFalse);
      expect(debug.error, contains('native library unavailable'));
      expect(debug.snapshot, isNull);
    },
  );
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

class _Editor extends EditorController {
  _Editor(Project project) : super(project: project);
  Completer<void>? saveGate;
  Completer<void>? openGate;
  final saved = <String>[];

  void releaseGates() {
    if (saveGate != null && !saveGate!.isCompleted) saveGate!.complete();
    if (openGate != null && !openGate!.isCompleted) openGate!.complete();
  }

  @override
  Future<String?> saveFile(
    OpenFile open, {
    bool backup = false,
    List<int>? bytes,
    bool Function()? shouldSave,
  }) async {
    saved.add(open.path);
    await saveGate?.future;
    return super.saveFile(
      open,
      backup: backup,
      bytes: bytes,
      shouldSave: shouldSave,
    );
  }

  @override
  Future<String?> openPath(
    String path, {
    String? ownerProjectName,
    String? ownerProjectPath,
    String? ownerProjectType,
    bool readOnly = false,
    String? timeLabel,
    FileCursor? cursor,
    bool Function()? shouldOpen,
  }) async {
    await openGate?.future;
    return super.openPath(
      path,
      ownerProjectName: ownerProjectName,
      ownerProjectPath: ownerProjectPath,
      ownerProjectType: ownerProjectType,
      readOnly: readOnly,
      timeLabel: timeLabel,
      cursor: cursor,
      shouldOpen: shouldOpen,
    );
  }
}

class _Debugger implements StudioDebugger {
  _Debugger(this.capabilities);
  @override
  final DebugCapabilities capabilities;
  @override
  String get displayName => 'Test debugger';
  final session = _Session();
  final requests = <DebugLaunchRequest>[];
  Completer<void>? launchGate;
  Object? launchError;
  Set<String> languages = {'python'};
  @override
  bool supportsLanguage(String language) => languages.contains(language);
  void releaseLaunch() {
    if (launchGate != null && !launchGate!.isCompleted) launchGate!.complete();
  }

  @override
  Future<DebugSession> launch(DebugLaunchRequest request) async {
    requests.add(request);
    await launchGate?.future;
    if (launchError != null) throw launchError!;
    return session;
  }
}

class _Session implements DebugSession {
  @override
  String get id => 'test-session';
  final events = StreamController<DebugSnapshot>.broadcast(sync: true);
  final completion = Completer<void>();
  var state = DebugSnapshot(
    sessionId: 'test-session',
    revision: 0,
    phase: DebugPhase.running,
  );
  void Function()? onRead;
  void Function(DebugCommand)? onCommand;
  final commands = <(DebugCommand, DebugPauseToken?, String?)>[];
  final breakpointCalls = <List<DebugBreakpoint>>[];
  Completer<void>? commandGate;
  Completer<void>? breakpointGate;
  Completer<void>? disposeGate;
  int stopCalls = 0;
  int disposeCalls = 0;
  int disposeFailures = 0;
  void Function()? onDispose;

  @override
  DebugSnapshot get snapshot {
    final before = state;
    onRead?.call();
    return before;
  }

  @override
  Stream<DebugSnapshot> get updates => events.stream;
  @override
  Future<void> get done => completion.future;
  void emit(DebugSnapshot value) {
    state = value;
    if (!events.isClosed) events.add(value);
  }

  void running() => emit(
    DebugSnapshot(
      sessionId: id,
      revision: state.revision + 1,
      phase: DebugPhase.running,
    ),
  );
  void pause(
    String path, {
    required int generation,
    int line = 1,
    int? column,
    String stdout = '',
    List<DebugFrame>? frames,
  }) => emit(
    DebugSnapshot(
      sessionId: id,
      revision: state.revision + 1,
      phase: DebugPhase.paused,
      pauseToken: DebugPauseToken(sessionId: id, generation: generation),
      threads: [
        const DebugThread(id: 'worker', name: 'Worker', isPaused: true),
      ],
      frames:
          frames ??
          [
            DebugFrame(
              id: 'frame',
              threadId: 'worker',
              name: 'f',
              location: DebugSourceLocation(
                filePath: path,
                line: line,
                column: column,
              ),
            ),
          ],
      stdout: stdout,
      breakpoints: state.breakpoints,
    ),
  );
  void finish({int? exitCode = 0}) {
    if (completion.isCompleted) return;
    emit(
      DebugSnapshot(
        sessionId: id,
        revision: state.revision + 1,
        phase: DebugPhase.terminated,
        exitCode: exitCode,
      ),
    );
    completion.complete();
  }

  void releaseGates() {
    if (commandGate != null && !commandGate!.isCompleted) {
      commandGate!.complete();
    }
    if (breakpointGate != null && !breakpointGate!.isCompleted) {
      breakpointGate!.complete();
    }
    if (disposeGate != null && !disposeGate!.isCompleted) {
      disposeGate!.complete();
    }
  }

  @override
  Future<List<DebugBreakpointResult>> setBreakpoints(
    List<DebugBreakpoint> points,
  ) async {
    breakpointCalls.add(points);
    await breakpointGate?.future;
    final results = [
      for (final point in points)
        DebugBreakpointResult(
          requested: point,
          status: DebugBreakpointStatus.verified,
          actualLocation: DebugSourceLocation(
            filePath: point.filePath,
            line: point.line,
          ),
        ),
    ];
    emit(
      DebugSnapshot(
        sessionId: id,
        revision: state.revision + 1,
        phase: state.phase,
        pauseToken: state.pauseToken,
        threads: state.threads,
        frames: state.frames,
        breakpoints: results,
      ),
    );
    return results;
  }

  @override
  Future<void> command(
    DebugCommand command, {
    DebugPauseToken? pauseToken,
    String? threadId,
  }) async {
    commands.add((command, pauseToken, threadId));
    onCommand?.call(command);
    await commandGate?.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await done;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    onDispose?.call();
    if (disposeFailures > 0) {
      disposeFailures--;
      throw StateError('cleanup failure');
    }
    await done;
    await disposeGate?.future;
    await events.close();
  }
}

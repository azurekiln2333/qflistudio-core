import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/open_file.dart';
import 'package:qfli_studio_core/editor/vibe_send_coordinator.dart';

/// Regression for the delayed-save window: while protected buffers are being
/// saved, Run/Debug/terminal must not start, and a prompt must re-check
/// execution ownership immediately before it reaches the controller.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  OpenFile file(String name, {bool dirty = false}) {
    final open = OpenFile(
      path: '/project/$name',
      content: 'original',
      highlightTheme: null,
      projectRootPath: '/project',
    );
    open.dirty = dirty;
    return open;
  }

  test('aborts when an execution starts during a delayed save', () async {
    final gate = VibeSendCoordinator();
    final started = Completer<void>();
    final release = Completer<void>();
    var active = false;
    var sent = 0;
    final open = file('main.py', dirty: true);

    final future = gate.submit(
      buffers: [open],
      save: (_) async {
        started.complete();
        await release.future;
        open.dirty = false;
        return null;
      },
      stillOwner: () => true,
      hasActiveExecution: () => active,
      send: (_) => sent++,
      text: '写一个脚本',
    );

    await started.future;
    // Preparation itself counts as busy for every other execution entry.
    expect(gate.preparing, isTrue);

    // A second prompt must not run its own save/send while preparing.
    var secondSaves = 0;
    final second = await gate.submit(
      buffers: [open],
      save: (_) async {
        secondSaves++;
        return null;
      },
      stillOwner: () => true,
      hasActiveExecution: () => active,
      send: (_) => sent++,
      text: '第二条',
    );
    expect(second.sent, isFalse);
    expect(secondSaves, 0);

    // The user starts Run while the save is still awaiting.
    active = true;
    release.complete();

    final result = await future;
    expect(result.sent, isFalse);
    expect(result.message, contains('已有运行任务'));
    expect(sent, 0);
    expect(gate.preparing, isFalse);
  });

  test(
    'refuses before saving when an execution already owns the editor',
    () async {
      final gate = VibeSendCoordinator();
      var saves = 0;
      var sent = 0;
      final result = await gate.submit(
        buffers: [file('a.py', dirty: true)],
        save: (_) async {
          saves++;
          return null;
        },
        stillOwner: () => true,
        hasActiveExecution: () => true,
        send: (_) => sent++,
        text: 'prompt',
      );
      expect(result.sent, isFalse);
      expect(result.message, contains('请先停止'));
      expect(saves, 0);
      expect(sent, 0);
    },
  );

  test('a real save failure aborts the prompt', () async {
    final gate = VibeSendCoordinator();
    var sent = 0;
    final open = file('b.py', dirty: true);
    final result = await gate.submit(
      buffers: [open],
      save: (_) async => '保存失败：拒绝访问',
      stillOwner: () => true,
      hasActiveExecution: () => false,
      send: (_) => sent++,
      text: 'prompt',
    );
    expect(result.sent, isFalse);
    expect(result.message, contains('拒绝访问'));
    expect(sent, 0);
  });

  test('aborts when the owner changes during the save', () async {
    final gate = VibeSendCoordinator();
    final release = Completer<void>();
    var owner = true;
    var sent = 0;
    final open = file('c.py', dirty: true);
    final future = gate.submit(
      buffers: [open],
      save: (_) async {
        await release.future;
        open.dirty = false;
        return null;
      },
      stillOwner: () => owner,
      hasActiveExecution: () => false,
      send: (_) => sent++,
      text: 'prompt',
    );
    owner = false; // the user switched to another project's file
    release.complete();
    final result = await future;
    expect(result.sent, isFalse);
    expect(result.message, contains('项目已切换'));
    expect(sent, 0);
  });

  test('aborts when a buffer is still dirty after its save', () async {
    final gate = VibeSendCoordinator();
    var sent = 0;
    final result = await gate.submit(
      buffers: [file('d.py', dirty: true)],
      save: (_) async => null, // reported success but dirty stays true
      stillOwner: () => true,
      hasActiveExecution: () => false,
      send: (_) => sent++,
      text: 'prompt',
    );
    expect(result.sent, isFalse);
    expect(result.message, contains('未保存'));
    expect(sent, 0);
  });

  test('saves only dirty buffers of this owner, then sends once', () async {
    final gate = VibeSendCoordinator();
    final saved = <String>[];
    var sent = 0;
    final dirty = file('e.py', dirty: true);
    final clean = file('f.py');
    final result = await gate.submit(
      buffers: [dirty, clean],
      save: (open) async {
        saved.add(open.path);
        open.dirty = false;
        return null;
      },
      stillOwner: () => true,
      hasActiveExecution: () => false,
      send: (_) => sent++,
      text: 'prompt',
    );
    expect(result.sent, isTrue);
    expect(saved, ['/project/e.py']);
    expect(sent, 1);
    expect(gate.preparing, isFalse);
  });
}

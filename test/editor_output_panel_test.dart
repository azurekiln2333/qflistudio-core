import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_debug_controller.dart';
import 'package:qfli_studio_core/editor/editor_output_panel.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditorOutputBuffer', () {
    test('preserves exact chunks and notifies only on changes', () {
      final buffer = EditorOutputBuffer();
      addTearDown(buffer.dispose);
      var changes = 0;
      buffer.addListener(() => changes++);
      buffer.append('');
      buffer.clear();
      expect(changes, 0);
      buffer.append('line\r');
      buffer.append('\nnext');
      expect(buffer.text, 'line\r\nnext');
      expect(buffer.truncated, isFalse);
      expect(changes, 2);
      buffer.clear();
      expect(buffer.text, isEmpty);
      expect(changes, 3);
    });

    test('keeps a bounded rolling tail across small and large chunks', () {
      final buffer = EditorOutputBuffer();
      addTearDown(buffer.dispose);
      buffer.append('a' * EditorOutputBuffer.maxUnits);
      expect(buffer.text.length, EditorOutputBuffer.maxUnits);
      expect(buffer.truncated, isFalse);
      buffer.append('END');
      expect(buffer.text, '${'a' * (EditorOutputBuffer.maxUnits - 3)}END');
      expect(buffer.truncated, isTrue);
      buffer.append('${'b' * (EditorOutputBuffer.maxUnits + 50)}TAIL');
      expect(buffer.text, '${'b' * (EditorOutputBuffer.maxUnits - 4)}TAIL');
      buffer.clear();
      expect(buffer.truncated, isFalse);
      buffer.append('fresh');
      expect(buffer.text, 'fresh');
      expect(buffer.truncated, isFalse);
    });

    test('does not split a surrogate pair at a tail boundary', () {
      final buffer = EditorOutputBuffer();
      addTearDown(buffer.dispose);
      buffer.append('😀${'x' * (EditorOutputBuffer.maxUnits - 1)}');
      expect(buffer.text, 'x' * (EditorOutputBuffer.maxUnits - 1));
      expect(buffer.truncated, isTrue);
      buffer.clear();
      buffer.append('a😀${'x' * (EditorOutputBuffer.maxUnits - 3)}');
      buffer.append('!');
      expect(buffer.text.startsWith('😀'), isTrue);
      buffer.append('?');
      expect(buffer.text, '${'x' * (EditorOutputBuffer.maxUnits - 3)}!?');
    });

    test('preserves pairs split between chunks, including a full-size chunk', () {
      final buffer = EditorOutputBuffer();
      addTearDown(buffer.dispose);
      buffer.append(String.fromCharCode(0xd83d));
      buffer.append(String.fromCharCode(0xde00));
      expect(buffer.text, '😀');
      expect(buffer.truncated, isFalse);
      buffer.clear();
      buffer.append(String.fromCharCode(0xd83d));
      buffer.append(
        '${String.fromCharCode(0xde00)}${'x' * (EditorOutputBuffer.maxUnits - 1)}',
      );
      expect(buffer.text, 'x' * (EditorOutputBuffer.maxUnits - 1));
      expect(buffer.truncated, isTrue);
    });

    test('late appends and clears are ignored after idempotent disposal', () {
      final buffer = EditorOutputBuffer()..append('retained');
      buffer.dispose();
      expect(() {
        buffer.dispose();
        buffer.append('late');
        buffer.clear();
      }, returnsNormally);
      expect(buffer.text, 'retained');
    });
  });

  late EditorController editor;
  late _Debug debug;
  late EditorOutputBuffer output;
  setUp(() {
    editor = EditorController(
      project: Project.create(name: 'Panel test', path: '/panel-test'),
    );
    debug = _Debug(editor);
    output = EditorOutputBuffer();
  });
  tearDown(() {
    debug.dispose();
    editor.dispose();
    output.dispose();
  });

  testWidgets(
    'output replaces rolling backend snapshots and keeps real exit status',
    (tester) async {
      output.append('tool output\n');
      debug.publish(_snapshot(stdout: 'old\nretained', stderr: 'warning'));
      await tester.pumpWidget(
        _host(EditorOutputPanel(output: output, debug: debug, onClose: () {})),
      );
      expect(_text(tester, 'editor-run-output'), 'tool output\n');
      expect(_text(tester, 'editor-debug-stdout'), 'old\nretained');
      expect(_text(tester, 'editor-debug-stderr'), 'warning');
      expect(find.textContaining('退出码：未提供'), findsOneWidget);

      debug.publish(
        _snapshot(
          revision: 2,
          stdout: 'retained\nnew',
          exitCode: 7,
          phase: DebugPhase.terminated,
        ),
      );
      await tester.pump();
      expect(_text(tester, 'editor-debug-stdout'), 'retained\nnew');
      expect(find.byKey(const ValueKey('editor-debug-stderr')), findsNothing);
      expect(find.textContaining('退出码：7'), findsOneWidget);
      await tester.tap(find.byTooltip('清空运行与工具输出'));
      await tester.pump();
      expect(output.text, isEmpty);
      expect(_text(tester, 'editor-debug-stdout'), 'retained\nnew');
      expect(debug.snapshot!.stdout, 'retained\nnew');

      debug.publish(null);
      await tester.pump();
      expect(find.text('尚无运行、工具或调试输出'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-debug-stdout')), findsNothing);
    },
  );

  testWidgets('output distinguishes backend truncation from stream retention', (
    tester,
  ) async {
    output.append('x' * (EditorOutputBuffer.maxUnits + 1));
    debug.publish(_snapshot(stdout: 'backend tail', stdoutTruncated: true));
    await tester.pumpWidget(
      _host(EditorOutputPanel(output: output, debug: debug, onClose: () {})),
    );
    expect(find.text('面板仅保留最近 128 Ki UTF-16 单元以内的文本'), findsOneWidget);
    expect(
      _text(tester, 'editor-run-output').length,
      EditorOutputBuffer.maxUnits,
    );
    await tester.tap(find.byTooltip('清空运行与工具输出'));
    await tester.pump();
    expect(output.truncated, isFalse);
    expect(find.text('后端已截断，显示保留的输出'), findsOneWidget);
    expect(_text(tester, 'editor-debug-stdout'), 'backend tail');
  });

  testWidgets(
    'console displays actual logs and feedback without an evaluator',
    (tester) async {
      output.append('preview log');
      debug.publish(
        _snapshot(
          console: 'backend log',
          message: 'paused',
          consoleTruncated: true,
        ),
        error: 'command failed',
      );
      await tester.pumpWidget(
        _host(
          EditorDebugConsolePanel(
            previewConsole: output,
            debug: debug,
            onClose: () {},
          ),
        ),
      );
      expect(_text(tester, 'editor-preview-console'), 'preview log');
      expect(_text(tester, 'editor-debug-console'), 'backend log');
      expect(_text(tester, 'editor-debug-message'), 'paused');
      expect(_text(tester, 'editor-debug-error'), 'command failed');
      expect(find.text('后端已截断，显示保留的输出'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .every((field) => field.readOnly),
        isTrue,
      );

      await tester.tap(find.byTooltip('清空预览日志'));
      await tester.pump();
      expect(output.text, isEmpty);
      expect(_text(tester, 'editor-debug-console'), 'backend log');
      debug.publish(
        _snapshot(revision: 2, console: 'rolling tail', message: 'done'),
        error: 'done',
      );
      await tester.pump();
      expect(_text(tester, 'editor-debug-console'), 'rolling tail');
      expect(find.byKey(const ValueKey('editor-debug-error')), findsNothing);
      debug.publish(null);
      await tester.pump();
      expect(find.text('尚无预览日志或调试器消息'), findsOneWidget);
    },
  );

  testWidgets(
    'ports has an explicit empty state and never calls a stop implicitly',
    (tester) async {
      var stops = 0;
      await tester.pumpWidget(
        _host(
          EditorPortsPanel(
            preview: null,
            onStop: () async {
              stops++;
            },
            onClose: () {},
          ),
        ),
      );
      expect(find.text('当前没有由应用启动的预览监听器'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-preview-stop')), findsNothing);
      expect(stops, 0);
    },
  );

  testWidgets(
    'ports shows the supplied address and awaits the delegated stop',
    (tester) async {
      final preview = _Preview('http://127.0.0.1:41023/index.html');
      final stopped = Completer<void>();
      var stops = 0;
      await tester.pumpWidget(
        _host(
          EditorPortsPanel(
            preview: preview,
            onStop: () {
              stops++;
              return stopped.future;
            },
            onClose: () {},
          ),
        ),
      );
      expect(_text(tester, 'editor-preview-url'), preview.url);
      expect(find.text('端口：41023'), findsOneWidget);
      expect(preview.stopCalls, 0);
      await tester.tap(find.byKey(const ValueKey('editor-preview-stop')));
      await tester.pump();
      expect(stops, 1);
      expect(find.text('停止中…'), findsOneWidget);
      expect(_text(tester, 'editor-preview-url'), preview.url);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('editor-preview-stop')),
            )
            .onPressed,
        isNull,
      );
      stopped.complete();
      await tester.pumpAndSettle();
      expect(find.text('当前没有由应用启动的预览监听器'), findsOneWidget);
    },
  );

  testWidgets(
    'ports does not infer a port or remove a listener after stop failure',
    (tester) async {
      final preview = _Preview('http://localhost/status');
      await tester.pumpWidget(
        _host(
          EditorPortsPanel(
            preview: preview,
            onStop: () async {
              throw StateError('still running');
            },
            onClose: () {},
          ),
        ),
      );
      expect(find.text('端口：URL 未显式提供'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor-preview-stop')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'editor-preview-url'), preview.url);
      expect(find.textContaining('停止预览失败：'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('editor-preview-stop')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('old stop completion cannot hide a replacement preview', (
    tester,
  ) async {
    final first = _Preview('http://127.0.0.1:41023/first');
    final second = _Preview('http://127.0.0.1:41024/second');
    final stopped = Completer<void>();
    await tester.pumpWidget(
      _host(
        EditorPortsPanel(
          preview: first,
          onStop: () => stopped.future,
          onClose: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('editor-preview-stop')));
    await tester.pump();
    await tester.pumpWidget(
      _host(
        EditorPortsPanel(preview: second, onStop: () async {}, onClose: () {}),
      ),
    );
    stopped.complete();
    await tester.pumpAndSettle();
    expect(_text(tester, 'editor-preview-url'), second.url);
    expect(find.text('端口：41024'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-preview-stop')));
    await tester.pumpAndSettle();
    expect(find.text('当前没有由应用启动的预览监听器'), findsOneWidget);
  });

  for (final size in const [Size(160, 260), Size(120, 72), Size(80, 28)]) {
    testWidgets('panels retain a working close at $size and large text', (
      tester,
    ) async {
      debug.publish(
        _snapshot(stdout: 'actual output', console: 'actual diagnostics'),
      );
      output.append('preview');
      var closes = 0;
      final panels = <(Widget, String)>[
        (
          EditorOutputPanel(
            output: output,
            debug: debug,
            onClose: () {
              closes++;
            },
          ),
          'close-editor-output',
        ),
        (
          EditorDebugConsolePanel(
            previewConsole: output,
            debug: debug,
            onClose: () {
              closes++;
            },
          ),
          'close-editor-debug-console',
        ),
        (
          EditorPortsPanel(
            preview: _Preview('http://127.0.0.1:41023/index.html'),
            onStop: () async {},
            onClose: () {
              closes++;
            },
          ),
          'close-editor-ports',
        ),
      ];
      for (final (panel, closeKey) in panels) {
        await tester.pumpWidget(
          _host(panel, width: size.width, height: size.height, scale: 3),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(ValueKey(closeKey)));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(closes, 3);
    });
  }
}

Widget _host(
  Widget child, {
  double width = 600,
  double height = 520,
  double scale = 1,
}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  ),
);

String _text(WidgetTester tester, String key) =>
    tester.widget<SelectableText>(find.byKey(ValueKey(key))).data!;

DebugSnapshot _snapshot({
  int revision = 1,
  DebugPhase phase = DebugPhase.running,
  String stdout = '',
  String stderr = '',
  String console = '',
  bool stdoutTruncated = false,
  bool consoleTruncated = false,
  String? message,
  int? exitCode,
}) => DebugSnapshot(
  sessionId: 'test-session',
  revision: revision,
  phase: phase,
  stdout: stdout,
  stderr: stderr,
  console: console,
  stdoutTruncated: stdoutTruncated,
  consoleTruncated: consoleTruncated,
  message: message,
  exitCode: exitCode,
);

class _Debug extends EditorDebugController {
  _Debug(EditorController editor) : super(editor: editor);
  DebugSnapshot? _value;
  String? _feedback;
  @override
  DebugSnapshot? get snapshot => _value;
  @override
  String? get error => _feedback;
  void publish(DebugSnapshot? value, {String? error}) {
    _value = value;
    _feedback = error;
    notifyListeners();
  }
}

class _Preview implements WebPreviewSession {
  _Preview(this.url);
  @override
  final String url;
  int stopCalls = 0;
  @override
  Stream<String> get debugStream => const Stream.empty();
  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  Widget host(Widget child, {double textScale = 1}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  );

  AgentMessageView message({
    required String id,
    required String role,
    String text = '',
    String? toolName,
    bool isError = false,
    bool pending = false,
    List<String> changedPaths = const [],
  }) => AgentMessageView(
    id: id,
    role: role,
    text: text,
    toolName: toolName,
    isError: isError,
    pending: pending,
    changedPaths: changedPaths,
  );

  testWidgets('the empty state explains what to do next', (tester) async {
    await tester.pumpWidget(
      host(
        const ChatTranscript(
          messages: [],
          state: AgentRunState.idle,
          emptyTitle: '开始一个新的会话',
          emptyHint: '描述你想改什么。',
        ),
      ),
    );

    expect(find.text('开始一个新的会话'), findsOneWidget);
    expect(find.text('描述你想改什么。'), findsOneWidget);
  });

  testWidgets('user, assistant and tool entries all render', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [
            message(id: 'm0', role: 'user', text: '把输出改成大写'),
            message(id: 'm1', role: 'assistant', text: '先读一下文件。'),
            message(
              id: 'm2',
              role: 'tool',
              text: '12 行',
              toolName: 'read_file',
              changedPaths: ['src/Main.java'],
            ),
          ],
          state: AgentRunState.idle,
        ),
      ),
    );

    expect(find.text('把输出改成大写'), findsOneWidget);
    expect(find.text('先读一下文件。'), findsOneWidget);
    expect(find.text('读取文件'), findsOneWidget);
    expect(find.text('src/Main.java'), findsOneWidget);
  });

  testWidgets('a pending tool entry shows it is still running', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [
            message(
              id: 'm0',
              role: 'tool',
              toolName: 'run_command',
              pending: true,
            ),
          ],
          state: AgentRunState.running,
        ),
      ),
    );

    expect(find.text('执行中'), findsOneWidget);
  });

  testWidgets('C3 等确认时状态行写「等待你确认写入」', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'assistant', text: '准备写入')],
          state: AgentRunState.awaitingApproval,
          pendingApproval: const AgentWriteApproval(
            path: 'src/Main.java',
            summary: '新增 3 行',
          ),
        ),
      ),
    );

    expect(find.text('等待你确认写入'), findsOneWidget);
    expect(find.text('思考中…'), findsNothing);
  });

  testWidgets('the approval card allows a write', (tester) async {
    final decisions = <bool>[];
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'assistant', text: '准备写入')],
          state: AgentRunState.awaitingApproval,
          pendingApproval: const AgentWriteApproval(
            path: 'src/Main.java',
            summary: '新增 3 行',
          ),
          onApproval: decisions.add,
        ),
      ),
    );

    expect(find.text('需要确认写入'), findsOneWidget);
    expect(find.text('src/Main.java'), findsOneWidget);
    expect(find.text('新增 3 行'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('approval-allow')));
    await tester.pump();

    expect(decisions, [true]);
  });

  testWidgets('the approval card can refuse a write', (tester) async {
    final decisions = <bool>[];
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'assistant', text: '准备写入')],
          state: AgentRunState.awaitingApproval,
          pendingApproval: const AgentWriteApproval(
            path: 'src/Util.java',
            summary: '整体覆盖',
          ),
          onApproval: decisions.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('approval-deny')));
    await tester.pump();

    expect(decisions, [false]);
  });

  testWidgets('a failed run offers a retry next to the reason', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'user', text: '跑一下')],
          state: AgentRunState.failed,
          lastError: '网络请求失败，请检查连接后重试',
          onRetry: () => retried++,
        ),
      ),
    );

    expect(find.text('网络请求失败，请检查连接后重试'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-retry')));
    await tester.pump();

    expect(retried, 1);
  });

  testWidgets('no retry is offered while the run is still going', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'user', text: '跑一下')],
          state: AgentRunState.running,
          lastError: '上一轮的旧错误',
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('上一轮的旧错误'), findsNothing);
    expect(find.byKey(const ValueKey('chat-retry')), findsNothing);
  });

  testWidgets('a tool failure is marked as failed', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [
            message(
              id: 'm0',
              role: 'tool',
              text: '路径超出项目目录',
              toolName: 'write_file',
              isError: true,
            ),
          ],
          state: AgentRunState.idle,
        ),
      ),
    );

    expect(find.text('失败'), findsOneWidget);
    expect(find.text('路径超出项目目录'), findsOneWidget);
  });

  group('错误详情要说清哪里坏了', () {
    const host_ = 'qfli.suanxiwanjie.cn';
    const friendly = '连不上服务器 qfli.suanxiwanjie.cn：TLS 握手失败';
    const detail = '请求：POST /api/ai/chat\n'
        '服务器：qfli.suanxiwanjie.cn\n'
        '失败步骤：TLS 握手\n'
        '异常：HandshakeException\n'
        '系统信息：Connection terminated during handshake\n'
        '用时：8.2 秒';

    AgentErrorInfo info({
      AgentErrorKind kind = AgentErrorKind.offline,
      int? statusCode,
      String hostName = host_,
      AgentErrorPhase phase = AgentErrorPhase.tls,
      String body = detail,
    }) => AgentErrorInfo(
      kind: kind,
      statusCode: statusCode,
      host: hostName,
      phase: phase,
      detail: body,
    );

    Widget transcript({
      required AgentErrorInfo errorInfo,
      String? lastError = friendly,
      Future<String> Function()? onDiagnose,
    }) => ChatTranscript(
      messages: [message(id: 'm0', role: 'user', text: '跑一下')],
      state: AgentRunState.failed,
      lastError: lastError,
      errorInfo: errorInfo,
      onRetry: () {},
      onDiagnose: onDiagnose,
    );

    /// 用假的平台通道接管剪贴板。
    List<String> mockClipboard() {
      final written = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = call.arguments as Map<Object?, Object?>;
              written.add(args['text'] as String? ?? '');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      return written;
    }

    testWidgets('标题用带主机和步骤的友好文案，详情是多行等宽文本', (tester) async {
      await tester.pumpWidget(host(transcript(errorInfo: info())));

      expect(find.text(friendly), findsOneWidget);

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      // 多行说明原样显示，主机名和失败步骤都在。
      expect(find.text(detail), findsOneWidget);
      expect(find.textContaining('失败步骤：TLS 握手'), findsOneWidget);
      expect(find.textContaining(host_), findsWidgets);

      final shown = tester.widget<SelectableText>(
        find.byKey(const ValueKey('chat-error-detail')),
      );
      expect(shown.style?.fontFamily, 'monospace');
    });

    testWidgets('没有 host 时沿用分类文案', (tester) async {
      await tester.pumpWidget(
        host(
          transcript(
            errorInfo: info(hostName: '', phase: AgentErrorPhase.other),
            lastError: '上游返回的原文',
          ),
        ),
      );

      expect(find.text('网络不可用，检查网络后重试'), findsOneWidget);
    });

    testWidgets('复制按钮把详情和设备时间写进剪贴板', (tester) async {
      final written = mockClipboard();
      await tester.pumpWidget(host(transcript(errorInfo: info())));

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-error-copy')));
      await tester.pump();

      expect(written, hasLength(1));
      expect(written.single, startsWith(detail));
      expect(written.single, contains('\n复制于 '));
      // 复制成功的回执。
      expect(find.text('已复制'), findsOneWidget);
    });

    testWidgets('TLS 失败有「诊断连接」，HTTP 错误没有', (tester) async {
      var diagnosed = 0;
      Future<String> diagnose() async {
        diagnosed++;
        return '服务器：qfli.suanxiwanjie.cn';
      }

      await tester.pumpWidget(
        host(transcript(errorInfo: info(), onDiagnose: diagnose)),
      );
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-error-diagnose')), findsOneWidget);
      // 不自动诊断，必须是零次。
      expect(diagnosed, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          transcript(
            errorInfo: info(
              kind: AgentErrorKind.notConfigured,
              statusCode: 503,
              phase: AgentErrorPhase.http,
              body: '服务端返回 502',
            ),
            lastError: '服务器 qfli.suanxiwanjie.cn 返回 503',
            onDiagnose: diagnose,
          ),
        ),
      );
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-error-diagnose')), findsNothing);
      // 复制始终在。
      expect(find.byKey(const ValueKey('chat-error-copy')), findsOneWidget);
    });

    testWidgets('点一次调一次诊断，结果显示在详情下面', (tester) async {
      var calls = 0;
      var gate = Completer<String>();
      Future<String> diagnose() {
        calls++;
        return gate.future;
      }

      await tester.pumpWidget(
        host(transcript(errorInfo: info(), onDiagnose: diagnose)),
      );
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-error-diagnose')));
      await tester.pump();

      expect(calls, 1);
      expect(
        find.byKey(const ValueKey('chat-error-diagnose-progress')),
        findsOneWidget,
      );

      gate.complete('服务器：qfli.suanxiwanjie.cn\n① 域名解析：成功（0.04 秒）');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('chat-error-diagnose-progress')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('chat-error-diagnosis')), findsOneWidget);
      expect(find.textContaining('域名解析：成功'), findsOneWidget);

      // 再点可以重新诊断。
      gate = Completer<String>();
      await tester.tap(find.byKey(const ValueKey('chat-error-diagnose')));
      await tester.pump();
      expect(calls, 2);
      gate.complete('服务器：qfli.suanxiwanjie.cn\n结论：连接正常');
      await tester.pump();
      expect(find.textContaining('结论：连接正常'), findsOneWidget);
    });

    testWidgets('诊断失败时不把异常飙到界面外', (tester) async {
      await tester.pumpWidget(
        host(
          transcript(
            errorInfo: info(),
            onDiagnose: () async => throw StateError('boom'),
          ),
        ),
      );
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-error-diagnose')));
      await tester.pump();

      expect(find.textContaining('诊断没有完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('390 宽且文字 1.3 倍时不溢出', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 390,
            child: transcript(
              errorInfo: info(
                body: '请求：POST /api/ai/chat\n'
                    '服务器：qfli.suanxiwanjie.cn\n'
                    '失败步骤：TLS 握手\n'
                    '系统信息：Connection terminated during handshake',
              ),
              onDiagnose: () async => '服务器：qfli.suanxiwanjie.cn\n结论：连接正常',
            ),
          ),
          textScale: 1.3,
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-error-diagnose')));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('chat-error-diagnosis')), findsOneWidget);
    });
  });
}

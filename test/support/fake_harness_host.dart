// 假主机：hub 和 Agents 界面的测试与预览共用。
//
// 只实现契约里的行为，不碰 PTY、日志或网络。会话列表由测试直接推进，
// 打开会话返回的 handle 记下 detach/stop 次数，用来验证「关闭视图只
// detach、结束会话要先确认」。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';

/// 假的终端通道：记录写入的字节，测试可以用 [emit] 喂输出。
class FakeTerminalChannel implements HarnessTerminalChannel {
  FakeTerminalChannel();

  final StreamController<Uint8List> _out =
      StreamController<Uint8List>.broadcast();
  final List<Uint8List> writes = <Uint8List>[];
  final List<(int, int)> resizes = <(int, int)>[];

  @override
  Stream<Uint8List> get output => _out.stream;

  @override
  void write(Uint8List data) => writes.add(data);

  @override
  void resize(int columns, int rows) => resizes.add((columns, rows));

  void emit(String text) => _out.add(Uint8List.fromList(text.codeUnits));

  /// 原样发送字节：用来验证被拆开的多字节字符能重新拼回去。
  void emitBytes(List<int> bytes) => _out.add(Uint8List.fromList(bytes));

  Future<void> close() => _out.close();
}

/// 假会话视图。
class FakeSessionHandle implements HarnessSessionHandle {
  FakeSessionHandle({required this.info, this.terminal, bool transcript = true})
    : status = ValueNotifier<HarnessSessionStatus>(info.status),
      _transcript = transcript
          ? StreamController<TranscriptEvent>.broadcast()
          : null;

  @override
  final HarnessSessionInfo info;

  @override
  final HarnessTerminalChannel? terminal;

  @override
  final ValueNotifier<HarnessSessionStatus> status;

  final StreamController<TranscriptEvent>? _transcript;

  final List<String> prompts = <String>[];
  final List<HarnessReply> replies = <HarnessReply>[];
  int detachCount = 0;
  int stopCount = 0;

  /// 非空时 sendPrompt 一直等它：用来观察“发送中”那一刻的界面。
  Completer<void>? sendGate;

  /// 结束后从终端拿到的状态。
  HarnessSessionStatus? lastStatus;

  @override
  Stream<TranscriptEvent>? get transcript => _transcript?.stream;

  void addEvent(TranscriptEvent event) => _transcript?.add(event);

  @override
  Future<void> sendPrompt(String text) async {
    prompts.add(text);
    final gate = sendGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> reply(HarnessReply reply) async => replies.add(reply);

  @override
  Future<void> detach() async => detachCount++;

  @override
  Future<void> stop() async {
    stopCount++;
    status.value = HarnessSessionStatus.exited;
    lastStatus = HarnessSessionStatus.exited;
  }
}

/// 假主机：一个可变的会话列表和固定的 provider 列表。
class FakeHarnessHost implements HarnessHost, HarnessHostHint {
  FakeHarnessHost({
    required this.id,
    required this.label,
    required this.kind,
    List<HarnessSessionInfo> initialSessions = const <HarnessSessionInfo>[],
    this.providerList = const <HarnessProviderInfo>[],
    HarnessHostState initialState = HarnessHostState.online,
    this.hint,
    this.openHandler,
    this.launchHandler,
  }) : _current = initialSessions {
    state = ValueNotifier<HarnessHostState>(initialState);
  }

  @override
  final String id;

  @override
  final String label;

  @override
  final HarnessHostKind kind;

  final List<HarnessProviderInfo> providerList;

  final String? hint;

  /// 可选：给结构化提示的主机换成子类覆写它。
  @override
  Object? get installHint => hint;

  @override
  late final ValueNotifier<HarnessHostState> state;

  /// 打开与会话的钩子，默认返回一个带对话和终端的假 handle。
  final Future<HarnessSessionHandle> Function(String sessionId)? openHandler;
  final Future<HarnessSessionHandle> Function(HarnessLaunchRequest request)?
  launchHandler;

  final List<StreamController<List<HarnessSessionInfo>>> _controllers =
      <StreamController<List<HarnessSessionInfo>>>[];
  List<HarnessSessionInfo> _current;
  final List<String> opened = <String>[];
  int disposeCount = 0;

  List<HarnessSessionInfo> get sessions => _current;

  /// 推进会话列表（测试用）。
  void emitSessions(List<HarnessSessionInfo> sessions) {
    _current = sessions;
    for (final controller in _controllers) {
      controller.add(sessions);
    }
  }

  void setState(HarnessHostState next) => state.value = next;

  @override
  Stream<List<HarnessSessionInfo>> watchSessions() {
    // 每个订阅者一个 controller：hub 刷新会重新订阅，广播 controller 在
    // 没有监听者时不会缓存上一帧，重新订阅时要先把当前列表发一次。
    late final StreamController<List<HarnessSessionInfo>> controller;
    controller = StreamController<List<HarnessSessionInfo>>.broadcast(
      onListen: () => controller.add(_current),
    );
    _controllers.add(controller);
    controller.onCancel = () => _controllers.remove(controller);
    return controller.stream;
  }

  @override
  Future<List<HarnessProviderInfo>> providers() async => providerList;

  @override
  Future<HarnessSessionHandle> open(String sessionId) async {
    opened.add(sessionId);
    final handler = openHandler;
    if (handler != null) return handler(sessionId);
    return FakeSessionHandle(
      info: _infoFor(sessionId),
      terminal: FakeTerminalChannel(),
    );
  }

  HarnessSessionInfo _infoFor(String sessionId) {
    for (final session in _current) {
      if (session.id == sessionId) return session;
    }
    return fakeSession(hostId: id, id: sessionId, title: sessionId);
  }

  @override
  Future<HarnessSessionHandle> launch(HarnessLaunchRequest request) async {
    final handler = launchHandler;
    if (handler != null) return handler(request);
    final info = HarnessSessionInfo(
      id: '$id-new-${opened.length + 1}',
      hostId: id,
      providerId: request.providerId,
      title: request.title ?? '新会话',
      status: HarnessSessionStatus.working,
      capabilities: const {
        HarnessCapability.transcript,
        HarnessCapability.terminal,
        HarnessCapability.prompt,
        HarnessCapability.stop,
      },
      cwd: request.cwd,
    );
    emitSessions(<HarnessSessionInfo>[..._current, info]);
    return FakeSessionHandle(info: info, terminal: FakeTerminalChannel());
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    for (final controller in [..._controllers]) {
      await controller.close();
    }
    _controllers.clear();
  }
}

/// 常用的会话信息。
HarnessSessionInfo fakeSession({
  required String hostId,
  required String id,
  String providerId = 'claude',
  String title = '会话',
  HarnessSessionStatus status = HarnessSessionStatus.idle,
  String? cwd,
  DateTime? updatedAt,
  Set<HarnessCapability> capabilities = const {
    HarnessCapability.transcript,
    HarnessCapability.terminal,
    HarnessCapability.prompt,
    HarnessCapability.stop,
  },
}) {
  return HarnessSessionInfo(
    id: id,
    hostId: hostId,
    providerId: providerId,
    title: title,
    status: status,
    cwd: cwd,
    updatedAt: updatedAt,
    capabilities: capabilities,
  );
}

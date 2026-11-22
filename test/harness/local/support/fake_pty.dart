import 'dart:async';
import 'dart:typed_data';

import 'package:qfli_studio_core/harness/local/pty_process.dart';

/// 测试用的 PTY 进程：由测试手动喂输出和退出码。
class FakePtyProcess implements PtyProcess {
  FakePtyProcess({this.pidValue = 4242, this.resizeSupported = false});

  final int pidValue;
  final bool resizeSupported;
  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  final Completer<int> _exit = Completer<int>();

  /// 收到的写入，按顺序。
  final List<List<int>> writes = <List<int>>[];

  /// 收到的尺寸申请。
  final List<List<int>> resizes = <List<int>>[];

  /// terminate 被调用的次数。
  int terminateCount = 0;

  @override
  int get pid => pidValue;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(List<int> data) {
    writes.add(List<int>.of(data));
  }

  @override
  bool resize(int columns, int rows) {
    resizes.add(<int>[columns, rows]);
    return resizeSupported;
  }

  @override
  Future<void> terminate() async {
    terminateCount++;
    if (!_exit.isCompleted) _exit.complete(0);
    // 让退出码先到达监听者，再关闭输出，与真实进程的先后顺序一致。
    await Future<void>.delayed(Duration.zero);
    if (!_output.isClosed) await _output.close();
  }

  /// 推送一段输出。
  void emit(List<int> data) {
    if (!_output.isClosed) _output.add(Uint8List.fromList(data));
  }

  /// 自然结束。
  void finish(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    scheduleMicrotask(() {
      if (!_output.isClosed) _output.close();
    });
  }
}

/// 记录启动参数的假 launcher。
class FakePtyLauncher implements PtyLauncher {
  FakePtyLauncher({
    this.resizeSupported = false,
    this.allocatesTerminal = true,
  });

  final bool resizeSupported;

  @override
  final bool allocatesTerminal;

  final List<FakePtyProcess> spawned = <FakePtyProcess>[];
  final List<Map<String, Object?>> launches = <Map<String, Object?>>[];

  /// dispose 被调用的次数。
  int disposeCount = 0;

  @override
  String get strategy => allocatesTerminal ? 'fake' : 'pipe';

  @override
  bool get supportsResize => resizeSupported;

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  Future<PtyProcess> spawn({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) async {
    launches.add(<String, Object?>{
      'executable': executable,
      'arguments': arguments,
      'workingDirectory': workingDirectory,
      'environment': environment,
      'columns': columns,
      'rows': rows,
    });
    final process = FakePtyProcess(resizeSupported: resizeSupported);
    spawned.add(process);
    return process;
  }
}

// 把 StudioMux 的 PTY 后端接到 `HarnessPtyFactory` 接缝上。
//
// 本机主机（LocalHarnessHost）自己持有 `PtyLauncher`；Herdr 主机只认
// `lib/harness/pty/harness_pty.dart` 的接缝。两边形状几乎一一对应，差别只在
// 入参形态（可执行文件 + 参数列表 vs argv）和返回值包装，所以适配器放在这里，
// 平台代码仍然只有一份。
//
// 后端没有真实终端时（Windows 的管道模式、移动端）直接抛
// `HarnessPtyException`：调用方会退回快照终端，不会拿到一个看起来能用、
// 实际上不能交互的壳。

import 'dart:async';
import 'dart:typed_data';

import '../pty/harness_pty.dart';
import 'pty_process.dart';

/// 用 [PtyLauncher] 启动 `HarnessPty`。
///
/// launcher 可以外部注入（与 `StudioMux` 共用同一个后端），也可以留空由本
/// 工厂惰性创建；只有自己创建的那个会被 [dispose] 释放，外部注入的由调用方
/// 负责，避免重复释放共享后端。
class StudioMuxPtyFactory implements HarnessPtyFactory {
  StudioMuxPtyFactory({PtyLauncher? launcher})
    : _launcher = launcher,
      _ownsLauncher = launcher == null;

  PtyLauncher? _launcher;
  final bool _ownsLauncher;

  /// 后端是否分配真实终端。为 false 时 [start] 一定失败。
  bool get allocatesTerminal => _resolve().allocatesTerminal;

  PtyLauncher _resolve() => _launcher ??= createPtyLauncher();

  @override
  Future<HarnessPty> start({
    required List<String> argv,
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 80,
    int rows = 24,
  }) async {
    if (argv.isEmpty) {
      throw const HarnessPtyException('缺少要运行的程序');
    }
    final launcher = _resolve();
    if (!launcher.allocatesTerminal) {
      throw const HarnessPtyException('当前平台没有真实终端，交互式界面无法运行');
    }
    final process = await launcher.spawn(
      executable: argv.first,
      arguments: argv.sublist(1),
      workingDirectory: workingDirectory,
      environment: environment,
      columns: columns,
      rows: rows,
    );
    return _PtyAdapter(process);
  }

  /// 释放自建的 launcher；外部注入的不动。
  Future<void> dispose() async {
    if (!_ownsLauncher) return;
    final launcher = _launcher;
    _launcher = null;
    await launcher?.dispose();
  }
}

/// [PtyProcess] → [HarnessPty]。
class _PtyAdapter implements HarnessPty {
  _PtyAdapter(this._process);

  final PtyProcess _process;
  bool _killed = false;

  @override
  int? get pid => _process.pid;

  @override
  Stream<Uint8List> get output => _process.output;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(Uint8List data) {
    if (_killed) return;
    _process.write(data);
  }

  @override
  void resize(int columns, int rows) {
    if (_killed) return;
    // 后端不支持运行期改尺寸时返回 false；这里不能假装成功，也不需要抛错：
    // 终端视图已经按上一次的尺寸排版。
    _process.resize(columns, rows);
  }

  @override
  Future<void> kill() async {
    if (_killed) return;
    _killed = true;
    await _process.terminate();
  }
}

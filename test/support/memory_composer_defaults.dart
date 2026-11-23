import 'package:qfli_studio_core/chat/composer_state.dart';

/// 输入卡片选择记忆的内存实现。
///
/// 文件实现要问 `AppPaths.storageDirectory()` 才能拿到落盘位置。那一步在
/// widget 测试里会挂一个 2 秒的可写性定时器：平台通道不回应，定时器就活过
/// 建个用例，测试框架随即以「A Timer is still pending even after the widget
/// tree was disposed」失败。
///
/// 编辑器页面的用例都在挂载时注入这一份，行为不变（读不到就是没有记住过），
/// 只是不碰文件系统，也不留目录探测的定时器。
class MemoryComposerDefaults implements ComposerDefaultsStore {
  final Map<String, ComposerDefaults> _byProject = {};

  /// 当前记住的选择，用例可以断言写进去的内容。
  ComposerDefaults? valueFor(String projectId) => _byProject[projectId];

  @override
  Future<ComposerDefaults?> read(String projectId) async =>
      _byProject[projectId];

  @override
  Future<void> write(String projectId, ComposerDefaults defaults) async {
    _byProject[projectId] = defaults;
  }
}

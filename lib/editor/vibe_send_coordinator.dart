import 'open_file.dart';

/// Outcome of one prompt submission attempt.
class VibeSendResult {
  const VibeSendResult._(this.sent, this.message);

  const VibeSendResult.sent() : this._(true, null);
  const VibeSendResult.aborted(String reason) : this._(false, reason);

  /// True only when the prompt was actually handed to the controller.
  final bool sent;

  /// User-facing reason when [sent] is false; null for an ignored duplicate.
  final String? message;
}

/// Serialises Vibe prompt preparation and keeps execution ownership exclusive.
///
/// Protected buffers are saved with awaits before the model may run. Two things
/// can change during those awaits: the editor may switch to another project, and
/// the user may start a Run, Debug session or terminal command. Both invalidate
/// the prompt, so ownership and execution availability are re-checked after
/// every save and once more immediately before the handoff.
class VibeSendCoordinator {
  bool _preparing = false;

  /// True while buffers are being saved for a prompt. Callers must treat this as
  /// busy: no Run, Debug, terminal command or second prompt may start.
  bool get preparing => _preparing;

  Future<VibeSendResult> submit({
    required List<OpenFile> buffers,
    required Future<String?> Function(OpenFile open) save,
    required bool Function() stillOwner,
    required bool Function() hasActiveExecution,
    required void Function(String text) send,
    required String text,
  }) async {
    if (_preparing) {
      return const VibeSendResult.aborted('上一个请求仍在准备');
    }
    if (!stillOwner()) {
      return const VibeSendResult.aborted('项目已切换，发送已取消');
    }
    if (hasActiveExecution()) {
      return const VibeSendResult.aborted('请先停止当前运行或调试，再使用 Vibe Coding');
    }
    _preparing = true;
    try {
      for (final open in buffers) {
        if (!open.dirty) continue;
        final error = await save(open);
        if (!stillOwner()) {
          return const VibeSendResult.aborted('项目已切换，发送已取消');
        }
        if (error != null) {
          return VibeSendResult.aborted('保存失败，已中止：$error');
        }
      }
      if (!stillOwner()) {
        return const VibeSendResult.aborted('项目已切换，发送已取消');
      }
      if (buffers.any((open) => open.dirty)) {
        return const VibeSendResult.aborted('仍有未保存的文件，已中止发送');
      }
      // A Run, Debug session or terminal command may have started while saves
      // were awaiting. Starting the model now would fight it for the project.
      if (hasActiveExecution()) {
        return const VibeSendResult.aborted('已有运行任务开始，发送已取消');
      }
      send(text);
      return const VibeSendResult.sent();
    } finally {
      _preparing = false;
    }
  }
}

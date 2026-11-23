import 'package:flutter/foundation.dart';

/// 从项目页带进工作台的第一条消息。
///
/// 项目页只负责创建会话；真正发起这一轮的是工作台持有的 facade，这样同一
/// 个会话始终只有一个执行者。
@immutable
class ComposerDraft {
  const ComposerDraft({
    this.text = '',
    this.attachments = const [],
    this.autoSend = true,
  });

  static const ComposerDraft empty = ComposerDraft();

  final String text;
  final List<String> attachments;

  /// 为假时只把附件填进输入卡片，不替用户发送。
  ///
  /// 分享进来的文件走这条路：用户到编辑器里自己补一句话再发。
  final bool autoSend;

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
}

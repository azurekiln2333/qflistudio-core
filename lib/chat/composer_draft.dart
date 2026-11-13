import 'package:flutter/foundation.dart';

/// 从项目页带进工作台的第一条消息。
///
/// 项目页只负责创建会话；真正发起这一轮的是工作台持有的 facade，这样同一
/// 个会话始终只有一个执行者。
@immutable
class ComposerDraft {
  const ComposerDraft({this.text = '', this.attachments = const []});

  static const ComposerDraft empty = ComposerDraft();

  final String text;
  final List<String> attachments;

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
}

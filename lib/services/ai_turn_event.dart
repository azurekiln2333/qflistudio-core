/// 一次模型回合的增量事件。
///
/// 中转与直连、三种协议都转换成这一种事件流。Agent 循环只认这个类型，
/// 不按协议分支（`.trellis/spec/frontend/ai-protocols.md` §3）。
///
/// 增量事件只用于显示。写历史、执行工具只认 [AiTurnCompleted.result]。
library;

import 'api_client.dart' show AiChatResult;

sealed class AiTurnEvent {
  const AiTurnEvent();
}

/// 思考内容增量。
final class AiReasoningDelta extends AiTurnEvent {
  const AiReasoningDelta(this.text);

  final String text;
}

/// 正文增量。
final class AiContentDelta extends AiTurnEvent {
  const AiContentDelta(this.text);

  final String text;
}

/// 某个工具调用第一次出现名字。只用于界面提示，不执行。
final class AiToolCallStarted extends AiTurnEvent {
  const AiToolCallStarted({required this.index, required this.name});

  final int index;
  final String name;
}

/// 回合结束。[result] 是这一轮唯一的权威结果。
final class AiTurnCompleted extends AiTurnEvent {
  const AiTurnCompleted(this.result);

  final AiChatResult result;
}

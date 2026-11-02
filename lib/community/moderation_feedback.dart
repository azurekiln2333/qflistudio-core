import 'package:flutter/foundation.dart';

import '../services/api_client.dart';

/// 用户看到错误后下一步能做什么。
enum ModerationAction {
  /// 未实名：引导走华为账号绑定手机号。
  bindPhone,

  /// 被限流：稍后重试，可选倒计时。
  waitAndRetry,

  /// 被禁言 / 封停：只能查看，不能发布。
  contactAdmin,

  /// 审核服务不可用：稍后重试发布。
  retryLater,

  /// 普通错误：原样显示服务端文案。
  none,
}

/// 一条可直接展示的错误提示。
@immutable
class ModerationMessage {
  const ModerationMessage({
    required this.text,
    this.action = ModerationAction.none,
    this.retryAfterSeconds,
  });

  /// 给用户看的一句话。不回显服务端返回的命中词原文。
  final String text;

  final ModerationAction action;

  /// `429 rate.limited` 的 `retryAfter`（秒）；其它情况为 null。
  final int? retryAfterSeconds;

  bool get requiresBinding => action == ModerationAction.bindPhone;

  @override
  String toString() => text;
}

/// 把服务端的错误码翻译成用户能行动的一句话（contracts.md C 节）。
///
/// 只覆盖错误体契约里的错误码；未知错误保留服务端 `message`，
/// 空文案回落到状态码提示。这里不回显 `X-Request-Id` 之外的任何细节，
/// 也从不拼接 `categories` 命中词原文。
abstract final class ModerationFeedback {
  /// 审核服务不可用时的固定文案，与服务端 `message` 一致。
  static const String moderationUnavailable = '审核服务暂不可用';

  static const Map<String, String> categoryLabels = {
    'politics': '涉政',
    'porn': '色情',
    'gambling': '赌博',
    'drugs': '毒品',
    'weapons': '枪支弹药',
    'controlled': '管制器具',
    'fraud': '诈骗',
    'terror': '暴恐',
    'contraband': '违禁品',
    'advertising': '广告引流',
    'custom': '自定义',
  };

  static ModerationMessage describe(Object error) {
    if (error is! ApiException) {
      return ModerationMessage(text: '$error');
    }
    final key = error.details['errorKey'];
    final message = error.message.trim();
    switch (key is String ? key : '') {
      case 'realname.required':
        return const ModerationMessage(
          text: '该功能需要先完成手机号实名绑定。请使用已绑定手机号的华为账号登录。',
          action: ModerationAction.bindPhone,
        );
      case 'account.banned':
        return const ModerationMessage(
          text: '账号已被封停，暂时不能使用社区、云项目、终端和 AI 服务。',
          action: ModerationAction.contactAdmin,
        );
      case 'account.muted':
        return const ModerationMessage(
          text: '账号已被禁言，暂时不能发帖或评论。',
          action: ModerationAction.contactAdmin,
        );
      case 'rate.limited':
        final retryAfter = _retryAfter(error.details);
        return ModerationMessage(
          text: retryAfter == null
              ? '发布过于频繁，请稍后再试。'
              : '发布过于频繁，请 $retryAfter 秒后再试。',
          action: ModerationAction.waitAndRetry,
          retryAfterSeconds: retryAfter,
        );
      case 'moderation.blocked':
        final categories = _categories(error.details);
        final suffix = categories.isEmpty ? '' : '（${categories.join('、')}）';
        return ModerationMessage(text: '内容未通过审核$suffix，请修改后重新提交。');
      case 'moderation.unavailable':
        return const ModerationMessage(
          text: moderationUnavailable,
          action: ModerationAction.retryLater,
        );
    }
    // 没有 errorKey 时仍按状态码兜底，保证提示可读。
    switch (error.statusCode) {
      case 403:
        if (message.contains('实名') || message.contains('手机号')) {
          return const ModerationMessage(
            text: '该功能需要先完成手机号实名绑定。请使用已绑定手机号的华为账号登录。',
            action: ModerationAction.bindPhone,
          );
        }
      case 429:
        final retryAfter = _retryAfter(error.details);
        return ModerationMessage(
          text: retryAfter == null
              ? '操作过于频繁，请稍后再试。'
              : '操作过于频繁，请 $retryAfter 秒后再试。',
          action: ModerationAction.waitAndRetry,
          retryAfterSeconds: retryAfter,
        );
      case 422:
        return const ModerationMessage(text: '内容未通过审核，请修改后重新提交。');
      case 503:
        return const ModerationMessage(
          text: moderationUnavailable,
          action: ModerationAction.retryLater,
        );
    }
    if (message.isNotEmpty) return ModerationMessage(text: message);
    return ModerationMessage(text: '请求失败（${error.statusCode ?? '网络错误'}）');
  }

  static int? _retryAfter(Map<String, dynamic> details) {
    for (final key in const ['retryAfter', 'retry_after']) {
      final value = details[key];
      if (value is num && value >= 0) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null && parsed >= 0) return parsed;
      }
    }
    return null;
  }

  /// 命中的类别；服务端只下发类别，不下发命中词原文。
  static List<String> _categories(Map<String, dynamic> details) {
    final raw = details['categories'];
    if (raw is! List) return const [];
    final result = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final label = categoryLabels[item] ?? item;
      if (!result.contains(label)) result.add(label);
    }
    return result;
  }
}

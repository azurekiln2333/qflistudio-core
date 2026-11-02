@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/community/moderation_feedback.dart';
import 'package:qfli_studio_core/services/account_erasure_service.dart';
import 'package:qfli_studio_core/services/api_client.dart';

/// Contract C 节 error keys → a message the user can act on.
///
/// Two rules are load-bearing: the client guides an unverified account to phone
/// binding, and a blocked text never echoes the matched words back (the server
/// does not send them, so echoing anything would mean inventing content).
void main() {
  group('realname and account state', () {
    test('realname.required guides to Huawei phone binding', () {
      final message = ModerationFeedback.describe(
        ApiException(
          '需要实名',
          statusCode: 403,
          details: const {'errorKey': 'realname.required'},
        ),
      );
      expect(message.requiresBinding, isTrue);
      expect(message.action, ModerationAction.bindPhone);
      expect(message.text, contains('实名'));
      expect(message.text, contains('华为账号'));
    });

    test('a bare 403 that mentions 手机号 still guides to binding', () {
      final message = ModerationFeedback.describe(
        ApiException('请先绑定手机号', statusCode: 403),
      );
      expect(message.action, ModerationAction.bindPhone);
    });

    test('banned and muted are explained as posting restrictions', () {
      final banned = ModerationFeedback.describe(
        ApiException(
          'banned',
          statusCode: 403,
          details: const {'errorKey': 'account.banned'},
        ),
      );
      final muted = ModerationFeedback.describe(
        ApiException(
          'muted',
          statusCode: 403,
          details: const {'errorKey': 'account.muted'},
        ),
      );
      expect(banned.text, contains('封停'));
      expect(banned.action, ModerationAction.contactAdmin);
      expect(muted.text, contains('禁言'));
      expect(muted.action, ModerationAction.contactAdmin);
    });
  });

  group('rate limiting', () {
    test('surfaces retryAfter seconds', () {
      final message = ModerationFeedback.describe(
        ApiException(
          'too many',
          statusCode: 429,
          details: const {'errorKey': 'rate.limited', 'retryAfter': 30},
        ),
      );
      expect(message.retryAfterSeconds, 30);
      expect(message.text, contains('30'));
      expect(message.action, ModerationAction.waitAndRetry);
    });

    test('accepts a string retryAfter and falls back when absent', () {
      expect(
        ModerationFeedback.describe(
          ApiException(
            'x',
            statusCode: 429,
            details: const {'errorKey': 'rate.limited', 'retryAfter': '15'},
          ),
        ).retryAfterSeconds,
        15,
      );
      final without = ModerationFeedback.describe(
        ApiException(
          'x',
          statusCode: 429,
          details: const {'errorKey': 'rate.limited'},
        ),
      );
      expect(without.retryAfterSeconds, isNull);
      expect(without.text, isNotEmpty);
    });
  });

  group('moderation results', () {
    test('blocked text lists categories but never the matched words', () {
      final message = ModerationFeedback.describe(
        ApiException(
          '命中敏感词：代开发票',
          statusCode: 422,
          details: const {
            'errorKey': 'moderation.blocked',
            'categories': ['advertising', 'fraud'],
          },
        ),
      );
      expect(message.text, contains('广告引流'));
      expect(message.text, contains('诈骗'));
      // The server message may carry the hit word; the client must not show it.
      expect(message.text, isNot(contains('代开发票')));
      expect(message.text, isNot(contains('命中敏感词')));
    });

    test('an unknown category id is shown as-is, still without hit words', () {
      final message = ModerationFeedback.describe(
        ApiException(
          'x',
          statusCode: 422,
          details: const {
            'errorKey': 'moderation.blocked',
            'categories': ['brand-new'],
          },
        ),
      );
      expect(message.text, contains('brand-new'));
    });

    test('unavailable uses the promised wording', () {
      final message = ModerationFeedback.describe(
        ApiException(
          '审核服务暂不可用',
          statusCode: 503,
          details: const {'errorKey': 'moderation.unavailable'},
        ),
      );
      expect(message.text, ModerationFeedback.moderationUnavailable);
      expect(message.action, ModerationAction.retryLater);
    });
  });

  group('fallbacks', () {
    test('an unknown error keeps the server message', () {
      final message = ModerationFeedback.describe(
        ApiException('服务暂时不可用（500），请稍后重试', statusCode: 500),
      );
      expect(message.text, contains('500'));
      expect(message.action, ModerationAction.none);
    });

    test('an empty message falls back to the status code', () {
      final message = ModerationFeedback.describe(
        ApiException('', statusCode: 418),
      );
      expect(message.text, contains('418'));
    });

    test('a non-ApiException still renders as text', () {
      expect(
        ModerationFeedback.describe(StateError('boom')).text,
        contains('boom'),
      );
    });
  });

  test('the erasure confirm word matches the contract', () {
    expect(AccountErasureService.confirmWord, 'DEACTIVATE');
  });
}

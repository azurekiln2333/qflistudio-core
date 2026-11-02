import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/community/moderation_feedback.dart';
import 'package:qfli_studio_core/services/api_client.dart';

/// Community side of the remediation (整改任务书 §3-W3).
///
/// Two things are asserted here: a post or comment can be reported through
/// `POST /api/reports`, and the moderation error keys turn into the wording the
/// release checklist asks for.
void main() {
  late List<http.Request> sent;

  setUp(() => sent = []);

  ApiClient clientReturning(Object body, {int status = 200}) {
    return ApiClient(
      transport: MockClient((request) async {
        sent.add(request);
        return http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  group('report', () {
    test('posts target type and id to the reports endpoint', () async {
      final api = clientReturning({'id': 'r-1', 'status': 'pending'});
      final result = await api.report(
        token: 'token-1',
        targetType: kReportTargetPost,
        targetId: '42',
        reason: kReportReasonSpam,
      );

      expect(result.id, 'r-1');
      expect(result.status, 'pending');
      final request = sent.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/reports');
      expect(request.headers['authorization'], 'Bearer token-1');
      expect(jsonDecode(request.body), {
        'targetType': 'post',
        'targetId': '42',
        'reason': kReportReasonSpam,
      });
    });

    test('a comment report sends the comment target type', () async {
      final api = clientReturning({'id': 'r-2', 'status': 'pending'});
      await api.report(
        token: 't',
        targetType: kReportTargetComment,
        targetId: 'c-7',
        reason: kReportReasonAbuse,
      );
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['targetType'], 'comment');
      expect(body['targetId'], 'c-7');
      expect(body['reason'], 'abuse');
    });

    test('an unknown target type never reaches the network', () async {
      final api = clientReturning({'id': 'r-3'});
      await expectLater(
        api.report(
          token: 't',
          targetType: 'message',
          targetId: '9',
          reason: kReportReasonSpam,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(sent, isEmpty);
    });

    test(
      'a response without an id is an exception, not a silent success',
      () async {
        final api = clientReturning({'status': 'pending'});
        await expectLater(
          api.report(
            token: 't',
            targetType: kReportTargetPost,
            targetId: '42',
            reason: kReportReasonSpam,
          ),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test(
      'a duplicate report keeps the status code and the error body',
      () async {
        final api = clientReturning({
          'error': '已举报该内容',
          'errorKey': 'report.duplicate',
        }, status: 409);
        await expectLater(
          api.report(
            token: 't',
            targetType: kReportTargetPost,
            targetId: '42',
            reason: kReportReasonSpam,
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.details['errorKey'],
                  'errorKey',
                  'report.duplicate',
                ),
          ),
        );
      },
    );

    test('the report dialog offers a fixed reason list', () {
      // Wire values stay stable ASCII: the server stores them.
      for (final key in kReportReasonLabels.keys) {
        expect(key, matches(RegExp(r'^[a-z]+$')));
      }
      expect(kReportReasonLabels[kReportReasonSpam], '广告引流');
      expect(kReportReasonLabels[kReportReasonPorn], '色情低俗');
      expect(kReportReasonLabels[kReportReasonIllegal], '违法违规内容');
      expect(kReportReasonLabels.length, 7);
    });
  });

  group('pending moderation', () {
    test('a pending post reports itself as pending', () {
      expect(_post(status: kModerationStatusPending).isPending, isTrue);
      expect(isModerationPending(kModerationStatusPending), isTrue);
    });

    test('a published post is not pending', () {
      expect(_post(status: kModerationStatusPublished).isPending, isFalse);
    });

    test('a missing status is treated as published', () {
      expect(_post().isPending, isFalse);
      expect(isModerationPending(''), isFalse);
      expect(isModerationPending('weird'), isFalse);
    });

    test('a rejected post is not shown as pending', () {
      expect(_post(status: kModerationStatusRejected).isPending, isFalse);
    });

    test('a pending comment reports itself as pending', () {
      final comment = _comment(status: kModerationStatusPending);
      expect(comment.isPending, isTrue);
      final published = _comment(status: kModerationStatusPublished);
      expect(published.isPending, isFalse);
    });
  });

  group('feedback wording', () {
    ModerationMessage describe({
      String? errorKey,
      int? statusCode,
      String message = 'server said something in English',
      Map<String, dynamic> details = const {},
    }) => ModerationFeedback.describe(
      ApiException(
        message,
        statusCode: statusCode,
        details: {'errorKey': ?errorKey, ...details},
      ),
    );

    test('every key the task names has a fixed Chinese wording', () {
      expect(describe(errorKey: 'realname.required').text, contains('实名'));
      expect(describe(errorKey: 'rate.limited').text, contains('频繁'));
      expect(describe(errorKey: 'moderation.blocked').text, contains('审核'));
      expect(
        describe(errorKey: 'moderation.unavailable').text,
        ModerationFeedback.moderationUnavailable,
      );
      expect(describe(errorKey: 'account.banned').text, contains('封停'));
      expect(describe(errorKey: 'account.muted').text, contains('禁言'));
    });

    test('the actions tell the user what to do next', () {
      expect(
        describe(errorKey: 'realname.required').action,
        ModerationAction.bindPhone,
      );
      expect(
        describe(errorKey: 'rate.limited').action,
        ModerationAction.waitAndRetry,
      );
      expect(
        describe(errorKey: 'moderation.unavailable').action,
        ModerationAction.retryLater,
      );
      expect(
        describe(errorKey: 'account.banned').action,
        ModerationAction.contactAdmin,
      );
    });

    test('no wording echoes the matched words', () {
      for (final key in const [
        'realname.required',
        'rate.limited',
        'moderation.blocked',
        'moderation.unavailable',
        'account.banned',
        'account.muted',
      ]) {
        final message = describe(
          errorKey: key,
          details: {
            'categories': ['porn', 'politics'],
            'hits': ['裸', '政府'],
            'matchedWords': ['裸聊'],
          },
        );
        expect(message.text, isNot(contains('裸')), reason: key);
        expect(message.text, isNot(contains('政府')), reason: key);
        expect(message.text, isNot(contains('porn')), reason: key);
      }
    });

    test('a blocked message names the hit categories, not the words', () {
      final message = describe(
        errorKey: 'moderation.blocked',
        details: {
          'categories': ['porn', 'politics'],
        },
      );
      expect(message.text, contains('色情'));
      expect(message.text, contains('涉政'));
    });

    test('an unmapped category is deduplicated instead of repeated', () {
      final message = describe(
        errorKey: 'moderation.blocked',
        details: {
          'categories': ['custom', 'custom'],
        },
      );
      expect('自定义'.allMatches(message.text).length, 1);
    });

    test('rate.limited carries the wait time in plain words', () {
      final message = describe(
        errorKey: 'rate.limited',
        details: {'retryAfter': 30},
      );
      expect(message.text, contains('30 秒'));
      expect(message.retryAfterSeconds, 30);
    });

    test('a bare status code still gets a usable wording', () {
      expect(describe(statusCode: 429).text, contains('频繁'));
      expect(
        describe(statusCode: 503).text,
        ModerationFeedback.moderationUnavailable,
      );
      expect(describe(statusCode: 422).text, contains('审核'));
      expect(describe(statusCode: 403).text, isNotEmpty);
    });

    test('a 403 that mentions real name is diagnosed as such', () {
      final message = describe(statusCode: 403, message: '需要先完成手机号实名绑定');
      expect(message.action, ModerationAction.bindPhone);
    });

    test('an unknown error keeps the server sentence', () {
      expect(describe(statusCode: 400, message: '标题过长').text, '标题过长');
    });

    test('an empty message falls back to the status code', () {
      final message = describe(statusCode: 500, message: '  ');
      expect(message.text, contains('500'));
    });

    test('a non-Api error is passed through without pretending to be审核', () {
      final message = ModerationFeedback.describe(StateError('boom'));
      expect(message.text, isNot(contains('审核')));
    });
  });
}

Post _post({String? status}) => Post(
  id: '1',
  type: 'discussion',
  title: '标题',
  excerpt: '正文',
  content: '正文',
  tags: const [],
  zoneId: 'z-1',
  zoneName: '综合',
  author: const PostAuthor(
    id: 'u-1',
    nickname: 'demo',
    username: 'demo',
    avatarColor: '#000',
  ),
  likeCount: 0,
  commentCount: 0,
  liked: false,
  createdAt: '2026-01-01T00:00:00Z',
  // A missing field must behave like the default, so omit it entirely.
  status: status ?? kModerationStatusPublished,
);

Comment _comment({String? status}) => Comment(
  id: 'c-1',
  content: '内容',
  createdAt: '2026-01-01T00:00:00Z',
  parentId: null,
  author: const PostAuthor(
    id: 'u-1',
    nickname: 'demo',
    username: 'demo',
    avatarColor: '#000',
  ),
  children: const [],
  status: status ?? kModerationStatusPublished,
);

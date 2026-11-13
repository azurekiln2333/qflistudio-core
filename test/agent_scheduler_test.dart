import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/vibe_coding/agent_request_scheduler.dart';

void main() {
  test('E6 caps concurrency and queues the rest', () async {
    final scheduler = AgentRequestScheduler(maxConcurrent: 2);
    final gates = <String, Completer<void>>{
      'a': Completer<void>(),
      'b': Completer<void>(),
      'c': Completer<void>(),
    };
    final started = <String>[];

    Future<void> run(String key) => scheduler.run(key, () async {
      started.add(key);
      await gates[key]!.future;
    });

    final a = run('a');
    final b = run('b');
    final c = run('c');
    await Future<void>.delayed(Duration.zero);

    expect(started, ['a', 'b']);
    expect(scheduler.activeCount, 2);
    expect(scheduler.isWaiting('c'), isTrue);
    expect(scheduler.waitingCount, 1);

    // 放行一个，排队的那个立刻接上。
    gates['a']!.complete();
    await a;
    await Future<void>.delayed(Duration.zero);

    expect(started, ['a', 'b', 'c']);
    expect(scheduler.isWaiting('c'), isFalse);
    expect(scheduler.activeCount, 2);

    gates['b']!.complete();
    gates['c']!.complete();
    await b;
    await c;
    expect(scheduler.activeCount, 0);
  });

  test('E7 retries 429 with 1s, 2s, 4s and gives up after three', () async {
    final delays = <Duration>[];
    final scheduler = AgentRequestScheduler(
      sleep: (delay) async => delays.add(delay),
    );
    var attempts = 0;

    await expectLater(
      scheduler.run('s', () async {
        attempts++;
        throw ApiException('请求太频繁', statusCode: 429);
      }),
      throwsA(isA<ApiException>()),
    );

    // 首次 + 3 次重试。
    expect(attempts, 4);
    expect(delays, const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ]);
    expect(scheduler.activeCount, 0);
  });

  test('E7 a retry that succeeds returns the result', () async {
    final delays = <Duration>[];
    final scheduler = AgentRequestScheduler(
      sleep: (delay) async => delays.add(delay),
    );
    var attempts = 0;

    final result = await scheduler.run('s', () async {
      attempts++;
      if (attempts < 3) {
        throw ApiException('请求太频繁', statusCode: 429);
      }
      return 'ok';
    });

    expect(result, 'ok');
    expect(attempts, 3);
    expect(delays, const [Duration(seconds: 1), Duration(seconds: 2)]);
  });

  test('E7 other errors are not retried', () async {
    final delays = <Duration>[];
    final scheduler = AgentRequestScheduler(
      sleep: (delay) async => delays.add(delay),
    );
    var attempts = 0;

    await expectLater(
      scheduler.run('s', () async {
        attempts++;
        throw ApiException('AI 服务未配置', statusCode: 503);
      }),
      throwsA(isA<ApiException>()),
    );

    expect(attempts, 1);
    expect(delays, isEmpty);
  });

  test('E7 a cancelled run stops retrying', () async {
    final delays = <Duration>[];
    final scheduler = AgentRequestScheduler(
      sleep: (delay) async => delays.add(delay),
    );
    var attempts = 0;
    var cancelled = false;

    await expectLater(
      scheduler.run(
        's',
        () async {
          attempts++;
          cancelled = true;
          throw ApiException('请求太频繁', statusCode: 429);
        },
        isCancelled: () => cancelled,
      ),
      throwsA(isA<ApiException>()),
    );

    expect(attempts, 1);
    expect(delays, isEmpty);
  });

  test('cancelWaiting releases the queue without running the request', () async {
    final scheduler = AgentRequestScheduler(maxConcurrent: 1);
    final gate = Completer<void>();
    final first = scheduler.run('a', () => gate.future);
    final queued = scheduler.run('b', () async => 'never');
    await Future<void>.delayed(Duration.zero);

    expect(scheduler.isWaiting('b'), isTrue);
    scheduler.cancelWaiting();

    await expectLater(
      queued,
      throwsA(
        isA<ApiException>().having(
          (error) => error.details['code'],
          'code',
          'ABORTED',
        ),
      ),
    );
    expect(scheduler.isWaiting('b'), isFalse);

    gate.complete();
    await first;
    expect(scheduler.activeCount, 0);
  });
}

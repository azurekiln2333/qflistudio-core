import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/pages/tasks_page.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

CommunityUser _user() => const CommunityUser(
  id: 'user_a',
  username: 'tester',
  nickname: 'Tester',
  bio: '',
  avatarColor: '#2196F3',
  points: 10,
  checkinStreak: 0,
  provider: 'local',
);

CommunityUser _userB() => const CommunityUser(
  id: 'user_b',
  username: 'other',
  nickname: 'Other',
  bio: '',
  avatarColor: '#4CAF50',
  points: 50,
  checkinStreak: 0,
  provider: 'local',
);

/// Test double for the page's state machine. No file or network I/O runs, so
/// the widget test stays inside the fake-async zone.
class _FakeActivity extends TaskActivityService {
  bool done = false;
  bool failNext = false;
  bool throwStorageError = false;
  int checkinCalls = 0;
  int refreshCalls = 0;
  Completer<void>? gate;
  Completer<void>? refreshGate;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshIfDue(AuthStore auth, {bool force = false}) async {
    refreshCalls++;
    final pending = refreshGate;
    if (pending != null) await pending.future;
  }

  @override
  String? get lastError => null;

  @override
  int pendingCount(AuthStore auth) => 0;

  @override
  DailyTasksSnapshot? snapshotFor(AuthStore auth) => DailyTasksSnapshot(
    day: '2026-10-23',
    checkedToday: done,
    streak: done ? 1 : 0,
    points: done ? 20 : 10,
    growth: const UserGrowth(),
    tasks: [
      TaskInfo(
        key: 'checkin',
        eventKey: 'checkin',
        label: '每日签到',
        done: done,
        reward: 10,
        progress: done ? 1 : 0,
        target: 1,
      ),
    ],
  );

  @override
  List<TaskInfo> visibleTasks(AuthStore auth) => snapshotFor(auth)!.tasks;

  @override
  Future<({bool alreadyChecked, int reward, int streak})> checkin(
    AuthStore auth,
  ) async {
    checkinCalls++;
    final pending = gate;
    if (pending != null) await pending.future;
    if (failNext) {
      failNext = false;
      throw ApiException('服务暂时不可用');
    }
    if (throwStorageError) {
      throw const FileSystemException('disk full');
    }
    done = true;
    notifyListeners();
    return (alreadyChecked: false, reward: 10, streak: 1);
  }
}

Future<AuthStore> _auth() async {
  final auth = AuthStore();
  await auth.signIn('token-a', _user());
  return auth;
}

Widget _page(AuthStore auth, _FakeActivity activity) => MaterialApp(
  home: TasksPage(auth: auth, activity: activity),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('condition was not met');
}

void main() {
  testWidgets('check-in replaces its button with an indeterminate bar', (
    tester,
  ) async {
    final auth = await _auth();
    final activity = _FakeActivity()..gate = Completer<void>();

    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();
    expect(find.text('签到'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('签到'));
    await _pumpUntil(tester, () => activity.checkinCalls == 1);
    await tester.pump();

    // The button is gone immediately and its slot shows the progress bar,
    // alongside the task's own determinate progress.
    expect(find.text('签到'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));

    activity.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('签到'), findsNothing);
    expect(find.text('签到成功，获得 10 积分，已连续 1 天'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a failed check-in is inline, retryable and clears progress', (
    tester,
  ) async {
    final auth = await _auth();
    final activity = _FakeActivity()..failNext = true;

    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();

    await tester.tap(find.text('签到'));
    await tester.pumpAndSettle();

    expect(activity.checkinCalls, 1);
    expect(find.text('服务暂时不可用'), findsNWidgets(2));
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('签到'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Let the failure snackbar expire before retrying so its text does not
    // linger in the tree.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('服务暂时不可用'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(activity.checkinCalls, 2);
    expect(find.text('服务暂时不可用'), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(find.text('签到'), findsNothing);
    expect(find.text('1/1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an unknown check-in error is inline and not retryable', (
    tester,
  ) async {
    final auth = await _auth();
    final activity = _FakeActivity()..throwStorageError = true;

    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();

    await tester.tap(find.text('签到'));
    await tester.pumpAndSettle();

    expect(activity.checkinCalls, 1);
    expect(find.text('签到结果未知，请刷新任务确认，避免重复签到'), findsOneWidget);
    // No immediate retry action, because the server may already have succeeded.
    expect(find.text('重试'), findsNothing);
    expect(find.text('刷新确认'), findsOneWidget);
    // A duplicate claim must not be implied to be safe.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '签到'),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('refresh confirmation re-enables an uncertain check-in', (
    tester,
  ) async {
    final auth = await _auth();
    final activity = _FakeActivity()..throwStorageError = true;

    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();
    await tester.tap(find.text('签到'));
    await tester.pumpAndSettle();

    expect(find.text('刷新确认'), findsOneWidget);
    final disabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '签到'),
    );
    expect(disabled.onPressed, isNull);

    await tester.tap(find.text('刷新确认'));
    await tester.pumpAndSettle();

    // The fake refresh reports the task is still pending, so the user may
    // check in again once the server confirms.
    expect(find.text('签到结果未知，请刷新任务确认，避免重复签到'), findsNothing);
    expect(find.text('刷新确认'), findsNothing);
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '签到'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('a rotated token cannot confirm an uncertain check-in', (
    tester,
  ) async {
    final auth = await _auth();
    final activity = _FakeActivity()..throwStorageError = true;

    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();
    await tester.tap(find.text('签到'));
    await tester.pumpAndSettle();

    activity.refreshGate = Completer<void>();
    final refreshCalls = activity.refreshCalls;
    await tester.tap(find.text('刷新确认'));
    await _pumpUntil(tester, () => activity.refreshCalls == refreshCalls + 1);

    // The service discards responses issued with the previous token. Keeping
    // the same account/day must not turn its cached snapshot into confirmation.
    await auth.signIn('rotated-token', _user());
    activity.refreshGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('刷新确认'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '签到'))
          .onPressed,
      isNull,
    );

    // A later refresh for the current token can confirm the pending task.
    activity.refreshGate = null;
    await tester.tap(find.text('刷新确认'));
    await tester.pumpAndSettle();
    expect(find.text('刷新确认'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '签到'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('uncertain check-in state is scoped to the account and day', (
    tester,
  ) async {
    final auth = await _auth();
    final activity = _FakeActivity()..throwStorageError = true;

    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();
    await tester.tap(find.text('签到'));
    await tester.pumpAndSettle();

    expect(find.text('刷新确认'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '签到'))
          .onPressed,
      isNull,
    );

    // A different account must not inherit A's uncertain state or message.
    await auth.signIn('token-b', _userB());
    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();
    expect(find.text('签到结果未知，请刷新任务确认，避免重复签到'), findsNothing);
    expect(find.text('刷新确认'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '签到'))
          .onPressed,
      isNotNull,
    );

    // Going back to A restores A's pending confirmation.
    await auth.signIn('token-a', _user());
    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();
    expect(find.text('刷新确认'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '签到'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('check-in feedback is suppressed after an account switch', (
    tester,
  ) async {
    final auth = await _auth();
    final activity = _FakeActivity()..gate = Completer<void>();

    await tester.pumpWidget(_page(auth, activity));
    await tester.pumpAndSettle();
    await tester.tap(find.text('签到'));
    await _pumpUntil(tester, () => activity.checkinCalls == 1);
    await tester.pump();

    await auth.signIn('token-b', _userB());
    activity.gate!.complete();
    await tester.pumpAndSettle();

    // The request belonged to A; B must not receive its success feedback.
    expect(find.textContaining('签到成功'), findsNothing);
    expect(find.text('签到结果未知，请刷新任务确认，避免重复签到'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/pages/auth/account_login_page.dart';
import 'package:qfli_studio_core/pages/auth/login_page.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/ohos_safe_area.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

import 'support/ohos_target.dart';

const _channel = MethodChannel(OhosSafeArea.channelName);
const _huaweiChannel = MethodChannel('qflistudio/huawei_account');

/// Top avoid area the fake host reports, in logical pixels.
double _hostTop = 0;

/// Answers the host safe-area channel with [top] logical pixels. The handler
/// is installed per test, because the test framework drops mock handlers as
/// soon as a test finishes.
void _answerSafeAreaChannel({double top = 0}) {
  _hostTop = top;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (call.method != 'getSafeArea') return null;
        return <String, Object>{'top': _hostTop, 'topPx': _hostTop * 3.5};
      });
}

/// Runs [body] with [platform] reported to widgets and restores the default
/// before the framework checks its invariants.
Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Pumps until async channel answers have been delivered.
Future<void> _pumpHostAnswer(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // The host reports the current avoid area whenever the window changes. The
  // fake host channel is dropped when a case ends, so each case replays the
  // last report through the test-only refetch.
  setUp(() async {
    messenger.setMockMethodCallHandler(_huaweiChannel, (call) async => null);
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method != 'getSafeArea') return null;
      return <String, Object>{'top': _hostTop, 'topPx': _hostTop * 3.5};
    });
    OhosSafeArea.debugRefetch();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  tearDown(() {
    OhosSafeArea.debugResetTopAvoid();
    messenger.setMockMethodCallHandler(_huaweiChannel, null);
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('HarmonyOS login page offers only Huawei one-tap login', (
    tester,
  ) async {
    _answerSafeAreaChannel();

    await _withPlatform(ohosPlatform, () async {
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: AuthStore())));
      await _pumpHostAnswer(tester);

      expect(find.text('其他方式登录'), findsNothing);
      expect(find.textContaining('注册'), findsNothing);
      expect(find.text('欢迎回到 QFLIStudioN'), findsOneWidget);

      // Starts the avoid-area listener, which owns pending timers. Drop the
      // tree and let them finish inside this test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  testWidgets('Non-HarmonyOS login page keeps the alternate login entry', (
    tester,
  ) async {
    _answerSafeAreaChannel();

    await _withPlatform(TargetPlatform.android, () async {
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: AuthStore())));
      await _pumpHostAnswer(tester);

      expect(find.text('其他方式登录'), findsOneWidget);
    });
  });

  testWidgets('Binding page without a phone number blocks skipping', (
    tester,
  ) async {
    _answerSafeAreaChannel();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountLoginPage(
          auth: AuthStore(),
          bindingId: 'binding-1',
          phoneAvailable: false,
        ),
      ),
    );
    await _pumpHostAnswer(tester);

    // 网关在没有已验证手机号时拒绝绑定，也不允许用 skip 建号。
    expect(find.text('新建账号'), findsNothing);
    expect(find.text('绑定并登录'), findsOneWidget);
    expect(find.text('请使用已绑定手机号的华为账号'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('Binding page offers binding and account creation', (
    tester,
  ) async {
    _answerSafeAreaChannel();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountLoginPage(
          auth: AuthStore(),
          bindingId: 'binding-1',
          phoneAvailable: true,
        ),
      ),
    );
    await _pumpHostAnswer(tester);

    // Skip is the only way a new user creates an account, so it stays.
    expect(find.text('新建账号'), findsOneWidget);
    expect(find.text('绑定并登录'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Host reported cutout inset is added above the login content', (
    tester,
  ) async {
    _answerSafeAreaChannel(top: 44);
    await OhosSafeArea.debugRefetch();

    await _withPlatform(TargetPlatform.android, () async {
      // A host answer is only pushed when the window changes, so restate the
      // current state here.
      OhosSafeArea.ensureListening();
      await tester.pump(const Duration(milliseconds: 20));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: MaterialApp(home: LoginPage(auth: AuthStore())),
        ),
      );
      await _pumpHostAnswer(tester);

      // Identity of the page's own scroll view, so the assertion cannot match
      // some other scrollable in the tree.
      final pageTop =
          tester
                  .widget<SingleChildScrollView>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is SingleChildScrollView &&
                          widget.padding is EdgeInsets &&
                          (widget.padding! as EdgeInsets).left == 24,
                    ),
                  )
                  .padding
              as EdgeInsets;

      // The viewport reports no status bar, so the only top padding above the
      // 28px layout value comes from the host inset.
      expect(pageTop.top, greaterThanOrEqualTo(28 + 44));
    });
  });

  group('Huawei rejections', () {
    final phoneRequired = ApiException(
      '请使用已绑定手机号的华为账号',
      statusCode: 403,
      details: {'errorKey': 'huawei.phone_required'},
    );

    test('a missing phone number shows the server guidance', () {
      expect(LoginPage.loginErrorMessage(phoneRequired), '请使用已绑定手机号的华为账号');
    });

    test('an empty server message still explains what to do', () {
      final bare = ApiException(
        ' ',
        statusCode: 403,
        details: {'errorKey': 'huawei.phone_required'},
      );
      expect(LoginPage.loginErrorMessage(bare), '请使用已绑定手机号的华为账号');
    });

    test('other rejections keep the server message', () {
      final other = ApiException(
        '华为账号授权失败',
        statusCode: 400,
        details: {'errorKey': 'huawei.invalid_code'},
      );
      expect(LoginPage.loginErrorMessage(other), '华为账号授权失败');
    });
  });
}


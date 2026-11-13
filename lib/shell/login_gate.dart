import 'package:flutter/material.dart';

import '../pages/auth/login_page.dart';
import '../store/auth_store.dart';

/// 把 [AuthStore] 提供给界面层的登录门控。
///
/// 现有代码靠构造函数逐层传 store，没有全局 provider。门控需要从任意
/// 子树的 `BuildContext` 拿到登录态，因此用一个作用域承载。见 design.md §5。
class LoginGateScope extends InheritedWidget {
  const LoginGateScope({super.key, required this.auth, required super.child});

  final AuthStore auth;

  static AuthStore? maybeAuthOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LoginGateScope>()
      ?.auth;

  static AuthStore authOf(BuildContext context) {
    final auth = maybeAuthOf(context);
    assert(auth != null, '缺少 LoginGateScope 祖先');
    return auth!;
  }

  @override
  bool updateShouldNotify(LoginGateScope oldWidget) =>
      !identical(auth, oldWidget.auth) || !identical(child, oldWidget.child);
}

/// 已登录返回 true。未登录时打开登录页，登录成功后返回 true。
///
/// 界面层门控。harness 层另有 `AgentRuntime.open` 抛
/// `AgentLoginRequired`，两层都要有。
Future<bool> ensureLoggedIn(BuildContext context) async {
  final auth = LoginGateScope.maybeAuthOf(context);
  if (auth == null) return false;
  if (auth.isLoggedIn) return true;
  final signedIn = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => LoginPage(auth: auth)),
  );
  return signedIn == true && auth.isLoggedIn;
}

/// 未登录时显示的登录引导卡片。
///
/// 只提示和引导，不弹错误。登录成功后回到原位置。见 design.md §4 第 5 条。
class LoginGuideCard extends StatelessWidget {
  const LoginGuideCard({super.key, this.compact = false});

  /// 窄容器下收紧内边距。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.all(compact ? 8 : 12),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '需要登录',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '登录后可以使用 Agent 会话、读写项目文件和调用技能。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('login-guide-action'),
                onPressed: () => ensureLoggedIn(context),
                child: const Text('登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

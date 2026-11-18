import 'package:flutter/widgets.dart';

import '../services/studio_profile.dart';

/// 工具条目的可见范围。
///
/// [everyone] 是现有工具的取值：任何产品都显示。[qfliStudioMainApp] 只给
/// 从 netrix 移植来的工具使用：只有主程序 qflistudio 显示，子项目不显示。
/// [product] 留给将来某个产品独占的工具。
enum ToolAudience { everyone, qfliStudioMainApp, product }

/// [ToolAudience] 的判定入口。
///
/// 判定依据是现有的应用配置 [StudioProfile.productKey]：主程序自己的
/// `main.dart` 把 productKey 设成 [StudioProductCatalog.qfliStudioKey]，
/// 各语言子项目设成自己的 key。这里只读配置，不修改
/// `lib/services/studio_profile.dart`。
///
/// 没有设置档位时（例如单元测试直接挂载工具页）不算主程序。这是保守选择：
/// 移植来的工具必须显式确认主程序身份才显示，子项目不会因为漏配而多出工具。
abstract final class ToolAudienceScope {
  /// 只有 productKey 等于主程序标识时才算主程序。
  static bool get isMainApp {
    final profile = StudioProfile.current;
    if (profile == null) return false;
    return profile.productKey == StudioProductCatalog.qfliStudioKey;
  }

  /// 工具页在当前产品下是否显示 [audience] 范围的工具。
  ///
  /// [isMainApp] 为 null 时按 [isMainApp] 判定；页面把测试用的覆盖传进来，
  /// 保证页面与注册表用的是同一个判定。
  static bool canSee(ToolAudience audience, {bool? isMainApp}) =>
      switch (audience) {
        ToolAudience.everyone => true,
        ToolAudience.qfliStudioMainApp =>
          isMainApp ?? ToolAudienceScope.isMainApp,
        ToolAudience.product => false,
      };

  /// 按可见范围过滤工具条目。顺序保持不变。
  static List<T> filter<T>(
    List<T> items,
    ToolAudience Function(T item) audience, {
    bool? isMainApp,
  }) {
    return [
      for (final item in items)
        if (canSee(audience(item), isMainApp: isMainApp)) item,
    ];
  }
}

/// 让子组件读到当前可见范围判定的工具范围。
///
/// 页面在 build 时按 [StudioProfile.current] 判定一次，再把它传给下属组件，
/// 避免每一行都重复读静态字段。需要测试另一种配置时直接传 [isMainApp]。
@immutable
class ToolScope extends InheritedWidget {
  const ToolScope({super.key, required this.isMainApp, required super.child});

  /// 按当前 [StudioProfile.current] 判定的范围。
  ToolScope.current({Key? key, required Widget child})
    : this(key: key, isMainApp: ToolAudienceScope.isMainApp, child: child);

  final bool isMainApp;

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ToolScope>();
    return scope?.isMainApp ?? ToolAudienceScope.isMainApp;
  }

  bool canSee(ToolAudience audience) => switch (audience) {
    ToolAudience.everyone => true,
    ToolAudience.qfliStudioMainApp => isMainApp,
    ToolAudience.product => false,
  };

  @override
  bool updateShouldNotify(ToolScope oldWidget) =>
      oldWidget.isMainApp != isMainApp;
}

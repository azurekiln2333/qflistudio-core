/// 鸿蒙本地运行工具的下载清单。
///
/// 每个条目对应一个可以从鸿蒙应用市场下载的应用。清单只回答「去哪里下载」：
/// 不承诺该应用一定能编译或运行某个语言，具体能力由各应用自己提供，
/// 新的运行时会陆续补充。
///
/// 产品名取自 [StudioProductCatalog]，不要按产品键拼 bundle 名：两者并不
/// 一一对应（例如 Dart 的产品键是 `dartwing`）。这里保留为单一事实来源，
/// 改名时只改这一处。
library;

import '../services/studio_profile.dart';

/// AppGallery 详情页的统一模板。
const String _storeUrlTemplate =
    'https://appgallery.huawei.com/app/detail'
    '?id=<bundleName>&channelId=SHARE&source=appshare';

/// 一个可下载的鸿蒙运行时应用。
class OhosRuntimeApp {
  const OhosRuntimeApp({
    required this.id,
    required this.name,
    required this.languageLabel,
    required this.languages,
    required this.bundleName,
    required this.iconAsset,
  });

  /// 稳定标识，同时是图标文件名（`assets/product_icons/<id>.png`）。
  final String id;

  /// 产品名，取自 [StudioProductCatalog]。
  final String name;

  /// 界面上展示的语言描述，例如 `C / C++`。
  final String languageLabel;

  /// 该条目对应的项目语言键，用于在界面上优先展示。
  ///
  /// 它只表示「这个 App 与哪些语言相关」，不代表该 App 一定能编译或运行
  /// 它们。空集表示不与任何具体语言对应。
  final Set<String> languages;

  /// 鸿蒙应用的 bundle 名，也是 AppGallery 链接的唯一参数。
  final String bundleName;

  /// 包内资源路径，需配合 `package: qfli_studio_core` 使用。
  final String iconAsset;

  /// AppGallery 详情页。
  Uri get storeUri =>
      Uri.parse(_storeUrlTemplate.replaceFirst('<bundleName>', bundleName));

  /// [language] 是否与该条目相关（忽略大小写与两端空白）。
  bool supports(String? language) {
    if (language == null) return false;
    final key = language.trim().toLowerCase();
    if (key.isEmpty) return false;
    return languages.contains(key);
  }
}

/// 下载列表，按用户理解的顺序排列：Java、C/C++、Go、Dart、Python、SQL、
/// Web、Rust，最后是多语言编辑器 Studio。
const List<OhosRuntimeApp> ohosRuntimeApps = <OhosRuntimeApp>[
  OhosRuntimeApp(
    id: 'java',
    name: StudioProductCatalog.jvmx,
    languageLabel: 'Java',
    languages: <String>{'java'},
    bundleName: 'com.azurekiln.qfli.java',
    iconAsset: 'assets/product_icons/java.png',
  ),
  OhosRuntimeApp(
    id: 'cpp',
    name: StudioProductCatalog.forge,
    languageLabel: 'C / C++',
    languages: <String>{'c', 'cpp', 'c++'},
    bundleName: 'com.azurekiln.qfli.cpp',
    iconAsset: 'assets/product_icons/cpp.png',
  ),
  OhosRuntimeApp(
    id: 'go',
    name: StudioProductCatalog.goShift,
    languageLabel: 'Go',
    languages: <String>{'go'},
    bundleName: 'com.azurekiln.qfli.go',
    iconAsset: 'assets/product_icons/go.png',
  ),
  OhosRuntimeApp(
    id: 'dart',
    name: StudioProductCatalog.dartWing,
    languageLabel: 'Dart',
    languages: <String>{'dart'},
    bundleName: 'com.azurekiln.qfli.dart',
    iconAsset: 'assets/product_icons/dart.png',
  ),
  OhosRuntimeApp(
    id: 'python',
    name: StudioProductCatalog.pyFlow,
    languageLabel: 'Python',
    languages: <String>{'python'},
    bundleName: 'com.azurekiln.qfli.pyflow',
    iconAsset: 'assets/product_icons/python.png',
  ),
  OhosRuntimeApp(
    id: 'sql',
    name: StudioProductCatalog.sqlab,
    languageLabel: 'SQL',
    languages: <String>{'sql'},
    bundleName: 'com.azurekiln.qfli.sql',
    iconAsset: 'assets/product_icons/sql.png',
  ),
  OhosRuntimeApp(
    id: 'web',
    name: StudioProductCatalog.webForge,
    languageLabel: 'Web 前端',
    languages: <String>{'web', 'html', 'css', 'javascript', 'typescript'},
    bundleName: 'com.azurekiln.qfli.web',
    iconAsset: 'assets/product_icons/web.png',
  ),
  OhosRuntimeApp(
    id: 'rust',
    name: StudioProductCatalog.rustCore,
    languageLabel: 'Rust',
    languages: <String>{'rust'},
    bundleName: 'com.azurekiln.qfli.rust',
    iconAsset: 'assets/product_icons/rust.png',
  ),
  OhosRuntimeApp(
    id: 'studio',
    name: StudioProductCatalog.qfliStudio,
    languageLabel: '多语言编辑器',
    // Studio 是多语言编辑器，不与具体语言对应。
    languages: <String>{},
    bundleName: 'com.azurekiln.qflistudio',
    iconAsset: 'assets/product_icons/studio.png',
  ),
];

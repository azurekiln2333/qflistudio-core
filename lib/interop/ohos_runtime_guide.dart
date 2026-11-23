import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/studio_localizations.dart';
import 'ohos_runtime_catalog.dart';

/// 打开一条鸿蒙本地运行工具的安装页。
///
/// 默认走 `qflistudio/platform` 的 `openUrl`。该通道会真实抛出失败，
/// 因此调用方能看到错误并重试。`RunnerService.openUrl` 会吞掉异常，
/// 这里不用它。
typedef OhosStoreOpener = Future<void> Function(Uri uri);

/// 平台通道名，与 `qflistudio/platform` 保持一致。
const String _platformChannelName = 'qflistudio/platform';

/// 默认打开方式：把完整 HTTPS 地址交给原生侧。
///
/// 失败原样抛出：缺通道、平台拒绝或其他异常都交给界面显示。
Future<void> _defaultOpenStore(Uri uri) async {
  const channel = MethodChannel(_platformChannelName);
  await channel.invokeMethod<void>('openUrl', <String, Object?>{
    'url': uri.toString(),
  });
}

/// 打开鸿蒙本地运行工具的下载指引。
///
/// 只推入一个普通 [MaterialPageRoute]。页面跟随根主题与本地化。
/// [language] 是当前项目语言，用于把对应工具排到最前并高亮。
Future<void> showOhosRuntimeGuide(
  BuildContext context, {
  String? language,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => OhosRuntimeGuide(language: language),
    ),
  );
}

/// 九个鸿蒙本地运行工具的安装指引页。
///
/// 窄屏按列表排，宽屏按网格排。工具栏只说明当前语言要装哪个工具，
/// 其余工具仍然可见，不隐藏。
class OhosRuntimeGuide extends StatefulWidget {
  const OhosRuntimeGuide({super.key, this.language, this.openStore});

  /// 当前项目语言，例如 `python`。为空时按目录原顺序显示。
  final String? language;

  /// 打开安装页的方式。默认走平台通道，测试可替换。
  final OhosStoreOpener? openStore;

  @override
  State<OhosRuntimeGuide> createState() => _OhosRuntimeGuideState();
}

class _OhosRuntimeGuideState extends State<OhosRuntimeGuide> {
  /// 正在打开的工具 id。同一时刻只允许一条请求。
  String? _opening;

  /// 最近一次失败，用于对话框显示。
  String? _failedLink;

  OhosStoreOpener get _openStore => widget.openStore ?? _defaultOpenStore;

  @override
  Widget build(BuildContext context) {
    final l = StudioLocalizations.of(context);
    final apps = _orderedApps();
    final preferred = _preferredApp();
    return Scaffold(
      appBar: AppBar(title: Text(_title(l))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 720 是侧栏展开后仍能放下两列卡片的宽度。
            final wide = constraints.maxWidth >= 720;
            // 固定高度的网格单元要随文字缩放一起长，否则大字号会溢出。
            final scaled = MediaQuery.textScalerOf(context)
                .scale(1.0)
                .clamp(1.0, 2.0);
            final extent = (wide ? 168.0 : 152.0) * scaled;
            return CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(_intro(l, preferred)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverGrid.builder(
                    // 720px 以下固定单列。
                    gridDelegate: wide
                        ? SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 360,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            mainAxisExtent: extent,
                          )
                        : SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            mainAxisSpacing: 12,
                            mainAxisExtent: extent,
                          ),
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return _AppCard(
                        app: app,
                        highlighted: identical(app, preferred),
                        busy: _opening == app.id,
                        onInstall: () => _install(app, l),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 当前语言对应的工具排在最前，其余保持目录顺序。
  List<OhosRuntimeApp> _orderedApps() {
    final preferred = _preferredApp();
    if (preferred == null) return ohosRuntimeApps;
    return <OhosRuntimeApp>[
      preferred,
      for (final app in ohosRuntimeApps)
        if (!identical(app, preferred)) app,
    ];
  }

  /// 找出与项目语言匹配的工具。
  ///
  /// Studio 是多语言编辑器，不是运行工具，永远不作为推荐项。
  /// 语言为空或不认识时返回 null：目录顺序不变，也没有高亮。
  OhosRuntimeApp? _preferredApp() {
    final language = widget.language;
    if (language == null || language.trim().isEmpty) return null;
    for (final app in ohosRuntimeApps) {
      if (_isStudio(app)) continue;
      // 用清单自己的匹配规则，让语言键只在一处定义。
      if (app.supports(language)) return app;
    }
    return null;
  }

  /// Studio 用固定 id 识别，避免运行时被当成本语言工具。
  static bool _isStudio(OhosRuntimeApp app) => app.id.toLowerCase() == 'studio';

  Future<void> _install(
    OhosRuntimeApp app,
    StudioLocalizations l,
  ) async {
    if (_opening != null) return;
    setState(() {
      _opening = app.id;
      _failedLink = null;
    });
    try {
      await _openStore(app.storeUri);
    } catch (_) {
      // 失败必须让用户看见：给重试与复制链接两条路。
      if (!mounted) return;
      // 先释放锁，否则重试会在 _install 开头被当成重入直接返回。
      setState(() {
        _opening = null;
        _failedLink = app.storeUri.toString();
      });
      await _showFailureDialog(app, l);
      return;
    }
    if (mounted) setState(() => _opening = null);
  }

  Future<void> _showFailureDialog(
    OhosRuntimeApp app,
    StudioLocalizations l,
  ) async {
    final link = _failedLink;
    if (link == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // 320px 宽、2 倍字号下内容会超出屏幕，必须可滚动。
        scrollable: true,
        title: Text(_failedTitle(l)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_failedBody(l)),
            const SizedBox(height: 12),
            SelectableText(
              link,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_copied(l))),
                );
              }
            },
            child: Text(_copyLink(l)),
          ),
          TextButton(
            onPressed: () {
              // 关掉对话框后重新发起安装。此时 _opening 已释放。
              Navigator.of(dialogContext).pop();
              if (mounted) unawaited(_install(app, l));
            },
            child: Text(_retry(l)),
          ),
        ],
      ),
    );
  }

  String _title(StudioLocalizations l) => l.isEnglish
      ? 'Local runtime tools'
      : l.isTraditionalChinese
      ? '本機執行工具'
      : '本地运行工具';

  String _intro(StudioLocalizations l, OhosRuntimeApp? preferred) {
    final base = l.isEnglish
        ? 'Download the tool for your language from AppGallery, '
              'then return to Studio to continue.'
        : l.isTraditionalChinese
        ? '從 AppGallery 下載對應語言的工具，安裝後返回 Studio 繼續操作。'
        : '在 AppGallery 下载对应语言的工具，安装后返回 Studio 继续操作。';
    if (preferred == null) return base;
    final hint = l.isEnglish
        ? 'This project uses ${preferred.name}.'
        : l.isTraditionalChinese
        ? '這個專案使用 ${preferred.name}。'
        : '这个项目使用 ${preferred.name}。';
    return '$hint\n$base';
  }

  String _failedTitle(StudioLocalizations l) => l.isEnglish
      ? 'Could not open AppGallery'
      : l.isTraditionalChinese
      ? '無法開啟 AppGallery'
      : '无法打开 AppGallery';

  String _failedBody(StudioLocalizations l) => l.isEnglish
      ? 'Copy the link and open it in a browser.'
      : l.isTraditionalChinese
      ? '複製連結後在瀏覽器開啟。'
      : '复制链接后在浏览器打开。';

  String _copyLink(StudioLocalizations l) => l.isEnglish
      ? 'Copy link'
      : l.isTraditionalChinese
      ? '複製連結'
      : '复制链接';

  String _retry(StudioLocalizations l) => l.isEnglish
      ? 'Retry'
      : l.isTraditionalChinese
      ? '重試'
      : '重试';

  String _copied(StudioLocalizations l) => l.isEnglish
      ? 'Link copied'
      : l.isTraditionalChinese
      ? '已複製連結'
      : '已复制链接';
}

/// 单个工具卡片：图标、名称、语言与安装按钮。
class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.highlighted,
    required this.busy,
    required this.onInstall,
  });

  final OhosRuntimeApp app;
  final bool highlighted;
  final bool busy;
  final VoidCallback onInstall;

  /// 卡片满高铺开，按钮始终留在可见区。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: highlighted
          ? scheme.primaryContainer.withValues(alpha: 0.45)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _icon(scheme),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        app.id == 'studio'
                            ? (StudioLocalizations.of(context).isEnglish
                                  ? 'Multi-language editor'
                                  : StudioLocalizations.of(context).isTraditionalChinese
                                  ? '多語言編輯器'
                                  : '多语言编辑器')
                            : app.id == 'web'
                            ? 'Web'
                            : app.languageLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              // 触控目标至少 44 高。
              height: 44,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : onInstall,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: Text(
                  StudioLocalizations.of(context).isEnglish
                      ? 'Download'
                      : StudioLocalizations.of(context).isTraditionalChinese
                      ? '下載'
                      : '下载',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 图标来自 Core 自己的 assets，必须带包名。
  Widget _icon(ColorScheme scheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        app.iconAsset,
        package: 'qfli_studio_core',
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        // 资源缺失时不报错，退回一个通用图标。
        errorBuilder: (context, error, stack) => Container(
          width: 40,
          height: 40,
          color: scheme.surfaceContainerHighest,
          child: Icon(
            Icons.extension_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

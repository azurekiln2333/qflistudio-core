import 'package:flutter/material.dart';

import '../i18n/studio_localizations.dart';
import '../services/studio_profile.dart';
import '../store/project_store.dart';
import 'content_tools_pages.dart';
import 'terminax_terminal_page.dart';

/// 主页的功能页。
class FunctionsTab extends StatelessWidget {
  const FunctionsTab({
    super.key,
    required this.onOpenTerminal,
    this.onOpenContentTool,
  });

  final VoidCallback onOpenTerminal;
  final VoidCallback? onOpenContentTool;

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tools)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _QuickToolTile(
            icon: Icons.terminal,
            title: l10n.terminal,
            subtitle: l10n.terminalSubtitle,
            onTap: onOpenTerminal,
          ),
          if (onOpenContentTool != null) ...[
            const SizedBox(height: 8),
            _QuickToolTile(
              icon: switch (StudioProfile.current?.productKey) {
                StudioProductCatalog.webForgeKey => Icons.language,
                StudioProductCatalog.jsonKey => Icons.data_object,
                StudioProductCatalog.noteKey => Icons.article_outlined,
                StudioProductCatalog.sqlabKey => Icons.storage_outlined,
                _ => Icons.build_outlined,
              },
              title: switch (StudioProfile.current?.productKey) {
                StudioProductCatalog.webForgeKey => 'Web 工具',
                StudioProductCatalog.jsonKey => l10n.jsonTools,
                StudioProductCatalog.noteKey => l10n.markdownTools,
                StudioProductCatalog.sqlabKey => l10n.sqlTools,
                _ => l10n.functions,
              },
              subtitle: switch (StudioProfile.current?.productKey) {
                StudioProductCatalog.webForgeKey => '本地服务、HTTP 请求与编解码',
                StudioProductCatalog.jsonKey => l10n.jsonStructure,
                StudioProductCatalog.noteKey => l10n.markdownPreview,
                StudioProductCatalog.sqlabKey => l10n.executeQuery,
                _ => l10n.functions,
              },
              onTap: onOpenContentTool!,
            ),
          ],
        ],
      ),
    );
  }
}

class ContentToolsPage extends StatelessWidget {
  const ContentToolsPage({super.key, required this.store});

  final ProjectStore store;

  @override
  Widget build(BuildContext context) {
    final profile = StudioProfile.current;
    final customTools = profile?.toolsPageBuilder;
    if (customTools != null) return customTools(store);
    return switch (profile?.productKey) {
      StudioProductCatalog.jsonKey => const JsonToolPage(),
      StudioProductCatalog.noteKey => const MarkdownToolPage(),
      StudioProductCatalog.sqlabKey => SqlToolPage(projectPath: _projectPath),
      _ => Scaffold(
        appBar: AppBar(title: Text(StudioLocalizations.of(context).tools)),
        body: const SizedBox.shrink(),
      ),
    };
  }

  String? get _projectPath {
    for (final project in store.projects) {
      if (!project.isCloud) return project.path;
    }
    return null;
  }
}

@Deprecated('Use FunctionsTab')
typedef QuickToolsTab = FunctionsTab;

class _QuickToolTile extends StatelessWidget {
  const _QuickToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// 全屏本地终端页。
///
/// 与应用其它入口共用同一个终端实现（[TerminaxTerminalPage] +
/// `TerminalManager` + 沙盒后端），不再单独维护一套命令引擎；沙盒根为应用私有
/// 数据目录，可访问其中各个项目文件。
class LocalTerminalPage extends StatelessWidget {
  const LocalTerminalPage({super.key, required this.store});

  final ProjectStore store;

  @override
  Widget build(BuildContext context) => TerminaxTerminalPage(store: store);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/project_templates.dart';
import '../services/studio_profile.dart';

/// The app version shown on the About page.
///
/// Kept in sync with `pubspec.yaml`'s `version:` field. It is a shared constant
/// so widget tests can assert the visible string without hardcoding it twice.
const String kQfliAboutVersion = '1.0.0';

/// Fallback for local products without a recognized language or document type.
const String kQfliOfflineDescription =
    '本地项目编辑工具。管理项目与文件，编辑内容，查阅教程与示例，并使用内置终端处理文件。';

/// Networked products keep the community-oriented description.
const String kQfliOnlineDescription =
    '多语言代码编辑器与开发者社区。管理本地与云端项目，编写代码，查阅教程与示例，交流开发经验。';

const String _feedbackGroup = '694120628';

String _descriptionFor(StudioProfile? profile) {
  if (profile == null || !profile.offlineOnly) return kQfliOnlineDescription;

  // Legacy profiles may only set an id; current products use the stable key.
  final identity = profile.productKey == StudioProductCatalog.qfliStudioKey
      ? profile.id
      : profile.productKey;
  final subject = switch (identity) {
    StudioProductCatalog.jvmxKey || 'java' => 'Java',
    StudioProductCatalog.pyFlowKey || 'python' => 'Python',
    StudioProductCatalog.forgeKey || 'c' || 'cpp' => 'C / C++',
    StudioProductCatalog.rustCoreKey || 'rust' => 'Rust',
    StudioProductCatalog.goShiftKey || 'go' => 'Go',
    StudioProductCatalog.dartWingKey || 'dart' => 'Dart',
    StudioProductCatalog.webForgeKey || 'web' => 'Web',
    StudioProductCatalog.sqlabKey || 'sql' => 'SQL',
    StudioProductCatalog.noteKey || 'markdown' => 'Markdown',
    StudioProductCatalog.scriptKey => '脚本',
    StudioProductCatalog.jsonKey => 'JSON',
    _ =>
      profile.templates
          .where((template) => template != ProjectTemplate.empty)
          .map((template) => template.language)
          .toSet()
          .join(' / '),
  };
  if (subject.isEmpty) return kQfliOfflineDescription;

  final introduction = switch (subject) {
    'Web' => 'Web 项目编辑工具。管理本地网页项目，编辑 HTML、CSS 和 JavaScript',
    'SQL' => 'SQL 学习与编辑工具。管理本地项目与 SQL 脚本，编写查询',
    'JSON' => 'JSON 数据编辑工具。管理本地项目与 JSON 文件，编辑结构化数据',
    'Markdown' => 'Markdown 写作工具。管理本地项目与 Markdown 文档，编写笔记',
    '脚本' => '脚本开发工具。管理本地项目与脚本，编辑源码',
    _ => '$subject 开发工具。管理本地项目，编辑 $subject 源码',
  };
  final execution = subject == 'Java' && profile.runtimeStatus == 'available'
      ? '，使用 JDK（javac / java）在本地编译和运行程序'
      : '';
  return '$introduction$execution，查阅教程与示例，并使用内置终端处理文件。';
}

Future<void> _copyFeedbackGroup(BuildContext context) async {
  String message;
  try {
    await Clipboard.setData(const ClipboardData(text: _feedbackGroup));
    message = '群号已复制，可粘贴到 QQ 搜索';
  } on PlatformException {
    message = '复制失败，请长按群号手动复制';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Each host supplies its own app icon under the same asset key as startup.
class _AboutAppIcon extends StatelessWidget {
  const _AboutAppIcon({required this.appTitle, this.size = 80});

  final String appTitle;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 4),
    child: Image.asset(
      'assets/app_icon.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: '$appTitle 应用图标',
      // The core package can also be previewed without a host asset bundle.
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: SizedBox.square(
          dimension: size,
          child: Icon(
            Icons.apps_rounded,
            size: size / 2,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    ),
  );
}

/// Opens the product About page as a normal secondary route.
///
/// This is the single entry point used by Profile and Settings. It preserves
/// the original helper signature so existing callers keep working, but it now
/// pushes a full page (with platform Back) instead of an [AboutDialog].
///
/// The pushed page reads [StudioProfile.current] when it builds, so tests and
/// language products always see the active identity.
void showQfliAbout(BuildContext context) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (context) => const AboutPage()),
  );
}

/// Product identity, version, offline description and open-source licenses.
///
/// A normal scrollable secondary page: it is narrow-screen and large-text
/// friendly, and returns through the platform Back button or the AppBar's
/// leading control.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = StudioProfile.current;
    final appTitle = profile?.appTitle ?? StudioProductCatalog.qfliStudio;
    final description = _descriptionFor(profile);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Center(child: _AboutAppIcon(appTitle: appTitle)),
            const SizedBox(height: 20),
            Text(
              appTitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '版本 $kQfliAboutVersion',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _copyFeedbackGroup(context),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.forum_outlined, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '反馈与交流',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('QQ 交流群'),
                      const SizedBox(height: 4),
                      SelectableText(
                        _feedbackGroup,
                        style: Theme.of(context).textTheme.titleLarge,
                        onTap: () => _copyFeedbackGroup(context),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _copyFeedbackGroup(context),
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('复制群号'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('开源许可'),
                subtitle: const Text('查看本应用使用的开源组件及其许可证'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: appTitle,
                  applicationVersion: kQfliAboutVersion,
                  applicationIcon: _AboutAppIcon(appTitle: appTitle, size: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/studio_profile.dart';

/// The app version shown on the About page.
///
/// Kept in sync with `pubspec.yaml`'s `version:` field. It is a shared constant
/// so widget tests can assert the visible string without hardcoding it twice.
const String kQfliAboutVersion = '1.0.0';

/// Offline products describe themselves as a local-only code editor.
const String kQfliOfflineDescription = '离线代码编辑器。管理本地项目，编写代码，学习教程与示例。';

/// Networked products keep the community-oriented description.
const String kQfliOnlineDescription = '轻量代码编辑器与开发者社区。管理项目，编写代码，分享你的经验。';

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
    final offline = profile?.offlineOnly ?? false;
    final description = offline
        ? kQfliOfflineDescription
        : kQfliOnlineDescription;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.code_rounded, size: 40),
              ),
            ),
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
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('开源许可'),
                subtitle: const Text('查看本应用使用的开源组件及其许可证'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: appTitle,
                  applicationVersion: kQfliAboutVersion,
                  applicationIcon: const Icon(Icons.code_rounded, size: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

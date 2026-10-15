import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../editor/ai_panel.dart';
import '../services/app_backup_service.dart';
import '../services/app_paths.dart';
import '../services/file_backup.dart';
import '../services/picker_service.dart';
import '../services/studio_profile.dart';
import '../store/auth_store.dart';
import '../store/settings_store.dart';
import '../store/project_store.dart';
import '../widgets/settings_section.dart';
import 'highlight_settings_page.dart';
import 'editor_font_settings_page.dart';
import '../editor/editor_fonts.dart';

// 保留旧入口的可用性：调用方仍可从设置页拿到 showQfliAbout。
export 'about_page.dart' show showQfliAbout;

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    this.auth,
    this.store,
    this.showAi = true,
  });

  final SettingsStore settings;
  final AuthStore? auth;
  final ProjectStore? store;
  final bool showAi;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Future<String?> _backupDirectory = _backupPath();

  /// Non-null while an export/import runs. Disables both entries and drives the
  /// progress row so a second operation can never start concurrently.
  String? _busyLabel;

  /// Set in [dispose]; guards every post-await `setState` / context use.
  bool _disposed = false;

  SettingsStore get settings => widget.settings;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                SettingsSection(
                  title: '外观与体验',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.brightness_6_outlined),
                      title: const Text('外观'),
                      subtitle: Text(switch (settings.themeMode) {
                        'light' => '浅色',
                        'dark' => '深色',
                        _ => '跟随系统',
                      }),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickThemeMode,
                    ),
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('代码高亮'),
                      subtitle: const Text('配色、TextMate 与自定义语法'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              HighlightSettingsPage(settings: settings),
                        ),
                      ),
                    ),
                  ],
                ),
                SettingsSection(
                  title: '编辑器',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.text_fields),
                      title: const Text('编辑器字体'),
                      subtitle: Text(
                        '${EditorFonts.choices[settings.editorFont]} · ${settings.editorFontSize.toStringAsFixed(1)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              EditorFontSettingsPage(settings: settings),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.map_outlined),
                      title: const Text('代码鸟瞰图'),
                      subtitle: const Text('在编辑器右侧快速定位代码'),
                      value: settings.minimap,
                      onChanged: settings.setMinimap,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.tab_outlined),
                      title: const Text('文件标签栏'),
                      subtitle: const Text('在编辑器顶部显示已打开的文件'),
                      value: settings.showEditorTabs,
                      onChanged: settings.setShowEditorTabs,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.autorenew_outlined),
                      title: const Text('自动保存'),
                      subtitle: const Text('每次修改后立即保存'),
                      value: settings.autoSave,
                      onChanged: settings.setAutoSave,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.history_outlined),
                      title: const Text('历史版本备份'),
                      subtitle: const Text('自动保存和云同步覆盖文件前保留上一版本'),
                      value: settings.backupEnabled,
                      onChanged: settings.setBackupEnabled,
                    ),
                  ],
                ),
                if (widget.showAi)
                  SettingsSection(
                    title: 'AI 助手',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('个人 AI 接口'),
                        subtitle: Text(
                          settings.aiModel.isEmpty
                              ? '连接你自己的 AI 服务与密钥'
                              : settings.aiModel,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => editAiSettings(context, settings),
                      ),
                    ],
                  ),
                SettingsSection(
                  title: '数据与存储',
                  children: [
                    FutureBuilder<String?>(
                      future: _backupDirectory,
                      builder: (context, snapshot) => ListTile(
                        leading: const Icon(Icons.folder_copy_outlined),
                        title: const Text('历史备份目录'),
                        subtitle: Text(
                          snapshot.data ??
                              (snapshot.connectionState == ConnectionState.done
                                  ? '暂时无法读取目录'
                                  : '正在读取…'),
                        ),
                      ),
                    ),
                    const ListTile(
                      leading: Icon(Icons.delete_sweep_outlined),
                      title: Text('项目回收站'),
                      subtitle: Text(
                        '删除的项目会保存在应用数据目录的 recyclebin/projects_bin 中',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: const Text('导出全部数据'),
                      subtitle: const Text(
                        '打包设置、项目（含二进制资源）、索引与缓存为 .qfliz 备份',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: _busyLabel == null,
                      onTap: _busyLabel == null ? _exportAllData : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: const Text('导入全部数据'),
                      subtitle: const Text(
                        '校验后暂存，下次启动应用时替换当前数据（不可撤销）',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: _busyLabel == null,
                      onTap: _busyLabel == null ? _importAllData : null,
                    ),
                    if (_busyLabel != null)
                      ListTile(
                        leading: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        title: Text(_busyLabel!),
                        subtitle: const LinearProgressIndicator(minHeight: 3),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickThemeMode() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('外观'),
        children: [
          for (final entry in const [
            ('system', '跟随系统', Icons.brightness_auto_outlined),
            ('light', '浅色', Icons.light_mode_outlined),
            ('dark', '深色', Icons.dark_mode_outlined),
          ])
            ListTile(
              leading: Icon(entry.$3),
              title: Text(entry.$2),
              trailing: settings.themeMode == entry.$1
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(context, entry.$1),
            ),
        ],
      ),
    );
    if (picked != null) await settings.setThemeMode(picked);
  }

  /// 导出全部数据。
  ///
  /// 顺序：先让用户选定目标（便宜、可取消），再流式导出到临时目录（昂贵），
  /// 最后 `File.copy` 到本地目标或只为 URI 目标读取压缩字节。临时文件无论
  /// 成功、失败、取消还是页面销毁都会清理。
  Future<void> _exportAllData() async {
    if (_busyLabel != null) return;
    final productKey =
        StudioProfile.current?.productKey ?? StudioProductCatalog.qfliStudioKey;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;

    // 选定目标在昂贵导出之前；用户取消不产生任何临时文件。
    _setBusy('正在准备导出…');
    try {
      final location = await PickerService.saveDocument(
        suggestedName: 'qfli-$productKey-$stamp.qfliz',
      );
      // Disposal can happen while the picker is open; never start compression
      // or touch a temp dir for a page that is already gone.
      if (_disposed || !mounted) return;
      if (location == null) return;
      final path = location.path;
      final uri = location.uri;
      if (!(path != null && path.isNotEmpty) &&
          !(uri != null && uri.isNotEmpty)) {
        throw const FileSystemException('系统未返回可写位置');
      }

      _setBusy('正在打包并导出…');
      final temp = await Directory.systemTemp.createTemp('qfli-export-');
      try {
        final tempFile = p.join(temp.path, 'backup.qfliz');
        final info = await AppBackupService.exportToFile(tempFile);
        // The page may be disposed during the expensive export; skip writing
        // the user-selected destination, but still clean the temp dir below.
        if (_disposed || !mounted) return;
        if (path != null && path.isNotEmpty) {
          await File(tempFile).copy(path);
        } else {
          final bytes = await File(tempFile).readAsBytes();
          await PickerService.writeUri(uri!, bytes);
        }
        _showMessage('已导出 ${info.fileCount} 个数据文件');
      } finally {
        await _deleteTempQuietly(temp);
      }
    } on Object catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      _clearBusy();
    }
  }

  /// 导入全部数据。
  ///
  /// 只校验并暂存（[AppBackupService.prepareImport]），**不**触碰线上数据；
  /// 真正的替换留给下次启动时的私有根交换。
  Future<void> _importAllData() async {
    if (_busyLabel != null) return;
    _setBusy('正在读取备份…');
    try {
      if (await AppBackupService.hasPendingRestore()) {
        final pending = await AppBackupService.pendingRestoreInfo();
        _showMessage(
          '已有待应用的恢复（${pending?.createdAt.toLocal() ?? ''}），请先重启应用',
        );
        return;
      }
      final picked = await PickerService.pickDocument(
        extensions: const ['qfliz', 'zip'],
      );
      if (picked == null) return;
      final bytes = await _readPickedBytes(picked);
      final info = await AppBackupService.readInfoAsync(bytes);
      AppBackupService.assertCompatible(info);
      if (_disposed || !mounted) return;
      final confirmed = await _confirmRestore(info);
      if (confirmed != true) return;
      if (_disposed || !mounted) return;

      _setBusy('正在校验并暂存…');
      final prepared = await AppBackupService.prepareImport(bytes);
      _showMessage(
        '已暂存 ${prepared.fileCount} 个文件。全部数据将在下次启动时替换：'
        '重启后会显示恢复完成，届时请再完全关闭并重新打开应用一次。',
      );
    } on Object catch (error) {
      _showMessage('导入失败：$error');
    } finally {
      _clearBusy();
    }
  }

  /// 恢复确认对话框：可滚动、窄屏与大字体友好。
  Future<bool?> _confirmRestore(AppBackupInfo info) {
    final created = info.createdAt.toLocal();
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('导入全部数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '来源：${info.appTitle.isEmpty ? info.productKey : info.appTitle}',
            ),
            Text('创建时间：$created'),
            Text('包含 ${info.fileCount} 个数据文件'),
            const SizedBox(height: 12),
            const Text(
              '应用的全部私有数据——项目（含二进制文件）、设置、索引与本地记录'
              '——将在下次启动时被此备份完整替换。',
            ),
            const SizedBox(height: 8),
            const Text('导入不会立即生效：确认后请完全关闭并重新打开应用以完成恢复。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续导入'),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _readPickedBytes(PickedDocument picked) async {
    final path = picked.path;
    if (path != null && path.isNotEmpty) return File(path).readAsBytes();
    final uri = picked.uri;
    if (uri != null && uri.isNotEmpty) return PickerService.readUri(uri);
    throw const FileSystemException('系统未返回可读文件');
  }

  void _setBusy(String label) {
    if (_disposed || !mounted) return;
    setState(() => _busyLabel = label);
  }

  void _clearBusy() {
    if (_disposed || !mounted) return;
    setState(() => _busyLabel = null);
  }

  Future<void> _deleteTempQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // 临时目录清理失败不影响导出结果。
    }
  }

  void _showMessage(String message) {
    if (_disposed || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<String?> _backupPath() async {
    final base = await AppPaths.storageDirectory();
    return base == null ? null : p.join(base, FileBackup.dirName);
  }
}

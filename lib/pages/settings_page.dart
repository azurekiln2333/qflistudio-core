import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../config/agreement_config.dart';
import '../editor/ai_panel.dart';
import '../remote_control/remote_computer_page.dart';
import '../services/account_erasure_service.dart';
import '../services/app_backup_service.dart';
import '../services/app_paths.dart';
import '../services/file_backup.dart';
import '../services/picker_service.dart';
import '../services/studio_profile.dart';
import '../shell/large_screen_controller.dart';
import '../shell/shortcut_label.dart';
import '../store/auth_store.dart';
import '../store/settings_store.dart';
import '../store/project_store.dart';
import '../widgets/settings_section.dart';
import 'auth/agreement_page.dart';
import 'devices_remote_page.dart';
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

  AuthStore? get _auth => widget.auth;

  /// 账户与隐私分组只在能真正生效时出现。
  ///
  /// 离线产品没有账号，也不联网，没有可撤回的同意；显示一个禁用入口
  /// 比没有入口更让人困惑。
  bool get _showsAccountSection =>
      widget.auth != null && StudioProfile.current?.offlineOnly != true;

  /// 是否提供“个人 AI 接口”入口。
  ///
  /// 鸿蒙正式版只走官方转发（§3-W3、§4 第 9 条）：披露的第三方只有深度求索，
  /// 且必须经本公司服务器转发。产品档位不开就是不显示，界面不自己判断平台。
  bool get _customAiEndpointAllowed =>
      StudioProfile.current?.allowCustomAiEndpoint == true;

  /// “账户与隐私”：协议入口、撤回同意、注销账号（§3-W3）。
  ///
  /// 从主界面进入不超过 4 次点击：主界面 → 我的 → 设置 → 本分组，
  /// 所以三个入口都在这一屏直接可见，不再嵌二级页面。
  Widget _accountSection(BuildContext context) {
    final auth = _auth!;
    return SettingsSection(
      title: '账户与隐私',
      children: [
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('用户协议'),
          subtitle: Text(userAgreementAvailable ? '查看并阅读' : '暂未发布，等待托管地址'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openAgreement('用户协议', userAgreementUrl),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('隐私政策'),
          subtitle: Text(privacyPolicyAvailable ? '查看并阅读' : '暂未发布，等待托管地址'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openAgreement('隐私政策', privacyPolicyUrl),
        ),
        ListTile(
          leading: const Icon(Icons.undo_outlined),
          title: const Text('撤回隐私政策同意'),
          subtitle: const Text('停止处理个人信息，并退出登录'),
          trailing: const Icon(Icons.chevron_right),
          onTap: auth.isLoggedIn ? _withdrawConsent : null,
          enabled: auth.isLoggedIn,
        ),
        ListTile(
          leading: Icon(
            Icons.person_off_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            '注销账号',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          subtitle: const Text('永久删除账号与本站个人数据，不可恢复'),
          trailing: const Icon(Icons.chevron_right),
          onTap: auth.isLoggedIn ? _deactivateAccount : null,
          enabled: auth.isLoggedIn,
        ),
      ],
    );
  }

  /// 「设备与远程」：配对、已绑定电脑和撤销。
  ///
  /// 配对不再占用独立首页，会话已并入编辑器页的 Agents 面板。
  Widget _devicesSection(BuildContext context) => SettingsSection(
    title: '设备与远程',
    children: [
      ListTile(
        key: const ValueKey('settings-devices-remote'),
        leading: const Icon(Icons.devices_other_outlined),
        title: const Text('设备与远程'),
        subtitle: const Text('配对电脑、查看绑定状态、撤销访问权限'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openDevicesRemotePage(context, auth: widget.auth),
      ),
    ],
  );

  void _openAgreement(String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgreementPage(title: title, url: url),
      ),
    );
  }

  /// 撤回隐私政策同意。
  ///
  /// 优先调用鸿蒙隐私托管的撤回接口（`qflistudio/platform.requestPrivacyWithdraw`）；
  /// 宿主没有该接口时（旧版鸿蒙或其他平台），清本地数据、退出登录，
  /// 并提示用户到系统设置里撤回。两条路径都不再发送任何请求。
  Future<void> _withdrawConsent() async {
    final auth = _auth!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('撤回隐私政策同意'),
        content: const Text(
          '撤回后将停止处理你的个人信息，并退出登录。\n'
          '已完成注销的账号不会被恢复；如需继续使用，需要重新同意隐私政策后再登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    var hosted = false;
    try {
      final result = await const MethodChannel(
        'qflistudio/platform',
      ).invokeMethod<bool>('requestPrivacyWithdraw');
      hosted = result == true;
    } on MissingPluginException {
      // 宿主没有隐私托管：走本地分支。
    } on PlatformException {
      // 撤回接口报错也走本地分支，用户至少要能退出登录。
    }

    await auth.clearLocalData();
    if (!mounted) return;
    _showMessage(
      hosted ? '已撤回隐私政策同意，并退出登录' : '已退出登录并清除本地登录信息。请在系统设置 → 隐私中撤回对华为隐私政策的授权。',
    );
  }

  /// 注销账号：二次确认后调接口，成功后清本地登录态（§4 第 7 条）。
  Future<void> _deactivateAccount() async {
    final auth = _auth!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('永久注销账号'),
        content: const Text(
          '注销会立即且不可恢复地：\n'
          '· 删除账号与本站个人数据（帖文、评论、云项目、终端数据）\n'
          '· 吊销所有设备上的登录状态\n'
          '· 审计日志保留 365 天，其中的个人标识已去标识化\n\n'
          '如果只是想暂停使用，请选择取消，改为退出登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续注销'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 第二次确认：输入确认词，避免误触就删掉账号。
    final typed = await _askErasureConfirmation();
    if (typed != AccountErasureService.confirmWord) return;
    if (!mounted) return;

    _setBusy('正在注销账号…');
    final result = await AccountErasureService().erase(auth);
    _clearBusy();
    if (!mounted) return;
    if (result.succeeded) {
      _showMessage('账号已永久注销');
    } else {
      _showMessage(result.message ?? '注销失败，请稍后重试');
    }
  }

  Future<String?> _askErasureConfirmation() {
    // 控制器归对话框自己管：用 whenComplete 释放会在退场动画期间
    // 就被销毁，输入框重建时会拿到已释放的控制器。
    return showDialog<String>(
      context: context,
      builder: (context) => const _ErasureConfirmDialog(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final largeScreen = LargeScreenScope.maybeOf(context) != null;
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
                    if (largeScreen) _zoomSetting(),
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
                    if (largeScreen)
                      SwitchListTile(
                        key: const ValueKey('settings-large-screen-symbols'),
                        secondary: const Icon(Icons.keyboard_outlined),
                        title: const Text('大屏显示符号栏'),
                        subtitle: const Text('在平板和桌面编辑器中显示符号栏'),
                        value: settings.largeScreenSymbolBar,
                        onChanged: settings.setLargeScreenSymbolBar,
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
                if (largeScreen) _shortcutSection(),
                if (widget.showAi && _customAiEndpointAllowed)
                  SettingsSection(
                    title: 'AI 助手',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('个人 AI 接口'),
                        subtitle: Text(
                          settings.aiModel.isEmpty
                              ? '连接你自己的 AI 服务与密钥'
                              : '${settings.aiModel} · ${settings.aiProtocol.label}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => editAiSettings(context, settings),
                      ),
                      // 只影响直连的 Responses 与 Messages 请求字段
                      // （design §4.4：默认关闭，不支持思考的模型会返回 400）。
                      SwitchListTile(
                        key: const ValueKey('settings-ai-thinking'),
                        secondary: const Icon(Icons.psychology_outlined),
                        title: const Text('请求思考过程'),
                        subtitle: const Text(
                          '只对 Responses 与 Messages 协议生效。模型不支持思考时请关闭。',
                        ),
                        value: settings.aiThinking,
                        onChanged: settings.setAiThinking,
                      ),
                    ],
                  ),
                if (_showsAccountSection) _accountSection(context),
                if (RemoteComputerPage.isSupported) _devicesSection(context),
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
                      subtitle: const Text('打包设置、项目（含二进制资源）、索引与缓存为 .qfliz 备份'),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: _busyLabel == null,
                      onTap: _busyLabel == null ? _exportAllData : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: const Text('导入全部数据'),
                      subtitle: const Text('校验后暂存，下次启动应用时替换当前数据（不可撤销）'),
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

  Widget _zoomSetting() => ListTile(
    key: const ValueKey('settings-ui-zoom'),
    leading: const Icon(Icons.zoom_in_outlined),
    title: const Text('界面缩放'),
    subtitle: Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${(settings.uiScale * 100).round()}%'),
        IconButton(
          key: const ValueKey('settings-ui-zoom-out'),
          tooltip: '缩小界面 (${shortcutLabel('Ctrl+-')})',
          onPressed: settings.uiScale > SettingsStore.minUiScale
              ? () => settings.setUiScale(settings.uiScale - 0.1)
              : null,
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          key: const ValueKey('settings-ui-zoom-in'),
          tooltip: '放大界面 (${shortcutLabel('Ctrl+= / Ctrl++')})',
          onPressed: settings.uiScale < SettingsStore.maxUiScale
              ? () => settings.setUiScale(settings.uiScale + 0.1)
              : null,
          icon: const Icon(Icons.add),
        ),
        Tooltip(
          message: '复原界面缩放 (${shortcutLabel('Ctrl+0')})',
          child: TextButton(
            key: const ValueKey('settings-ui-zoom-reset'),
            onPressed: settings.uiScale == 1
                ? null
                : () => settings.setUiScale(1),
            child: const Text('复原'),
          ),
        ),
      ],
    ),
  );

  Widget _shortcutSection() => SettingsSection(
    title: '快捷键',
    children: [
      const ListTile(subtitle: Text('终端获得焦点时，关闭标签、底部面板和 Agent 栏的快捷键交给终端。')),
      for (final entry in const [
        ('放大界面', 'Ctrl+= / Ctrl++ / Ctrl+NumpadAdd', '全局'),
        ('缩小界面', 'Ctrl+- / Ctrl+NumpadSubtract', '全局'),
        ('复原界面缩放', 'Ctrl+0 / Ctrl+Numpad0', '全局'),
        ('显示或收起侧栏', 'Ctrl+B', '工作台'),
        ('资源管理器', 'Ctrl+Shift+E', '工作台'),
        ('Agents 列表', 'Ctrl+Shift+A', '工作台'),
        ('设置', 'Ctrl+,', '工作台'),
        ('显示或收起终端', 'Ctrl+`', '编辑器'),
        ('显示或收起底部面板', 'Ctrl+J', '编辑器'),
        ('显示或收起 Agent 栏', 'Ctrl+L', '编辑器'),
        ('关闭当前文件标签', 'Ctrl+W', '编辑器'),
        ('下一个 / 上一个文件标签', 'Ctrl+Tab / Ctrl+Shift+Tab', '编辑器'),
        ('新建文件', 'Ctrl+N', '编辑器'),
        ('运行', 'F5', '编辑器'),
        ('保存', 'Ctrl+S', '编辑器'),
        ('查找', 'Ctrl+F', '编辑器'),
        ('跳行', 'Ctrl+G', '编辑器'),
        ('格式化', 'Ctrl+I', '编辑器'),
      ])
        ListTile(
          title: Text(entry.$1),
          subtitle: Text('${shortcutLabel(entry.$2)} · ${entry.$3}'),
        ),
    ],
  );

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
        _showMessage('已有待应用的恢复（${pending?.createdAt.toLocal() ?? ''}），请先重启应用');
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

/// 注销账号的第二道确认：必须原样输入确认词。
///
/// 输入控制器属于对话框自身的 State，随对话框一起销毁。
class _ErasureConfirmDialog extends StatefulWidget {
  const _ErasureConfirmDialog();

  @override
  State<_ErasureConfirmDialog> createState() => _ErasureConfirmDialogState();
}

class _ErasureConfirmDialogState extends State<_ErasureConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: const Text('确认注销'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('请输入 ${AccountErasureService.confirmWord} 以确认永久注销：'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '确认词',
              hintText: AccountErasureService.confirmWord,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: _submit,
          child: const Text('注销账号'),
        ),
      ],
    );
  }
}

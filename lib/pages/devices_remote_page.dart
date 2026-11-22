// 设置页的「设备与远程」：配对、查看已绑定电脑、撤销配对。
//
// 旧版把配对和会话管理放在独立的“远程电脑”首页（RemoteComputerPage）。
// 会话已经并入编辑器页的 Agents 面板，配对与撤销搬到这里；远程电脑模块的
// 内部实现（RemoteStore / RemoteController / 协议）保持不变，其它主机仍可
// 直接使用。
//
// 所有权与 RemoteComputerPage 一致：外部注入的 controller/store 由调用方
// 释放，本页只释放自己创建的那一个。

import 'dart:async';

import 'package:flutter/material.dart';

import '../remote_control/pages/pair_screen.dart';
import '../remote_control/remote_computer_page.dart';
import '../remote_control/state/remote_controller.dart';
import '../remote_control/state/remote_store.dart';
import '../store/auth_store.dart';
import '../widgets/settings_section.dart';

/// 打开「设备与远程」。
Future<void> openDevicesRemotePage(
  BuildContext context, {
  AuthStore? auth,
  RemoteController? controller,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DevicesRemotePage(auth: auth, controller: controller),
    ),
  );
}

class DevicesRemotePage extends StatefulWidget {
  const DevicesRemotePage({super.key, this.auth, this.store, this.controller});

  /// 当前登录账号。为空时账号分组只说明本机状态。
  final AuthStore? auth;

  /// 预打开的存储；测试注入内存实现。
  final RemoteStore? store;

  /// 预构造的控制器；给出时本页不释放它。
  final RemoteController? controller;

  @override
  State<DevicesRemotePage> createState() => _DevicesRemotePageState();
}

class _DevicesRemotePageState extends State<DevicesRemotePage> {
  RemoteController? _controller;
  RemoteStore? _store;
  bool _ownsController = false;
  Object? _bootError;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    if (!RemoteComputerPage.isSupported) {
      if (mounted) setState(() => _booting = false);
      return;
    }
    try {
      final provided = widget.controller;
      if (provided != null) {
        if (!mounted) return;
        _store = widget.store;
        _controller = provided;
        _ownsController = false;
      } else {
        final store = widget.store ?? await RemoteStore.open();
        // 页面在 await 期间被弹出：不再创建控制器，否则那个 WebSocket
        // 与订阅没有任何人释放。
        if (!mounted) return;
        final controller = RemoteController(store: store)..connect();
        if (!mounted) {
          controller.dispose();
          return;
        }
        _store = store;
        _controller = controller;
        _ownsController = true;
      }
    } on Object catch (error) {
      _bootError = error;
    }
    if (mounted) setState(() => _booting = false);
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备与远程')),
      body: ListenableBuilder(
        listenable: Listenable.merge([?_controller, ?widget.auth]),
        builder: (context, _) {
          final controller = _controller;
          final pairing = controller?.pairing;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (!RemoteComputerPage.isSupported)
                const _UnsupportedNotice()
              else if (_booting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_bootError != null)
                _BootFailure(error: _bootError!)
              else ...[
                SettingsSection(
                  title: '已绑定电脑',
                  children: [
                    if (pairing == null)
                      const ListTile(
                        leading: Icon(Icons.link_off),
                        title: Text('还没有绑定电脑'),
                        subtitle: Text('在电脑上启动伴侣程序，用配对码把手机连上它。'),
                      )
                    else
                      ListTile(
                        key: const ValueKey('devices-paired-computer'),
                        leading: _OnlineDot(
                          online: controller?.isOnline ?? false,
                        ),
                        title: Text(controller?.agentName ?? '我的电脑'),
                        subtitle: Text(
                          '${pairing.relayUrl} · ${pairing.agentId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          key: const ValueKey('devices-revoke'),
                          onPressed: () => _revoke(controller!),
                          child: const Text('撤销'),
                        ),
                      ),
                    ListTile(
                      key: const ValueKey('devices-add-computer'),
                      leading: const Icon(Icons.add_link),
                      title: const Text('添加电脑'),
                      subtitle: Text(
                        pairing == null
                            ? '用配对码或配对链接连接一台电脑'
                            : '换绑另一台电脑（会先解除当前配对）',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _addComputer(controller!),
                    ),
                  ],
                ),
                SettingsSection(
                  title: '账号',
                  children: [
                    ListTile(
                      key: const ValueKey('devices-account'),
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(_accountTitle(widget.auth)),
                      subtitle: Text(_accountSubtitle(widget.auth)),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    '会话列表在编辑器页的 Agents 面板里：本机、Herdr 和已绑定电脑都在同一处，'
                    '关闭会话视图不会结束电脑上的会话。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _accountTitle(AuthStore? auth) {
    if (auth == null) return '未接入账号';
    return auth.isLoggedIn ? '已登录' : '未登录';
  }

  static String _accountSubtitle(AuthStore? auth) {
    if (auth == null) {
      return '当前产品不提供账号，配对信息只保存在这台设备上。';
    }
    if (!auth.isLoggedIn) {
      return '登录后可以把配对状态同步到账号；未登录时配对只保存在本机。';
    }
    return '配对信息与账号分开保存，撤销配对不会退出登录。';
  }

  /// 撤销配对：先确认，再清掉本机保存的密钥。
  Future<void> _revoke(RemoteController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('devices-revoke-dialog'),
        scrollable: true,
        title: const Text('撤销这台电脑的配对'),
        content: const Text(
          '撤销后这台设备不再能连接该电脑，密钥会从本机删除。'
          '电脑上的会话不受影响，重新配对即可再次连接。',
        ),
        actions: [
          TextButton(
            key: const ValueKey('devices-revoke-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('devices-revoke-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.unpair();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('已撤销配对')));
  }

  /// 添加电脑：复用远程模块原有的配对页，配对成功后回到本页。
  Future<void> _addComputer(RemoteController controller) async {
    final pair = controller.pairing;
    if (pair != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('换绑另一台电脑'),
          content: const Text('当前已绑定一台电脑。继续会先解除现有配对，再进入配对流程。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (replace != true) return;
      await controller.unpair();
      if (!mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PairRoute(
          controller: controller,
          initialRelay: _store?.lastRelayUrl,
        ),
      ),
    );
  }
}

/// 单独的配对路由：配对成功后自己退出，回到设备列表。
class _PairRoute extends StatefulWidget {
  const _PairRoute({required this.controller, this.initialRelay});

  final RemoteController controller;
  final String? initialRelay;

  @override
  State<_PairRoute> createState() => _PairRouteState();
}

class _PairRouteState extends State<_PairRoute> {
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (_paired) return;
    if (widget.controller.pairing == null) return;
    _paired = true;
    // 配对完成立刻退回设备列表：配对页本身没有“完成”按钮。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 只在配对页仍是最上层时退一层：重复回调或用户已手动返回时，
      // pop 会把设置页一起弹掉。
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      if (!Navigator.of(context).canPop()) return;
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加电脑')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => PairScreen(
          controller: widget.controller,
          initialRelay: widget.initialRelay,
          onExit: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 32,
      child: Center(
        child: Container(
          key: ValueKey(online ? 'devices-dot-online' : 'devices-dot-offline'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? const Color(0xFF2E7D32) : scheme.outline,
          ),
        ),
      ),
    );
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.devices_other_rounded, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text('当前平台不支持远程电脑', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '远程电脑需要原生应用提供的 WebSocket 连接与本地私有存储，'
            '浏览器版两者都没有实现。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BootFailure extends StatelessWidget {
  const _BootFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.sd_card_alert_outlined, color: scheme.error, size: 36),
          const SizedBox(height: 8),
          Text('无法读取本机的配对信息', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText(
            '$error',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../community/community_widgets.dart';
import '../config/compliance_config.dart';
import '../services/api_client.dart';
import '../services/recovery_service.dart';
import '../store/auth_store.dart';
import '../store/settings_store.dart';
import '../store/project_store.dart';
import '../widgets/settings_section.dart';
import 'audit_page.dart';
import 'auth/login_page.dart';
import 'auth/agreement_page.dart';
import 'recovery_page.dart';
import 'settings_page.dart';
import 'tasks_page.dart';
import 'points_page.dart';
import 'task_config_page.dart';
import 'checkin_calendar_page.dart';
import 'activity_stats_page.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.auth,
    required this.settings,
    required this.store,
  });

  final AuthStore auth;
  final SettingsStore settings;
  final ProjectStore store;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const _cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );

  int _avatarRevision = 0;

  Future<void> _refresh() async {
    await widget.auth.refreshMe();
    if (mounted) setState(() => _avatarRevision++);
  }

  Future<void> _login() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginPage(auth: widget.auth)),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: widget.settings,
          auth: widget.auth,
          store: widget.store,
        ),
      ),
    );
  }

  Future<void> _openAccountPage(Widget Function() page) async {
    if (!widget.auth.isLoggedIn) await _login();
    if (!mounted || !widget.auth.isLoggedIn) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: widget.auth,
          builder: (context, _) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _profileHeader(context),
                    const SizedBox(height: 16),
                    if (widget.auth.isLoggedIn) ...[
                      _statistics(context),
                      const SizedBox(height: 24),
                    ],
                    SettingsSection(
                      title: '签到与积分',
                      cardShape: _cardShape,
                      children: [
                        _entry(
                          icon: Icons.task_alt_outlined,
                          title: '每日任务',
                          onTap: () => _openAccountPage(
                            () => TasksPage(auth: widget.auth),
                          ),
                        ),
                        _entry(
                          icon: Icons.stars_outlined,
                          title: '积分兑换',
                          onTap: () => _openAccountPage(
                            () => PointsPage(auth: widget.auth),
                          ),
                        ),
                        _entry(
                          icon: Icons.bar_chart_outlined,
                          title: '统计',
                          onTap: () => _openAccountPage(
                            () => ActivityStatsPage(auth: widget.auth),
                          ),
                        ),
                      ],
                    ),
                    SettingsSection(
                      title: '数据管理',
                      cardShape: _cardShape,
                      children: [
                        for (final kind in RecoveryKind.values)
                          _entry(
                            icon: recoveryIcon(kind),
                            title: recoveryTitle(kind),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => RecoveryPage(
                                  kind: kind,
                                  store: widget.store,
                                  settings: widget.settings,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SettingsSection(
                      title: '偏好与支持',
                      cardShape: _cardShape,
                      children: [
                        _entry(
                          icon: Icons.tune_rounded,
                          title: '设置',
                          onTap: _openSettings,
                        ),
                        _entry(
                          icon: Icons.info_outline,
                          title: '关于 QFLIStudio+',
                          onTap: () => showQfliAbout(context),
                        ),
                      ],
                    ),
                    if (widget.auth.user?.isAdmin == true)
                      SettingsSection(
                        title: '管理',
                        cardShape: _cardShape,
                        children: [
                          _entry(
                            icon: Icons.tune_outlined,
                            title: '任务配置',
                            onTap: () => _openAccountPage(
                              () => TaskConfigPage(auth: widget.auth),
                            ),
                          ),
                          _entry(
                            icon: Icons.policy_outlined,
                            title: '操作审计',
                            onTap: () => _openAccountPage(
                              () => AuditPage(auth: widget.auth),
                            ),
                          ),
                        ],
                      ),
                    if (widget.auth.isLoggedIn)
                      Center(
                        child: TextButton.icon(
                          onPressed: _confirmSignOut,
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('退出登录'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _icpFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = widget.auth.user;
    final loggedIn = widget.auth.isLoggedIn;
    return InkWell(
      onTap: loggedIn ? null : _login,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
        child: Row(
          children: [
            if (loggedIn)
              Avatar(
                name: user!.nickname,
                cacheKey: user.id,
                refreshToken: _avatarRevision,
                color: user.avatarColor,
                imageUrl: user.avatarUrl,
                size: 60,
              )
            else
              CircleAvatar(
                radius: 30,
                backgroundColor: scheme.surfaceContainerHighest,
                foregroundColor: scheme.onSurfaceVariant,
                child: const Icon(Icons.person_outline, size: 32),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loggedIn ? user!.nickname : '未登录',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (loggedIn) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'LV.${user!.growth.level}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${user.growth.levelExperience}/${user.growth.requiredExperience} 经验',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: user.growth.progress,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: scheme.primaryContainer,
                      color: scheme.primary,
                    ),
                  ],
                ],
              ),
            ),
            if (loggedIn)
              IconButton(
                tooltip: '编辑资料',
                onPressed: _editProfile,
                color: scheme.onSurfaceVariant,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
      ),
    );
  }

  Widget _icpFooter() => Center(
    child: TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        textStyle: const TextStyle(fontSize: 11),
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AgreementPage(
            title: '备案查询',
            url: ComplianceConfig.icpQueryUrl,
          ),
        ),
      ),
      child: const Text(ComplianceConfig.icpRecord),
    ),
  );

  Widget _statistics(BuildContext context) {
    final user = widget.auth.user!;
    return Card.filled(
      margin: EdgeInsets.zero,
      shape: _cardShape,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Row(
          children: [
            _stat(context, '${user.points}', '积分', onTap: () =>
                _openAccountPage(() => PointsPage(auth: widget.auth))),
            _stat(context, '${user.checkinStreak}', '连续签到', onTap: () =>
                _openAccountPage(() => CheckinCalendarPage(auth: widget.auth))),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(onTap: onTap, child: Column(
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      )),
    );
  }

  Widget _entry({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('本地项目与草稿将继续保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.auth.signOut();
  }

  Future<void> _editProfile() async {
    final user = widget.auth.user!;
    final nickname = TextEditingController(text: user.nickname);
    final bio = TextEditingController(text: user.bio);
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑资料'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nickname,
                maxLength: 24,
                decoration: const InputDecoration(labelText: '昵称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bio,
                maxLength: 200,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '个性签名',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final name = nickname.text.trim();
    final signature = bio.text.trim();
    // Dialog 的反向动画完成后再释放输入控制器。
    await Future<void>.delayed(const Duration(milliseconds: 250));
    nickname.dispose();
    bio.dispose();
    if (updated != true || !mounted) return;
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('昵称不能为空')));
      return;
    }
    try {
      await widget.auth.updateProfile(nickname: name, bio: signature);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

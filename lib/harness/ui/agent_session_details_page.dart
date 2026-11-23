// 会话详情：这台会话跑在哪台设备上、目录在哪。
//
// 只读展示，不做操作。字段缺值时显示「未知」，不猜。

import 'package:flutter/material.dart';

import '../../i18n/studio_localizations.dart';
import '../harness_host.dart';
import '../hub/agents_index.dart';
import 'hub_status.dart';

/// 一行会话的详情页。
class AgentSessionDetailsPage extends StatelessWidget {
  const AgentSessionDetailsPage({super.key, required this.row});

  final AgentsIndexRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    final theme = Theme.of(context);
    final device = row.device;
    String text(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? l10n.agentsUnknown : trimmed;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.agentsDetails)),
      body: ListView(
        key: const ValueKey('agent-session-details'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(row.session.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              _Dot(status: row.session.status, rowKey: row.rowKey),
              const SizedBox(width: 8),
              Text(
                harnessStatusLabel(row.session.status),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const Divider(height: 32),
          _Field(label: l10n.agentsDeviceName, value: text(device?.hostName)),
          _Field(
            label: l10n.agentsDeviceOs,
            value: text(_osLabel(device?.os, l10n.agentsUnknown)),
          ),
          _Field(
            label: l10n.agentsDeviceOsVersion,
            value: text(device?.osVersion),
          ),
          _Field(
            label: l10n.agentsHostKind,
            value: _hostKindLabel(row.hostKind),
          ),
          _Field(label: l10n.agentsSessionPath, value: text(row.session.cwd)),
        ],
      ),
    );
  }
}

/// 主机类型的中文说法。
String _hostKindLabel(HarnessHostKind kind) => switch (kind) {
  HarnessHostKind.local => '本机',
  HarnessHostKind.remote => '已绑定的电脑',
  HarnessHostKind.studio => '内置 Agent',
};

/// 系统名的中文说法。认不出时用调用方给的未知说法。
String _osLabel(HarnessDeviceOs? os, String unknown) => switch (os) {
  HarnessDeviceOs.android => 'Android',
  HarnessDeviceOs.ios => 'iOS',
  HarnessDeviceOs.ohos => 'HarmonyOS',
  HarnessDeviceOs.macos => 'macOS',
  HarnessDeviceOs.windows => 'Windows',
  HarnessDeviceOs.linux => 'Linux',
  HarnessDeviceOs.unknown || null => unknown,
};

/// 一行字段：左边名字，右边值。
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// 与列表行同一套配色的圆点。
class _Dot extends StatelessWidget {
  const _Dot({required this.status, required this.rowKey});

  final HarnessSessionStatus status;
  final String rowKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('agent-session-details-status-$rowKey'),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: harnessStatusDotColor(status),
        border: Border.all(
          color: harnessStatusDotBorderColor(scheme, status),
          width: 1.5,
        ),
      ),
    );
  }
}

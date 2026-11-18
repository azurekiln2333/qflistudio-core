import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class ToolResultView extends StatelessWidget {
  const ToolResultView({super.key, required this.result});

  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent =
        result.ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                    result.ok
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(result.title, style: theme.textTheme.titleLarge),
                      if (result.summary != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(result.summary!,
                            style: theme.textTheme.bodyMedium),
                      ],
                      if (result.error != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(result.error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                    ],
                  ),
                ),
                if (result.elapsed != null)
                  Text(formatDuration(result.elapsed),
                      style: theme.textTheme.labelMedium),
              ],
            ),
            if (result.rows.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: result.rows
                      .map((ResultRow row) => _ResultRow(row: row))
                      .toList(),
                ),
              ),
            ],
            for (final ToolPanel panel in result.panels) ...<Widget>[
              const SizedBox(height: 16),
              _TextPanel(panel: panel),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.row});

  final ResultRow row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
              width: 116,
              child: Text(row.label, style: theme.textTheme.labelLarge)),
          Expanded(
            child: SelectableText(
              row.value,
              style: row.mono
                  ? const TextStyle(fontFamily: 'monospace')
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({required this.panel});

  final ToolPanel panel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
                child: Text(panel.title, style: theme.textTheme.titleSmall)),
            IconButton(
              tooltip: '复制',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: panel.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已复制')));
                }
              },
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 420),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            child: SelectableText(panel.text,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
        ),
      ],
    );
  }
}

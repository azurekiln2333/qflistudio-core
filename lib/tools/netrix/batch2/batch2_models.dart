/// Netrix tool model types used by the ported batch 2 tools.
///
/// This file is a 1:1 port of `netrix/lib/core/models.dart` (only the names are
/// prefixed with `Netrix` so they cannot collide with the host application's
/// existing `lib/pages/tools_grid.dart` types). Field order, defaults, error
/// keys and helper bounds all match netrix.
library;

import 'package:flutter/material.dart';

/// A single named value shown in a result key/value table.
class NetrixResultRow {
  const NetrixResultRow(this.label, this.value, {this.mono = true});

  final String label;
  final String value;
  final bool mono;
}

/// A secondary output panel, such as a response body or formatted JSON.
class NetrixToolPanel {
  const NetrixToolPanel({required this.title, required this.text});

  final String title;
  final String text;
}

/// An error with a message that can be shown directly to the user.
class NetrixToolException implements Exception {
  NetrixToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The outcome of running one tool.
class NetrixToolResult {
  const NetrixToolResult({
    required this.title,
    this.summary,
    this.rows = const <NetrixResultRow>[],
    this.panels = const <NetrixToolPanel>[],
    this.ok = true,
    this.elapsed,
    this.error,
  });

  final String title;
  final String? summary;
  final List<NetrixResultRow> rows;
  final List<NetrixToolPanel> panels;
  final bool ok;
  final Duration? elapsed;
  final String? error;

  factory NetrixToolResult.failure(
    String title,
    Object error, {
    Duration? elapsed,
    String? localizedMessage,
  }) {
    return NetrixToolResult(
      title: title,
      ok: false,
      elapsed: elapsed,
      error: localizedMessage ??
          (error is NetrixToolException ? error.message : error.toString()),
    );
  }
}

/// The kind of editor used for a tool field.
enum NetrixToolFieldType { text, multiline, select }

/// One validated input field rendered by the generic tool page.
class NetrixToolField {
  const NetrixToolField({
    required this.id,
    required this.label,
    this.hint,
    this.initialValue = '',
    this.required = true,
    this.type = NetrixToolFieldType.text,
    this.keyboardType,
    this.obscureText = false,
    this.options = const <String>[],
  });

  final String id;
  final String label;
  final String? hint;
  final String initialValue;
  final bool required;
  final NetrixToolFieldType type;
  final TextInputType? keyboardType;
  final bool obscureText;
  final List<String> options;
}

typedef NetrixToolRunner = Future<NetrixToolResult> Function(
    Map<String, String> values);

/// Product category shown on the tool list, mirroring netrix categories.
enum NetrixToolCategory {
  diagnostics('diagnostics', Icons.monitor_heart_outlined),
  address('address', Icons.lan_outlined),
  dns('dns', Icons.dns_outlined),
  web('web', Icons.api_outlined),
  security('security', Icons.shield_outlined),
  text('text', Icons.text_fields_outlined),
  local('local', Icons.router_outlined);

  const NetrixToolCategory(this.key, this.icon);

  final String key;
  final IconData icon;
}

/// Static description and execution contract for one toolbox tool.
class NetrixToolDefinition {
  const NetrixToolDefinition({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.description,
    required this.category,
    required this.icon,
    required this.fields,
    required this.run,
  });

  final String id;
  final String title;
  final String titleEn;
  final String description;
  final NetrixToolCategory category;
  final IconData icon;
  final List<NetrixToolField> fields;
  final NetrixToolRunner run;
}

String formatDuration(Duration? duration) {
  if (duration == null) return '-';
  final int milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) return '$milliseconds ms';
  return '${(milliseconds / 1000).toStringAsFixed(2)} s';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String requireValue(String raw, {String field = '输入'}) {
  final String value = raw.trim();
  if (value.isEmpty) throw NetrixToolException('error_required');
  return value;
}

String requireHost(String raw, {String field = '主机'}) {
  final String value = requireValue(raw, field: field);
  if (value.contains(RegExp(r'\s'))) {
    throw NetrixToolException('error_whitespace');
  }
  return value;
}

String hostFromInput(String raw) {
  final String value = requireHost(raw);
  final Uri? uri = value.contains('://') ? Uri.tryParse(value) : null;
  if (uri != null) {
    if (uri.host.isEmpty) throw NetrixToolException('error_invalid_url');
    return uri.host;
  }
  final String withoutPath = value.split('/').first;
  if (withoutPath.startsWith('[') && withoutPath.contains(']')) {
    return withoutPath.substring(1, withoutPath.indexOf(']'));
  }
  final int colon = withoutPath.lastIndexOf(':');
  if (colon > 0 && int.tryParse(withoutPath.substring(colon + 1)) != null) {
    return withoutPath.substring(0, colon);
  }
  return withoutPath;
}

int requirePort(String raw, {int fallback = 80}) {
  final String value = raw.trim();
  if (value.isEmpty) return fallback;
  final int? port = int.tryParse(value);
  if (port == null || port < 1 || port > 65535) {
    throw NetrixToolException('error_port_range');
  }
  return port;
}

List<int> parsePortList(String raw, {int limit = 256}) {
  final Set<int> ports = <int>{};
  for (final String chunk in raw.split(RegExp(r'[,\s]+'))) {
    if (chunk.isEmpty) continue;
    if (chunk.contains('-')) {
      final List<String> parts = chunk.split('-');
      if (parts.length != 2) throw NetrixToolException('error_port_segment');
      final int? start = int.tryParse(parts[0]);
      final int? end = int.tryParse(parts[1]);
      if (start == null ||
          end == null ||
          start < 1 ||
          end > 65535 ||
          start > end) {
        throw NetrixToolException('error_port_segment_range');
      }
      for (int port = start; port <= end; port++) {
        ports.add(port);
        if (ports.length > limit) throw NetrixToolException('error_port_limit');
      }
    } else {
      final int? port = int.tryParse(chunk);
      if (port == null || port < 1 || port > 65535) {
        throw NetrixToolException('error_port_invalid');
      }
      ports.add(port);
      if (ports.length > limit) throw NetrixToolException('error_port_limit');
    }
  }
  if (ports.isEmpty) throw NetrixToolException('error_no_ports');
  return ports.toList()..sort();
}

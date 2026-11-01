import 'dart:convert';

import 'package:qfli_studio_core/tools/offline_tools.dart';

String contentDigest(List<int> bytes) => OfflineDigest.sha256Bytes(
  bytes,
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

/// Stable JSON value identity, independent of object key insertion order.
String canonicalContentJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final map = Map<String, Object?>.from(value);
    final keys = map.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(map[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

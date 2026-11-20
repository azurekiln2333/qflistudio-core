// Native (dart:io) relay transport. Selected by `relay_connector.dart` on every
// platform that has `dart:io`: Android, iOS, desktop and OpenHarmony.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'relay_socket.dart';

/// dart:io WebSocket. Works on Android, iOS, desktop and OpenHarmony without a
/// plugin; the relay's 30 s pings keep NAT mappings alive and the
/// [pingInterval] here detects dead links from our side.
Future<RelaySocket> connectRelaySocket(Uri url) async {
  final ws = await WebSocket.connect(
    url.toString(),
  ).timeout(const Duration(seconds: 15));
  ws.pingInterval = const Duration(seconds: 25);
  return _IoRelaySocket(ws);
}

class _IoRelaySocket implements RelaySocket {
  _IoRelaySocket(this._ws)
    : frames = _ws
          .where((data) => data is String)
          .map<Map<String, dynamic>?>((data) {
            try {
              final decoded = jsonDecode(data as String);
              return decoded is Map<String, dynamic> ? decoded : null;
            } on FormatException {
              return null;
            }
          })
          .where((frame) => frame != null)
          .cast<Map<String, dynamic>>()
          .asBroadcastStream();

  final WebSocket _ws;

  @override
  final Stream<Map<String, dynamic>> frames;

  @override
  void send(Map<String, dynamic> frame) {
    if (_ws.readyState == WebSocket.open) _ws.add(jsonEncode(frame));
  }

  @override
  Future<void> close() => _ws.close(1000);

  @override
  int? get closeCode => _ws.closeCode;

  @override
  String? get closeReason => _ws.closeReason;
}

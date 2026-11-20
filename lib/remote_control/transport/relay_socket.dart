// Socket surface and relay-address normalisation for the remote-control
// module.
//
// Deliberately free of `dart:io`: the wire layer must compile on every platform
// so the module can be imported by the shared core without breaking web builds.
// The native WebSocket client lives in `relay_socket_io.dart`; platforms without
// `dart:io` resolve `relay_socket_stub.dart` through `relay_connector.dart` and
// report that remote control is unsupported. Remote control is a native-only
// feature and is never advertised on the web.

/// Minimal socket surface the app needs, so tests can swap in a fake.
abstract class RelaySocket {
  /// Decoded JSON frames. Completes when the socket closes.
  Stream<Map<String, dynamic>> get frames;

  void send(Map<String, dynamic> frame);

  Future<void> close();

  int? get closeCode;
  String? get closeReason;
}

typedef RelayConnector = Future<RelaySocket> Function(Uri url);

/// Accepts what people actually type ("relay.example.com", "https://x/",
/// "192.168.1.5:8787") and produces a WebSocket URL ending in /ws.
///
/// Bare hosts default to wss:// except for LAN / loopback addresses, where a
/// TLS terminator is unlikely.
Uri? normalizeRelayUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) {
    final host = text.split(RegExp(r'[:/]')).first;
    text = '${_isLocalHost(host) ? 'ws' : 'wss'}://$text';
  }
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return null;
  }
  final scheme = switch (uri.scheme) {
    'http' || 'ws' => 'ws',
    'https' || 'wss' => 'wss',
    _ => null,
  };
  if (scheme == null || uri.host.isEmpty) return null;
  final path = uri.path.isEmpty || uri.path == '/' ? '/ws' : uri.path;
  return Uri(
    scheme: scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
}

bool _isLocalHost(String host) {
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!;
  final b = parts[1]!;
  return a == 127 ||
      a == 10 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}

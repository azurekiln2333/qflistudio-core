import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';

AgentInfo _agent({
  List<String> capabilities = const <String>[],
  Object? lanUrls,
}) => AgentInfo.fromJson(<String, dynamic>{
  'host': 'DESKTOP-7',
  'platform': 'win32',
  'defaultCwd': r'C:\work',
  'roots': <String>[r'C:\work'],
  'allowBypass': false,
  'capabilities': capabilities,
  'lanUrls': ?lanUrls,
});

void main() {
  group('agent capabilities', () {
    test('an old agent advertises neither project_git nor lan_tls', () {
      final info = _agent();
      expect(info.capabilities, isEmpty);
      expect(info.lanUrls, isEmpty);
    });

    test('project_git is reported as a capability', () {
      final info = _agent(capabilities: ['project_git']);
      expect(info.capabilities, contains('project_git'));
    });
  });

  group('lanUrls gate', () {
    test('encrypted endpoints pass when lan_tls is advertised', () {
      final info = _agent(
        capabilities: ['lan_tls'],
        lanUrls: ['wss://192.168.1.20:8787/ws', 'wss://10.0.0.2:8787/ws'],
      );
      expect(info.lanUrls, hasLength(2));
      expect(info.lanUrls.first, 'wss://192.168.1.20:8787/ws');
    });

    test('plaintext endpoints never reach the app', () {
      final info = _agent(
        capabilities: ['lan_tls'],
        lanUrls: ['ws://192.168.1.20:8787/ws'],
      );
      expect(info.lanUrls, isEmpty);
    });

    test('endpoints without the lan_tls capability are dropped', () {
      final info = _agent(
        capabilities: ['project_git'],
        lanUrls: ['wss://192.168.1.20:8787/ws'],
      );
      expect(info.lanUrls, isEmpty);
    });

    test('a malformed list is dropped', () {
      final info = _agent(capabilities: ['lan_tls'], lanUrls: 'wss://a/ws');
      expect(info.lanUrls, isEmpty);
    });

    test('non-string entries are skipped', () {
      final info = _agent(
        capabilities: ['lan_tls'],
        lanUrls: <Object?>[42, 'wss://192.168.1.20:8787/ws'],
      );
      expect(info.lanUrls, ['wss://192.168.1.20:8787/ws']);
    });
  });
}

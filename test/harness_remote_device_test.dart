import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/remote/remote_harness.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart'
    as protocol;
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart'
    show ConnectionPhase;
import 'package:qfli_studio_core/remote_control/state/session_view.dart';

/// A port that also answers device information, like the real adapter does.
class FakeDevicePort extends ChangeNotifier
    implements RemoteSessionPort, RemoteDevicePort {
  FakeDevicePort({protocol.AgentInfo? info}) : _info = info;

  protocol.AgentInfo? _info;

  set agentInfo(protocol.AgentInfo? value) {
    _info = value;
    notifyListeners();
  }

  @override
  protocol.AgentInfo? get agentInfo => _info;

  @override
  Listenable get changes => this;

  @override
  bool get isOnline => true;

  @override
  ConnectionPhase get phase => ConnectionPhase.online;

  @override
  String get hostLabel => '办公室电脑';

  @override
  String get hostId => 'agent-42';

  @override
  List<protocol.SessionInfo> get sessions => const [];

  @override
  SessionView view(protocol.SessionInfo info) => SessionView(info);

  @override
  Future<void> refreshSessions() async {}

  @override
  Future<void> subscribe(String id, {required Object owner}) async {}

  @override
  void unsubscribe(String id, {required Object owner}) {}

  @override
  Future<void> send(String id, String text) async {}

  @override
  Future<void> respondPermission(
    String id,
    String requestId,
    String decision, {
    String? message,
    Map<String, String>? answers,
  }) async {}

  @override
  Future<void> terminalInput(String id, String data) async {}

  @override
  Future<void> terminalResize(String id, int cols, int rows) async {}

  @override
  Future<void> closeSession(String id) async {}

  @override
  Future<protocol.SessionInfo> createSession({
    required String cwd,
    String? prompt,
  }) async => throw UnimplementedError();

  @override
  Future<protocol.SessionInfo> createTerminal({required String cwd}) async =>
      throw UnimplementedError();
}

/// A port without device support: the host must still work and report nothing.
class FakePlainPort extends ChangeNotifier implements RemoteSessionPort {
  @override
  Listenable get changes => this;

  @override
  bool get isOnline => true;

  @override
  ConnectionPhase get phase => ConnectionPhase.online;

  @override
  String get hostLabel => '办公室电脑';

  @override
  String get hostId => 'agent-42';

  @override
  List<protocol.SessionInfo> get sessions => const [];

  @override
  SessionView view(protocol.SessionInfo info) => SessionView(info);

  @override
  Future<void> refreshSessions() async {}

  @override
  Future<void> subscribe(String id, {required Object owner}) async {}

  @override
  void unsubscribe(String id, {required Object owner}) {}

  @override
  Future<void> send(String id, String text) async {}

  @override
  Future<void> respondPermission(
    String id,
    String requestId,
    String decision, {
    String? message,
    Map<String, String>? answers,
  }) async {}

  @override
  Future<void> terminalInput(String id, String data) async {}

  @override
  Future<void> terminalResize(String id, int cols, int rows) async {}

  @override
  Future<void> closeSession(String id) async {}

  @override
  Future<protocol.SessionInfo> createSession({
    required String cwd,
    String? prompt,
  }) async => throw UnimplementedError();

  @override
  Future<protocol.SessionInfo> createTerminal({required String cwd}) async =>
      throw UnimplementedError();
}

protocol.AgentInfo _info({
  String host = 'DESKTOP-7',
  String platform = 'win32',
  String? hostName,
  String? os,
  String? osVersion,
}) => protocol.AgentInfo(
  host: host,
  platform: platform,
  defaultCwd: r'C:\work',
  roots: const [r'C:\work'],
  allowBypass: false,
  hostName: hostName,
  os: os,
  osVersion: osVersion,
);

void main() {
  test('reported device fields reach the host unchanged', () async {
    final port = FakeDevicePort(
      info: _info(
        hostName: '工作台',
        os: 'windows',
        osVersion: 'Windows 11 23H2 (22631)',
      ),
    );
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    final device = host.device.value;
    expect(device.hostName, '工作台');
    expect(device.os, HarnessDeviceOs.windows);
    expect(device.osVersion, 'Windows 11 23H2 (22631)');
    expect(device.isEmpty, isFalse);
  });

  test('a missing hostName falls back to host', () async {
    final port = FakeDevicePort(info: _info(host: 'DESKTOP-7'));
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    expect(host.device.value.hostName, 'DESKTOP-7');
  });

  test('os maps the three reported short names', () async {
    for (final entry in {
      'windows': HarnessDeviceOs.windows,
      'macos': HarnessDeviceOs.macos,
      'linux': HarnessDeviceOs.linux,
    }.entries) {
      final port = FakeDevicePort(info: _info(os: entry.key));
      final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
      expect(host.device.value.os, entry.value, reason: entry.key);
      await host.dispose();
    }
  });

  test('os other falls back to the platform value', () async {
    for (final entry in {
      'win32': HarnessDeviceOs.windows,
      'darwin': HarnessDeviceOs.macos,
      'linux': HarnessDeviceOs.linux,
    }.entries) {
      final port = FakeDevicePort(
        info: _info(os: 'other', platform: entry.key),
      );
      final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
      expect(host.device.value.os, entry.value, reason: entry.key);
      await host.dispose();
    }
  });

  test('a missing os falls back to the platform value', () async {
    final port = FakeDevicePort(info: _info(platform: 'darwin'));
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    expect(host.device.value.os, HarnessDeviceOs.macos);
  });

  test('an unknown platform reports unknown instead of guessing', () async {
    final port = FakeDevicePort(
      info: _info(os: 'other', platform: 'freebsd'),
    );
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    expect(host.device.value.os, HarnessDeviceOs.unknown);
  });

  test(
    'an old agent that sends no device fields falls back to platform',
    () async {
      final port = FakeDevicePort(info: _info());
      final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
      addTearDown(host.dispose);

      final device = host.device.value;
      expect(device.os, HarnessDeviceOs.windows, reason: 'platform 兜底');
      expect(device.hostName, 'DESKTOP-7');
      expect(device.osVersion, isNull);
    },
  );

  test('the host reports nothing before the first info frame', () async {
    final port = FakeDevicePort();
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    expect(host.device.value.isEmpty, isTrue);
  });

  test('a later info frame updates the device value', () async {
    final port = FakeDevicePort(info: _info(hostName: '旧名字'));
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    final seen = <HarnessDeviceInfo>[];
    host.device.addListener(() => seen.add(host.device.value));

    port.agentInfo = _info(hostName: '新名字', os: 'macos', osVersion: 'macOS 15');

    expect(seen, hasLength(1));
    expect(host.device.value.hostName, '新名字');
    expect(host.device.value.os, HarnessDeviceOs.macos);
    expect(host.device.value.osVersion, 'macOS 15');
  });

  test('a port without device support reports empty', () async {
    final host = RemoteHarnessHost(remote: FakePlainPort(), hostId: 'agent-42');
    addTearDown(host.dispose);

    expect(host.device.value.isEmpty, isTrue);
    expect(harnessDeviceOf(host)?.isEmpty, isTrue);
  });

  test('harnessDeviceOf finds the device host', () async {
    final port = FakeDevicePort(info: _info(hostName: '工作台'));
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    expect(harnessDeviceOf(host)?.hostName, '工作台');
  });

  test('an empty osVersion becomes null instead of a blank string', () async {
    final port = FakeDevicePort(info: _info(osVersion: '   '));
    final host = RemoteHarnessHost(remote: port, hostId: 'agent-42');
    addTearDown(host.dispose);

    expect(host.device.value.osVersion, isNull);
  });
}

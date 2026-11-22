import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_models.dart';

/// Field names copied from real `herdr agent list` output (herdr 0.9.3).
const String _agentListJson = '''
{"id":"cli:agent:list","result":{"agents":[
 {"agent":"codex","agent_status":"idle","completion_seq":300,"cwd":"E:\\\\analysis",
  "focused":false,"pane_id":"w3F:pB","revision":2,"state_change_seq":300,
  "tab_id":"w3F:t1","terminal_id":"term_660c9c713c7151",
  "terminal_title":"执行 A D盘独立构建 | analysis",
  "terminal_title_stripped":"执行 A D盘独立构建 | analysis","workspace_id":"w3F"},
 {"agent":"pi","agent_session":{"agent":"pi","kind":"path","source":"herdr:pi",
  "value":"C:\\\\Users\\\\someone\\\\.pi\\\\agent\\\\sessions\\\\x.jsonl"},
  "agent_status":"working","cwd":null,"focused":true,"name":"pi-ui","pane_id":"w37:p14",
  "revision":17,"state_change_seq":383,"tab_id":"w37:t1",
  "terminal_id":"term_660cb54f79bcd3b","terminal_title":null,
  "terminal_title_stripped":null,"workspace_id":"w37"},
 {"agent":"claude","agent_status":"done","cwd":"D:\\\\MyNewProjects\\\\qflistudio",
  "focused":false,"name":null,"pane_id":"w37:p15","revision":3,"state_change_seq":386,
  "tab_id":"w37:t1","terminal_id":"term_660cd70ee31583e",
  "terminal_title":"✳ Herdr 与 studio 远程终端",
  "terminal_title_stripped":"Herdr 与 studio 远程终端","workspace_id":"w37"},
 {"agent":null,"agent_status":"unknown","cwd":"/tmp","focused":false,
  "pane_id":"w5C:p1","revision":1,"tab_id":"w5C:t1","terminal_id":"term_x",
  "terminal_title":"bash","terminal_title_stripped":"bash","workspace_id":"w5C"}
],"type":"agent_list"}}
''';

void main() {
  group('herdr agent parsing', () {
    test('parses the fields herdr agent list prints', () {
      final decoded = jsonDecode(_agentListJson) as Map<String, dynamic>;
      final result = decoded['result'] as Map<String, dynamic>;
      final agents = <Map<String, dynamic>>[
        for (final raw in result['agents'] as List<dynamic>)
          raw as Map<String, dynamic>,
      ];
      final infos = agents.map(HerdrAgentInfo.fromJson).toList();

      expect(infos, hasLength(4));
      expect(infos[0].paneId, 'w3F:pB');
      expect(infos[0].workspaceId, 'w3F');
      expect(infos[0].tabId, 'w3F:t1');
      expect(infos[0].agentKind, 'codex');
      expect(infos[0].status, HerdrAgentStatus.idle);
      expect(infos[0].cwd, r'E:\analysis');
      expect(infos[0].title, '执行 A D盘独立构建 | analysis');
      expect(infos[0].target, 'w3F:pB');

      // A named agent is addressed by name, and null titles fall back to it.
      expect(infos[1].name, 'pi-ui');
      expect(infos[1].target, 'pi-ui');
      expect(infos[1].cwd, isNull);
      expect(infos[1].displayTitle, 'pi-ui');
      expect(infos[1].status, HerdrAgentStatus.working);
    });

    test('stripped title wins over the raw title', () {
      final agent = HerdrAgentInfo.fromJson(<String, dynamic>{
        'pane_id': 'w1:p1',
        'workspace_id': 'w1',
        'tab_id': 'w1:t1',
        'agent': 'claude',
        'agent_status': 'done',
        'focused': true,
        'terminal_title': '✳ 带装饰的标题',
        'terminal_title_stripped': '带装饰的标题',
      });
      expect(agent.title, '带装饰的标题');
      expect(agent.displayTitle, '带装饰的标题');
    });

    test('a pane without an agent is a shell provider', () {
      final agent = HerdrAgentInfo.fromJson(<String, dynamic>{
        'pane_id': 'w5C:p1',
        'workspace_id': 'w5C',
        'tab_id': 'w5C:t1',
        'agent_status': 'unknown',
        'focused': false,
        'terminal_title_stripped': 'bash',
      });
      expect(agent.agentKind, '');
      expect(agent.providerId, 'shell');
      expect(agent.status, HerdrAgentStatus.unknown);
      expect(agent.displayTitle, 'bash');
    });

    test('unknown statuses degrade instead of throwing', () {
      final agent = HerdrAgentInfo.fromJson(<String, dynamic>{
        'pane_id': 'w1:p1',
        'workspace_id': 'w1',
        'tab_id': 'w1:t1',
        'agent': 'pi',
        'agent_status': 'paused',
        'focused': false,
      });
      expect(agent.status, HerdrAgentStatus.unknown);
    });

    test('status mapping covers every Herdr state', () {
      expect(
        harnessStatusFor(HerdrAgentStatus.idle),
        HarnessSessionStatus.idle,
      );
      expect(
        harnessStatusFor(HerdrAgentStatus.working),
        HarnessSessionStatus.working,
      );
      expect(
        harnessStatusFor(HerdrAgentStatus.blocked),
        HarnessSessionStatus.blocked,
      );
      expect(
        harnessStatusFor(HerdrAgentStatus.done),
        HarnessSessionStatus.done,
      );
      expect(
        harnessStatusFor(HerdrAgentStatus.unknown),
        HarnessSessionStatus.unknown,
      );
    });

    test('session info exposes herdr capabilities and the pane reference', () {
      final agent = HerdrAgentInfo.fromJson(<String, dynamic>{
        'pane_id': 'w37:p15',
        'workspace_id': 'w37',
        'tab_id': 'w37:t1',
        'agent': 'claude',
        'agent_status': 'blocked',
        'focused': false,
        'cwd': r'D:\MyNewProjects\qflistudio',
        'terminal_title_stripped': 'Herdr 与 studio 远程终端',
      });
      final info = agent.toSessionInfo(hostId: 'herdr');
      expect(info.id, 'w37:p15');
      expect(info.hostId, 'herdr');
      expect(info.providerId, 'claude');
      expect(info.status, HarnessSessionStatus.blocked);
      expect(info.cwd, r'D:\MyNewProjects\qflistudio');
      expect(info.sourceRef, 'w37:p15');
      expect(info.capabilities, contains(HarnessCapability.terminal));
      expect(info.capabilities, contains(HarnessCapability.prompt));
      expect(info.capabilities, contains(HarnessCapability.stop));
      // No structured transcript or approval API exists for a pane.
      expect(info.capabilities, isNot(contains(HarnessCapability.transcript)));
      expect(info.capabilities, isNot(contains(HarnessCapability.approve)));
    });
  });

  group('herdr workspace parsing', () {
    test('parses labels and counts', () {
      final workspace = HerdrWorkspaceInfo.fromJson(<String, dynamic>{
        'workspace_id': 'w37',
        'label': 'qflistudio',
        'number': 3,
        'focused': true,
        'agent_status': 'done',
        'pane_count': 6,
        'tab_count': 1,
        'active_tab_id': 'w37:t1',
      });
      expect(workspace.workspaceId, 'w37');
      expect(workspace.displayLabel, 'qflistudio');
      expect(workspace.status, HerdrAgentStatus.done);
      expect(workspace.paneCount, 6);
    });

    test('an unlabelled workspace falls back to its id', () {
      final workspace = HerdrWorkspaceInfo.fromJson(<String, dynamic>{
        'workspace_id': 'w5C',
        'label': '',
        'number': 8,
        'focused': false,
        'agent_status': 'unknown',
      });
      expect(workspace.displayLabel, 'w5C');
      expect(workspace.paneCount, 0);
    });
  });
}

// Vibe e2e harness self-check. Runs offline: no upstream, no credential.
// It pins the report schema, the redaction rules and the skip behaviour.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart'
    show VibeMessage, VibePhase, VibeToolCall, VibeToolStatus;

import '../tool/vibe_e2e_report.dart';
import '../tool/vibe_e2e_scenarios.dart';

const _env = {
  'QFLI_DEBUG_BASE_URL': 'https://newapi.azurekiln.cn/v1',
  'QFLI_DEBUG_API_KEY': 'not-a-real-key-0123456789',
  'QFLI_DEBUG_MODEL': 'deepseek-v4.1-flash',
};

void main() {
  group('credentials', () {
    test('reads all three variables from the environment map', () {
      final credentials = VibeE2eCredentials.fromEnvironment(_env);
      expect(credentials, isNotNull);
      expect(credentials!.model, 'deepseek-v4.1-flash');
      expect(credentials.baseUrl, 'https://newapi.azurekiln.cn/v1');
    });

    test('returns null when any variable is missing or blank', () {
      expect(VibeE2eCredentials.fromEnvironment(const {}), isNull);
      for (final key in _env.keys) {
        final partial = Map<String, String>.from(_env)..remove(key);
        expect(
          VibeE2eCredentials.fromEnvironment(partial),
          isNull,
          reason: '缺少 $key 时必须视为未配置',
        );
        final blank = Map<String, String>.from(_env)..[key] = '   ';
        expect(
          VibeE2eCredentials.fromEnvironment(blank),
          isNull,
          reason: '$key 为空白时必须视为未配置',
        );
      }
    });

    test('redacted summary never carries the key', () {
      final summary = VibeE2eCredentials.fromEnvironment(
        _env,
      )!.redacted(protocol: 'chat_completions');
      expect(summary['baseHost'], 'newapi.azurekiln.cn');
      expect(summary['keyPresent'], isTrue);
      expect(summary['keyLength'], _env['QFLI_DEBUG_API_KEY']!.length);
      final text = jsonEncode(summary);
      expect(text.contains(_env['QFLI_DEBUG_API_KEY']!), isFalse);
      expect(text.contains('apiKey'), isFalse);
    });

    test('toString never prints the key', () {
      final credentials = VibeE2eCredentials.fromEnvironment(_env)!;
      expect(
        credentials.toString().contains(_env['QFLI_DEBUG_API_KEY']!),
        isFalse,
      );
      expect(credentials.toString(), contains('REDACTED'));
    });
  });

  group('report', () {
    test('skipped scenarios produce a skipped report without credentials', () {
      final report = VibeE2eReport(
        generatedAt: DateTime.utc(2026, 11, 1),
        environment: const {'keyPresent': false},
        scenarios: [
          for (final scenario in vibeE2eScenarios)
            VibeE2eScenarioResult(
              key: scenario.key,
              status: VibeE2eStatus.skipped,
              phase: VibePhase.idle.name,
              durationMs: 0,
              skipReason: '缺少凭据',
            ),
        ],
      );
      expect(report.status, VibeE2eStatus.skipped);
      final json = report.toJson();
      expect(json['schema'], kVibeE2eSchema);
      expect(vibeE2eReportProblems(json), isEmpty);
    });

    test('one failure makes the whole report fail', () {
      final report = VibeE2eReport(
        generatedAt: DateTime.utc(2026, 11, 1),
        environment: const {'keyPresent': false},
        scenarios: [
          VibeE2eScenarioResult(
            key: 'python_fix_loop',
            status: VibeE2eStatus.passed,
            phase: VibePhase.succeeded.name,
            durationMs: 1200,
          ),
          VibeE2eScenarioResult(
            key: 'static_site',
            status: VibeE2eStatus.failed,
            phase: VibePhase.failed.name,
            durationMs: 900,
            lastError: '已达到 8 轮工具调用上限，任务未完成',
          ),
        ],
      );
      expect(report.status, VibeE2eStatus.failed);
    });

    test(
      'writer round-trips through disk and reader validates schema',
      () async {
        final dir = await Directory.systemTemp.createTemp('vibe-e2e-report-');
        addTearDown(() => dir.delete(recursive: true));
        final file = VibeE2eReportWriter.defaultFile(
          DateTime.utc(2026, 11, 1, 8, 30, 5),
          scratch: dir,
        );
        final report = VibeE2eReport(
          generatedAt: DateTime.utc(2026, 11, 1, 8, 30, 5),
          environment: VibeE2eCredentials.fromEnvironment(
            _env,
          )!.redacted(protocol: 'backend_default'),
          scenarios: [
            VibeE2eScenarioResult(
              key: 'static_site',
              status: VibeE2eStatus.passed,
              phase: VibePhase.succeeded.name,
              durationMs: 30000,
              tools: [
                {'name': 'write_file', 'status': 'ok', 'summary': 'index.html'},
              ],
              assertions: const [
                VibeE2eAssertion(
                  name: 'index_written',
                  ok: true,
                  detail: 'index.html',
                ),
              ],
              extra: const {
                'projectFiles': {'index.html': 512},
              },
            ),
          ],
        );
        await VibeE2eReportWriter.write(file, report);
        expect(file.path, contains(p.join('.artifacts', 'vibe-e2e')));
        final raw = file.readAsStringSync();
        expect(raw.contains(_env['QFLI_DEBUG_API_KEY']!), isFalse);
        final decoded = VibeE2eReportReader.read(file.path);
        expect(vibeE2eReportProblems(decoded), isEmpty);
        final scenarios = decoded['scenarios'] as List;
        expect((scenarios.single as Map)['key'], 'static_site');
      },
    );

    test('reader rejects an unknown schema', () async {
      final file = File(
        p.join(
          Directory.systemTemp.createTempSync('vibe-e2e-schema-').path,
          'report.json',
        ),
      );
      addTearDown(() => file.parent.delete(recursive: true));
      file.writeAsStringSync(jsonEncode({'schema': 99, 'scenarios': []}));
      expect(() => VibeE2eReportReader.read(file.path), throwsFormatException);
    });
  });

  group('redaction guard', () {
    test('report problems flag leaked key material', () {
      final leaked = {
        'schema': kVibeE2eSchema,
        'environment': {'keyPresent': true},
        'scenarios': [
          {
            'key': 'static_site',
            'status': 'passed',
            'tools': [
              {'name': 'run_command', 'output': 'Authorization: Bearer sk-abc'},
            ],
          },
        ],
      };
      final problems = vibeE2eReportProblems(leaked);
      expect(problems, isNotEmpty);
      expect(problems.any((text) => text.contains('敏感片段')), isTrue);
    });

    test('report problems reject an apiKey field in the environment', () {
      final problems = vibeE2eReportProblems({
        'schema': kVibeE2eSchema,
        'environment': {'apiKey': 'x'},
        'scenarios': [
          {'key': 'static_site', 'status': 'passed'},
        ],
      });
      expect(problems, contains('environment 泄露密钥字段'));
    });
  });

  group('scenarios', () {
    test('scenario keys and prompts are stable', () {
      expect(vibeE2eScenarios.map((s) => s.key), [
        'static_site',
        'python_fix_loop',
        'web_search',
      ]);
      final site = vibeE2eScenarios.firstWhere((s) => s.key == 'static_site');
      expect(site.prompt, contains('待办事项小网站'));
      final search = vibeE2eScenarios.firstWhere((s) => s.key == 'web_search');
      expect(search.requiresSearchTools, isTrue);
    });

    test('every declared assertion name is registered', () {
      final declared = <String>{};
      final dir = Directory.systemTemp.createTempSync('vibe-e2e-outcome-');
      addTearDown(() => dir.delete(recursive: true));
      for (final scenario in vibeE2eScenarios) {
        final outcome = VibeE2eScenarioOutcome(
          projectRoot: dir.path,
          phase: VibePhase.failed,
          toolCalls: const [],
          messages: const [],
          changedFiles: const [],
        );
        declared.addAll(
          scenario.assertions!.call(outcome).map((assertion) => assertion.name),
        );
      }
      expect(declared.difference(kVibeE2eAssertionNames), isEmpty);
    });

    test('static site scenario needs the three real files', () async {
      final root = Directory.systemTemp.createTempSync('vibe-e2e-site-');
      addTearDown(() => root.delete(recursive: true));
      final scenario = vibeE2eScenarios.firstWhere(
        (s) => s.key == 'static_site',
      );
      await scenario.prepare!(root.path);
      expect(File(p.join(root.path, 'README.md')).existsSync(), isTrue);

      final outcome = VibeE2eScenarioOutcome(
        projectRoot: root.path,
        phase: VibePhase.succeeded,
        toolCalls: const [
          VibeToolCall(
            id: 'c1',
            toolName: 'write_file',
            summary: 'index.html',
            status: VibeToolStatus.ok,
          ),
        ],
        messages: const [],
        changedFiles: const ['index.html'],
      );
      final assertions = scenario.assertions!(outcome);
      final byName = {for (final a in assertions) a.name: a.ok};
      expect(byName['index_written'], isTrue);
      expect(byName['style_written'], isFalse);
      expect(byName['html_references_assets'], isFalse);

      // 只有引用、没有真实资产时，结构化检查必须报问题。
      final htmlOnly = scenario.assertions!(outcome);
      final htmlOnlyByName = {for (final a in htmlOnly) a.name: a};
      expect(htmlOnlyByName['html_well_formed']!.ok, isFalse);
      expect(
        htmlOnlyByName['html_assets_exist']!.detail,
        contains('index.html'),
      );

      File(p.join(root.path, 'index.html')).writeAsStringSync(
        '<!doctype html><html><head>'
        '<link rel="stylesheet" href="style.css">'
        '</head><body>'
        '<script src="app.js"></script>'
        '</body></html>',
      );
      File(p.join(root.path, 'style.css')).writeAsStringSync('body{}');
      File(
        p.join(root.path, 'app.js'),
      ).writeAsStringSync('document.addEventListener("click", () {});');
      final passed = scenario.assertions!(
        VibeE2eScenarioOutcome(
          projectRoot: root.path,
          phase: VibePhase.succeeded,
          toolCalls: const [],
          messages: const [],
          changedFiles: const ['index.html', 'style.css', 'app.js'],
        ),
      );
      final failed = passed.where((assertion) => !assertion.ok).toList();
      expect(
        failed,
        isEmpty,
        reason: failed
            .map((assertion) => '${assertion.name}=${assertion.detail}')
            .join(', '),
      );
    });

    test('fix loop fails when the first run never really failed', () {
      final outcome = VibeE2eScenarioOutcome(
        projectRoot: Directory.systemTemp.path,
        phase: VibePhase.succeeded,
        toolCalls: const [
          VibeToolCall(
            id: 'r1',
            toolName: 'run_command',
            summary: 'python3 verify.py',
            status: VibeToolStatus.ok,
            exitCode: 0,
          ),
          VibeToolCall(
            id: 'r2',
            toolName: 'run_command',
            summary: 'python3 verify.py',
            status: VibeToolStatus.ok,
            exitCode: 0,
            commandOutput: 'QFLI_VIBE_VERIFIED_42',
          ),
        ],
        messages: const [],
        changedFiles: const [],
      );
      final assertions = VibeE2eAssertions.firstFailLastPass(outcome);
      expect(
        assertions.firstWhere((a) => a.name == 'first_run_failed').ok,
        isFalse,
      );
      expect(
        assertions.firstWhere((a) => a.name == 'last_run_passed').ok,
        isTrue,
      );
    });

    test('a single run is not evidence of a fix loop', () {
      final assertions = VibeE2eAssertions.firstFailLastPass(
        const VibeE2eScenarioOutcome(
          projectRoot: '.',
          phase: VibePhase.succeeded,
          toolCalls: [
            VibeToolCall(
              id: 'r1',
              toolName: 'run_command',
              summary: 'python3 verify.py',
              status: VibeToolStatus.ok,
              exitCode: 0,
            ),
          ],
          messages: [],
          changedFiles: [],
        ),
      );
      expect(assertions.single.name, 'runs_at_least_two');
      expect(assertions.single.ok, isFalse);
    });
  });

  group('tool evidence', () {
    test('keeps the real exit code and the output tail', () {
      final evidence = vibeE2eToolEvidence([
        VibeToolCall(
          id: 'r1',
          toolName: 'run_command',
          summary: 'python3 verify.py',
          status: VibeToolStatus.error,
          exitCode: 1,
          commandOutput: '${'x' * 6000}AssertionError',
        ),
      ], maxOutput: 100);
      expect(evidence.single['exitCode'], 1);
      final output = evidence.single['output'] as String;
      expect(output.length, lessThan(140));
      expect(output, endsWith('AssertionError'));
    });

    test('search tool detection follows the published specs', () {
      expect(vibeE2eHasSearchTools(const []), isFalse);
      expect(
        vibeE2eHasSearchTools(const [
          {
            'type': 'function',
            'function': {'name': 'web_search'},
          },
        ]),
        isTrue,
      );
    });

    test('citations that the tools never returned are caught', () {
      final scenario = vibeE2eScenarios.firstWhere(
        (s) => s.key == 'web_search',
      );
      // 工具真的返回过 example.com 的链接，模型另外编了一个。
      final outcome = VibeE2eScenarioOutcome(
        projectRoot: Directory.systemTemp.path,
        phase: VibePhase.succeeded,
        toolCalls: const [
          VibeToolCall(
            id: '1',
            toolName: 'web_search',
            summary: '{}',
            status: VibeToolStatus.ok,
            result: '直连：8 条结果',
          ),
        ],
        messages: const [
          VibeMessage(
            isUser: false,
            text: '见 https://example.com/a 与 https://fake.test/b',
          ),
        ],
        changedFiles: const [],
        toolPayloads: const [
          VibeToolPayload(
            toolName: 'web_search',
            arguments: '{}',
            result: 'https://example.com/a',
          ),
        ],
      );
      final byName = {for (final a in scenario.assertions!(outcome)) a.name: a};
      expect(byName['reply_cites_url']!.ok, isTrue);
      expect(byName['citations_from_tool_output']!.ok, isFalse);
      expect(
        byName['citations_from_tool_output']!.detail,
        contains('https://fake.test/b'),
      );
    });

    test('verification ignores a trailing run with no exit code', () {
      final scenario = vibeE2eScenarios.firstWhere(
        (s) => s.key == 'python_fix_loop',
      );
      VibeToolCall run(int? exit, String? output) => VibeToolCall(
        id: 'r$exit',
        toolName: 'run_command',
        summary: 'python3 verify.py',
        status: exit == 0 ? VibeToolStatus.ok : VibeToolStatus.error,
        result: exit == null ? '未登录或登录已过期' : '跨应用 · 退出码 $exit',
        exitCode: exit,
        commandOutput: output,
      );
      final outcome = VibeE2eScenarioOutcome(
        projectRoot: Directory.systemTemp.path,
        phase: VibePhase.succeeded,
        toolCalls: [
          run(1, 'AssertionError'),
          run(0, 'QFLI_VIBE_VERIFIED_42'),
          run(null, null), // 云终端 401：不是命令结果
          const VibeToolCall(
            id: 'e1',
            toolName: 'edit_file',
            summary: 'math_ops.py',
            status: VibeToolStatus.ok,
            result: '已替换 math_ops.py',
          ),
        ],
        messages: const [],
        changedFiles: const [],
      );
      final byName = {for (final a in scenario.assertions!(outcome)) a.name: a};
      expect(byName['verification_marker']!.ok, isTrue);
      expect(byName['verification_marker']!.detail, contains('无退出码的调用 1 次'));
    });

    test('citations the tools returned are accepted', () {
      final scenario = vibeE2eScenarios.firstWhere(
        (s) => s.key == 'web_search',
      );
      final outcome = VibeE2eScenarioOutcome(
        projectRoot: Directory.systemTemp.path,
        phase: VibePhase.succeeded,
        toolCalls: const [
          VibeToolCall(
            id: '1',
            toolName: 'web_search',
            summary: '{}',
            status: VibeToolStatus.ok,
            result: '直连：8 条结果',
          ),
        ],
        messages: const [
          VibeMessage(isUser: false, text: '最新版本见 https://example.com/a 。'),
        ],
        changedFiles: const [],
        toolPayloads: const [
          VibeToolPayload(
            toolName: 'web_search',
            arguments: '{}',
            result: 'https://example.com/a',
          ),
        ],
      );
      final failed = scenario.assertions!(outcome).where((a) => !a.ok).toList();
      expect(
        failed,
        isEmpty,
        reason: failed.map((a) => '${a.name}=${a.detail}').join(', '),
      );
    });
  });
}

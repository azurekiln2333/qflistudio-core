import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/trellis/trellis_commands.dart';
import 'package:qfli_studio_core/trellis/trellis_context.dart';
import 'package:qfli_studio_core/trellis/trellis_project.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_rules.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_skills.dart';

import 'support/trellis_fixture.dart';

/// 不提供任何内置技能资产。
class _NoAssets extends CachingAssetBundle {
  _NoAssets();

  @override
  Future<ByteData> load(String key) async =>
      throw StateError('missing asset $key');

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      throw StateError('missing asset $key');
}

void main() {
  group('context text', () {
    test('lists the current task, phase, docs and spec indexes', () async {
      final project = await TrellisProject.load(makeTrellisProject().path);
      final text = buildTrellisContext(project!);
      expect(text, startsWith('### Trellis 项目上下文'));
      expect(text, contains('开发者：lichengyu'));
      expect(text, contains('当前任务：11-22-harness-hub'));
      expect(text, contains('阶段 2 Execute'));
      expect(text, contains('下一步 2.1'));
      expect(text, contains('prd.md'));
      expect(text, contains('implement.md（缺）'));
      expect(text, contains('活跃任务（共 2 个）'));
      expect(text, contains('.trellis/spec/frontend/index.md'));
      expect(text.length, lessThanOrEqualTo(kTrellisContextMaxChars));
    });

    test('stays within the character budget with many tasks', () async {
      final root = makeTrellisProject();
      for (var i = 0; i < 40; i++) {
        writeFixture(
          root,
          '.trellis/tasks/12-00-many-$i/task.json',
          '{"id":"many-$i","title":"${'任务标题' * 20}$i",'
              '"status":"in_progress","assignee":"lichengyu"}',
        );
      }
      final project = await TrellisProject.load(root.path);
      final text = buildTrellisContext(project!);
      expect(text.length, lessThanOrEqualTo(kTrellisContextMaxChars));
      // 只列前 maxTasks 个任务，标题再长也裁到上限，所以这份上下文根本没到
      // 字符上限，不该带截断标记。撑大预算的是行数上限，这里钉住它。
      expect(text, contains('列出前 $kTrellisContextMaxTasks 个'));
      expect(text, isNot(contains('上下文已截断')));
    });

    test(
      'clamps the context when one block alone exceeds the budget',
      () async {
        final root = makeTrellisProject();
        // 规范索引逐条列出，不按数量截断；层多到一定地步，单这一块就会超预算。
        for (var i = 0; i < 80; i++) {
          writeFixture(root, '.trellis/spec/layer-$i/index.md', '# L$i\n');
        }
        final project = await TrellisProject.load(root.path);

        // 先证明夹具真的超了预算，否则下面那条“截断过”的断言会假通过。
        final unclamped = buildTrellisContext(project!, maxChars: 1 << 20);
        expect(unclamped.length, greaterThan(kTrellisContextMaxChars));

        final text = buildTrellisContext(project);
        expect(text.length, lessThanOrEqualTo(kTrellisContextMaxChars));
        expect(text, contains('上下文已截断'));
      },
    );

    test('clamp keeps the cut on a line boundary inside the budget', () {
      final text = clampTrellisContext('${'一行内容' * 400}\n', 200);
      expect(text.length, lessThanOrEqualTo(200));
      expect(text, contains('上下文已截断'));
    });

    test('reports an undetermined current task honestly', () async {
      final root = makeTrellisProject();
      Directory(
        '${root.path}${Platform.pathSeparator}.trellis'
        '${Platform.pathSeparator}.runtime'
        '${Platform.pathSeparator}sessions',
      ).deleteSync(recursive: true);
      final project = await TrellisProject.load(root.path);
      expect(project!.currentTask, isNull);
      expect(buildTrellisContext(project), contains('当前任务：未确定'));
    });
  });

  group('script compaction', () {
    test('drops the banner and bounds the change list', () {
      final text = [
        '========================================',
        'SESSION CONTEXT',
        '========================================',
        '',
        '## DEVELOPER',
        'Name: lichengyu',
        '',
        '## GIT STATUS',
        'Branch: main',
        'Changes:',
        for (var i = 0; i < 9; i++) ' M lib/file_$i.dart',
        '',
        '## CURRENT TASK',
        'Path: .trellis/tasks/x',
      ].join('\n');
      final compact = compactScriptContext(text);
      expect(compact, isNot(contains('=====')));
      expect(compact, isNot(contains('SESSION CONTEXT')));
      expect(compact, contains('Name: lichengyu'));
      expect(compact, contains('M lib/file_4.dart'));
      expect(compact, isNot(contains('M lib/file_5.dart')));
      expect(compact, contains('其余改动未列出'));
      expect(compact, contains('## CURRENT TASK'));
    });
  });

  group('context loader', () {
    test('returns an empty string outside a Trellis project', () async {
      final root = Directory.systemTemp.createTempSync('trellis-none-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      expect(await const TrellisContextLoader().load(root.path), isEmpty);
    });

    test('parses with Dart when the Python script is absent', () async {
      final project = await TrellisProject.load(makeTrellisProject().path);
      final text = await const TrellisContextLoader(
        preferPython: true,
      ).load(project!.root);
      expect(text, contains('### Trellis 项目上下文'));
      expect(text, contains('11-22-harness-hub'));
    });

    test('does not run the project script without explicit consent', () async {
      final root = makeTrellisProject();
      // 脚本被真正执行时才会写这个文件。
      final marker = p.join(root.path, 'script-ran.txt');
      writeFixture(
        root,
        '.trellis/scripts/get_context.py',
        'open(${jsonEncode(marker)}, "w").write("ran")\n',
      );

      final text = await const TrellisContextLoader(
        preferPython: true,
      ).load(root.path);

      expect(text, contains('### Trellis 项目上下文'));
      expect(File(marker).existsSync(), isFalse);
    });

    test('runs the script only when both switches are on', () {
      expect(
        const TrellisContextLoader(preferPython: true).runsProjectScript,
        isFalse,
      );
      expect(
        const TrellisContextLoader(allowProjectScript: true).runsProjectScript,
        isFalse,
      );
      expect(
        const TrellisContextLoader(
          preferPython: true,
          allowProjectScript: true,
        ).runsProjectScript,
        isTrue,
      );
      expect(const TrellisContextLoader().runsProjectScript, isFalse);
    });

    test('ignores a symlinked get_context.py', () async {
      final root = makeTrellisProject();
      final outside = File(p.join(root.path, 'outside.py'))
        ..writeAsStringSync('raise SystemExit(1)\n');
      final link = Link(
        p.join(root.path, '.trellis', 'scripts', 'get_context.py'),
      );
      Directory(link.parent.path).createSync(recursive: true);
      link.createSync(outside.path);

      final text = await const TrellisContextLoader(
        preferPython: true,
        allowProjectScript: true,
      ).load(root.path);

      // 链接被拒后回退到 Dart 解析，结果仍然可用。
      expect(text, contains('### Trellis 项目上下文'));
    });
  });

  group('script deadline', () {
    test('gives up on a wait that never ends', () async {
      final pending = Completer<String>();
      final settled = await awaitWithin(
        pending.future,
        const Duration(milliseconds: 20),
      );
      expect(settled, isNull);
      // 放弃等待不等于失信：原 future 仍然可以正常完成。
      pending.complete('晚到的正文');
      expect(await pending.future, '晚到的正文');
    });

    test('passes a value that arrives in time', () async {
      expect(
        await awaitWithin(
          Future<String>.value('正文'),
          const Duration(seconds: 1),
        ),
        '正文',
      );
    });

    test('keeps the error instead of hiding it', () async {
      await expectLater(
        awaitWithin(
          Future<String>.error(const FileSystemException('读不到')),
          const Duration(seconds: 1),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('project rules', () {
    test('reserves the Trellis entry before rule files', () {
      final root = makeTrellisProject();
      writeFixture(root, 'AGENTS.md', 'agent rule\n');
      final rules = loadVibeRules(root.path);
      expect(rules, startsWith('### Trellis workflow'));
      expect(rules, contains('.trellis/workflow.md'));
      expect(
        rules.indexOf('### Trellis workflow'),
        lessThan(rules.indexOf('### AGENTS.md')),
      );
      expect(rules.length, lessThan(kVibeMaxRulesChars + 16));
    });

    test('keeps the entry when AGENTS.md exceeds the budget', () {
      final root = makeTrellisProject();
      writeFixture(root, 'AGENTS.md', '${'a' * 40}\n' * 400);
      final rules = loadVibeRules(root.path);
      expect(rules, startsWith('### Trellis workflow'));
      expect(rules.length, lessThan(kVibeMaxRulesChars + 16));
    });

    test('skips the entry without a real workflow', () {
      final root = Directory.systemTemp.createTempSync('trellis-none-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      writeFixture(root, 'AGENTS.md', 'agent rule\n');
      final rules = loadVibeRules(root.path);
      expect(rules, isNot(contains('Trellis')));
    });
  });

  group('slash commands', () {
    late Directory root;

    setUp(() {
      root = makeTrellisProject();
    });

    test('matches the two supported commands only', () {
      expect(
        matchTrellisSlashCommand('/trellis:continue')?.name,
        '/trellis:continue',
      );
      expect(
        matchTrellisSlashCommand('  /trellis:finish-work now')?.name,
        '/trellis:finish-work',
      );
      expect(matchTrellisSlashCommand('/trellis:continuex'), isNull);
      expect(matchTrellisSlashCommand('继续'), isNull);
      expect(
        trellisCommandArguments(
          matchTrellisSlashCommand('/trellis:continue 继续实现')!,
          '/trellis:continue 继续实现',
        ),
        '继续实现',
      );
    });

    test('prefers a visible skill body', () async {
      writeFixture(
        root,
        '.qfli/skills/trellis-continue/SKILL.md',
        '---\nname: trellis-continue\ndescription: 继续任务\n---\n'
            '技能正文：先读工作流。\n',
      );
      final skills = await VibeSkillLibrary(
        projectRoot: root.path,
        bundle: _NoAssets(),
        includeUserSkills: false,
        lazyBodies: true,
      ).load();
      final routed = await routeTrellisSlashCommand(
        '/trellis:continue 接着做',
        projectRoot: root.path,
        skills: skills,
      );
      expect(routed, startsWith('/trellis:continue：接着做'));
      expect(routed, contains('技能正文：先读工作流。'));
    });

    test('falls back to the project command file', () async {
      writeFixture(
        root,
        '.pi/prompts/trellis-continue.md',
        '# Continue\n\n项目命令文件内容\n',
      );
      final routed = await routeTrellisSlashCommand(
        '/trellis:continue',
        projectRoot: root.path,
        skills: const [],
      );
      expect(routed, contains('项目命令文件内容'));
    });

    test('falls back to the built-in instructions', () async {
      final routed = await routeTrellisSlashCommand(
        '/trellis:finish-work',
        projectRoot: root.path,
        skills: const [],
      );
      expect(routed, contains('task.py archive'));
      expect(routed, contains('add_session.py'));
    });

    test('ignores commands outside a Trellis project', () async {
      final plain = Directory.systemTemp.createTempSync('trellis-none-');
      addTearDown(() {
        if (plain.existsSync()) plain.deleteSync(recursive: true);
      });
      expect(
        await routeTrellisSlashCommand(
          '/trellis:continue',
          projectRoot: plain.path,
          skills: const [],
        ),
        isNull,
      );
    });
  });
}

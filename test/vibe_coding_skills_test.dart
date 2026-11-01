import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/vibe_coding/vibe_skills.dart';

/// Serves a fixed set of packaged skill assets and records every load.
class _FakeAssets extends CachingAssetBundle {
  _FakeAssets(this.files);

  final Map<String, String> files;
  final List<String> loads = [];

  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    final text = files[key];
    if (text == null) throw StateError('missing asset $key');
    final bytes = Uint8List.fromList(text.codeUnits);
    return ByteData.view(bytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    await load(key);
    return files[key]!;
  }
}

void main() {
  late Directory root;

  setUp(() {
    VibeSkillLibrary.resetBuiltInCache();
    root = Directory.systemTemp.createTempSync('vibe-skills-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void writeSkill(String relative, String text) {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  group('parseVibeSkill', () {
    test('reads name and description from the front matter only', () {
      final skill = parseVibeSkill(
        '---\n'
        'name: hello\n'
        'description: "say hi to the project"\n'
        'allowed-tools: [Read]\n'
        '---\n'
        '# Body\n\nStep one.\n',
        fallbackName: 'ignored',
        source: VibeSkillSource.projectQfli,
      );
      expect(skill, isNotNull);
      expect(skill!.name, 'hello');
      expect(skill.description, 'say hi to the project');
      expect(skill.body, startsWith('# Body'));
      expect(skill.body, isNot(contains('allowed-tools')));
      expect(skill.source, VibeSkillSource.projectQfli.label);
    });

    test('falls back to the directory name and folds a block description', () {
      final skill = parseVibeSkill(
        '---\n'
        'description: >-\n'
        '  first line\n'
        '  second line\n'
        '---\n'
        'body\n',
        fallbackName: 'dir-name',
        source: VibeSkillSource.agents,
      );
      expect(skill!.name, 'dir-name');
      expect(skill.description, 'first line second line');
    });

    test('skips a skill without a description', () {
      expect(
        parseVibeSkill(
          '---\nname: lonely\n---\nbody\n',
          fallbackName: 'lonely',
          source: VibeSkillSource.projectQfli,
        ),
        isNull,
      );
    });

    test('treats a file without front matter as a plain skill', () {
      expect(
        parseVibeSkill(
          'plain text',
          fallbackName: 'plain',
          source: VibeSkillSource.projectQfli,
        ),
        isNull,
      );
    });

    test('truncates an oversized body and marks it', () {
      final body = 'x' * (kVibeSkillMaxBodyChars + 10);
      final skill = parseVibeSkill(
        '---\nname: big\ndescription: d\n---\n$body',
        fallbackName: 'big',
        source: VibeSkillSource.projectQfli,
      );
      expect(skill!.truncated, isTrue);
      expect(skill.body.length, lessThan(kVibeSkillMaxBodyChars + 200));
      expect(skill.body, contains('技能正文已截断'));
    });
  });

  group('VibeSkillLibrary', () {
    test('orders sources and keeps the first name', () async {
      writeSkill(
        '.qfli/skills/one/SKILL.md',
        '---\nname: shared\ndescription: from qfli\n---\nqfli body\n',
      );
      writeSkill(
        '.claude/skills/two/SKILL.md',
        '---\nname: shared\ndescription: from claude\n---\nclaude body\n',
      );
      writeSkill(
        '.agents/skills/three/SKILL.md',
        '---\nname: agents-only\ndescription: from agents\n---\nagents body\n',
      );
      final assets = _FakeAssets({
        'assets/skills/web-app-scaffold/SKILL.md':
            '---\nname: web-app-scaffold\n'
            'description: site scaffold\n---\nscaffold body\n',
        // The host ships two more built-ins that a Python project still sees.
        'assets/skills/bug-fix-loop/SKILL.md':
            '---\nname: bug-fix-loop\ndescription: fix loop\n---\nbody\n',
      });
      final library = VibeSkillLibrary(
        projectRoot: root.path,
        language: 'python',
        bundle: assets,
      );

      final skills = await library.load();

      expect(skills.map((s) => s.name), [
        'agents-only',
        'bug-fix-loop',
        'shared',
        'web-app-scaffold',
      ]);
      expect(
        skills.firstWhere((s) => s.name == 'shared').description,
        'from qfli',
      );
      expect(assets.loads, [
        'assets/skills/web-app-scaffold/SKILL.md',
        'assets/skills/bug-fix-loop/SKILL.md',
        'assets/skills/project-review/SKILL.md',
        'assets/skills/web-research/SKILL.md',
      ]);
    });

    test('skips directories without SKILL.md and links', () async {
      Directory(
        p.join(root.path, '.qfli', 'skills', 'empty'),
      ).createSync(recursive: true);
      writeSkill(
        '.qfli/skills/real/SKILL.md',
        '---\nname: real\ndescription: d\n---\nbody\n',
      );
      final library = VibeSkillLibrary(
        projectRoot: root.path,
        bundle: _FakeAssets({}),
      );
      final skills = await library.load();
      expect(skills.map((s) => s.name), ['real']);
    });

    test('survives a host app that ships no skill assets', () async {
      writeSkill(
        '.qfli/skills/local/SKILL.md',
        '---\nname: local\ndescription: d\n---\nbody\n',
      );
      final library = VibeSkillLibrary(
        projectRoot: root.path,
        bundle: _FakeAssets({}),
      );
      final skills = await library.load();
      expect(skills.map((s) => s.name), ['local']);
    });

    test('caps the index and keeps it one line per skill', () {
      final skills = [
        for (var i = 0; i < 50; i++)
          VibeSkill(
            name: 'skill-$i',
            description: 'd' * 100,
            body: 'b',
            source: VibeSkillSource.projectQfli.label,
          ),
      ];
      final index = buildVibeSkillIndex(skills);
      expect(index.length, lessThanOrEqualTo(kVibeMaxSkillIndexChars + 40));
      expect(index, contains('技能索引已截断'));
      expect(index.split('\n').first, startsWith('- skill-0'));
    });
  });

  group('vibePromptWantsWeb', () {
    test('detects a site request in Chinese and English', () {
      expect(vibePromptWantsWeb('做一个待办事项小网站'), isTrue);
      expect(vibePromptWantsWeb('build a landing page'), isTrue);
      expect(vibePromptWantsWeb('修复 Python 脚本'), isFalse);
    });
  });

  group('built-in skills', () {
    test('every shipped SKILL.md parses with a description', () {
      for (final asset in VibeSkillLibrary.builtInAssetDirs) {
        final file = File(
          p.joinAll([Directory.current.path, ...asset.split('/')]),
        );
        expect(file.existsSync(), isTrue, reason: asset);
        final skill = parseVibeSkill(
          file.readAsStringSync(),
          fallbackName: p.basename(p.dirname(asset)),
          source: VibeSkillSource.builtIn,
        );
        expect(skill, isNotNull, reason: asset);
        expect(skill!.description, isNotEmpty, reason: asset);
        expect(skill.isBuiltIn, isTrue);
      }
    });

    test('web-research states the citation rule', () {
      final asset = VibeSkillLibrary.builtInAssetDirs.firstWhere(
        (dir) => dir.contains('web-research'),
      );
      final body = File(
        p.joinAll([Directory.current.path, ...asset.split('/')]),
      ).readAsStringSync();
      expect(body, contains('web_search'));
      expect(body, contains('web_fetch'));
      expect(body, contains('完整网址'));
      expect(body, contains('不编造'));
      expect(kVibeBuiltInSkillLanguages.containsKey('web-research'), isTrue);
    });
  });
}

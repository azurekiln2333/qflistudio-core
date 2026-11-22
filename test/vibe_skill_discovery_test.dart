import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/vibe_coding/vibe_skills.dart';

/// 只提供内置技能资产的 bundle；不给资产时返回空列表。
class _Assets extends CachingAssetBundle {
  _Assets(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw StateError('missing asset $key');
    return ByteData.view(Uint8List.fromList(text.codeUnits).buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    await load(key);
    return files[key]!;
  }
}

void main() {
  late Directory project;
  late Directory home;

  setUp(() {
    VibeSkillLibrary.resetBuiltInCache();
    project = Directory.systemTemp.createTempSync('skill-project-');
    home = Directory.systemTemp.createTempSync('skill-home-');
  });

  tearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  void writeSkill(Directory root, String dir, String name, String body) {
    final file = File(
      p.joinAll([root.path, ...dir.split('/'), name, 'SKILL.md']),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '---\nname: $name\ndescription: $dir 的 $name\n---\n$body\n',
    );
  }

  VibeSkillLibrary library({bool lazy = false}) => VibeSkillLibrary(
    projectRoot: project.path,
    bundle: _Assets(const {}),
    userSkillsDirs: [
      for (final dir in VibeSkillLibrary.userSkillDirNames)
        p.joinAll([home.path, ...dir.split('/')]),
    ],
    lazyBodies: lazy,
  );

  group('directory coverage', () {
    test('discovers .agents, .claude, .pi and .codex project skills', () async {
      writeSkill(project, '.agents/skills', 'agents-one', 'a');
      writeSkill(project, '.claude/skills', 'claude-one', 'c');
      writeSkill(project, '.pi/skills', 'pi-one', 'p');
      writeSkill(project, '.codex/skills', 'codex-one', 'x');
      final skills = await library().load();
      expect(skills.map((skill) => skill.name).toSet(), {
        'agents-one',
        'claude-one',
        'pi-one',
        'codex-one',
      });
      expect(
        skills.firstWhere((s) => s.name == 'pi-one').source,
        VibeSkillSource.pi.label,
      );
      expect(
        skills.firstWhere((s) => s.name == 'codex-one').source,
        VibeSkillSource.codex.label,
      );
    });

    test('reads the same directories under the user home', () async {
      final names = <String>{};
      for (final dir in VibeSkillLibrary.userSkillDirNames) {
        final name = 'home-${dir.split('/').first.replaceAll('.', '')}';
        writeSkill(home, dir, name, 'body');
        names.add(name);
      }
      final skills = await library().load();
      expect(skills.map((skill) => skill.name).toSet(), names);
      for (final skill in skills) {
        expect(skill.source, VibeSkillSource.user.label);
      }
    });

    test('user directories keep the declared priority order', () {
      expect(VibeSkillLibrary.userSkillDirNames, [
        '.qfli/skills',
        '.claude/skills',
        '.agents/skills',
        '.pi/skills',
        '.codex/skills',
      ]);
      expect(
        VibeSkillLibrary.projectSkillDirNames,
        VibeSkillLibrary.userSkillDirNames,
      );
    });

    test('a project skill wins over a user skill of the same name', () async {
      writeSkill(project, '.pi/skills', 'shared', 'project body');
      writeSkill(home, '.pi/skills', 'shared', 'user body');
      writeSkill(home, '.codex/skills', 'user-only', 'user body');
      final skills = await library().load();
      expect(
        skills.firstWhere((skill) => skill.name == 'shared').description,
        '.pi/skills 的 shared',
      );
      expect(
        skills.firstWhere((skill) => skill.name == 'shared').source,
        VibeSkillSource.pi.label,
      );
      expect(
        skills.where((skill) => skill.name == 'user-only').single.source,
        VibeSkillSource.user.label,
      );
    });
  });

  group('metadata only', () {
    test('lazy loading skips the body until asked', () async {
      writeSkill(project, '.agents/skills', 'slow', '正文第一部分');
      final skills = await library(lazy: true).load();
      final skill = skills.single;
      expect(skill.name, 'slow');
      expect(skill.description, '.agents/skills 的 slow');
      expect(skill.hasInlineBody, isFalse);
      expect(skill.bodyPath, isNotNull);
      expect(skill.body, isEmpty);

      final body = await skill.resolveBody();
      expect(body, '正文第一部分');
      // 第二次读仍从盘上取，读到的内容与第一次一致。
      expect(await skill.resolveBody(), body);
    });

    test('a missing file resolves to an empty body', () async {
      writeSkill(project, '.agents/skills', 'gone', 'body');
      final skills = await library(lazy: true).load();
      File(skills.single.bodyPath!).deleteSync();
      expect(await skills.single.resolveBody(), isEmpty);
    });

    test('an eager library still carries the body', () async {
      writeSkill(project, '.agents/skills', 'eager', '完整正文');
      final skills = await library().load();
      expect(skills.single.body, '完整正文');
      expect(await skills.single.resolveBody(), '完整正文');
    });

    test('an oversized body is truncated with a marker', () async {
      final big = 'x' * (kVibeSkillMaxBodyChars + 100);
      writeSkill(project, '.agents/skills', 'big', big);
      final skills = await library(lazy: true).load();
      final body = await skills.single.resolveBody();
      expect(body.length, lessThan(kVibeSkillMaxBodyChars + 100));
      expect(body, contains('技能正文已截断'));
    });
  });

  group('frontmatter', () {
    test('keeps the directory name when name is absent', () async {
      final file = File(
        p.join(project.path, '.codex', 'skills', 'dir-name', 'SKILL.md'),
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('---\ndescription: 只有描述\n---\n正文\n');
      final skills = await library().load();
      expect(skills.single.name, 'dir-name');
      expect(skills.single.description, '只有描述');
    });

    test('skips a skill with an empty description', () async {
      final file = File(
        p.join(project.path, '.pi', 'skills', 'no-desc', 'SKILL.md'),
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('---\nname: no-desc\ndescription:\n---\n正文\n');
      expect(await library().load(), isEmpty);
    });
  });
}

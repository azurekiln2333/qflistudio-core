import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('vibe-plan-'));

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void writeFile(String relative, String text) {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  group('parseVibePlan', () {
    test('defaults ids and status, and keeps order', () {
      final plan = parseVibePlan([
        {'title': 'structure'},
        {'id': 'b', 'title': 'styles', 'status': 'doing'},
        {'title': 'verify', 'status': 'done'},
      ]);
      expect(plan.map((i) => i.id), ['1', 'b', '3']);
      expect(plan.map((i) => i.status), [
        VibePlanStatus.pending,
        VibePlanStatus.doing,
        VibePlanStatus.done,
      ]);
      expect(vibePlanAllDone(plan), isFalse);
    });

    test('rejects an empty list, unknown state and two doing items', () {
      expect(() => parseVibePlan(const []), throwsA(isA<VibePlanException>()));
      expect(
        () => parseVibePlan([
          {'title': 'a', 'status': 'started'},
        ]),
        throwsA(isA<VibePlanException>()),
      );
      expect(
        () => parseVibePlan([
          {'title': 'a', 'status': 'doing'},
          {'title': 'b', 'status': 'doing'},
        ]),
        throwsA(isA<VibePlanException>()),
      );
    });

    test('rejects duplicate ids, blank titles and oversize lists', () {
      expect(
        () => parseVibePlan([
          {'id': 'x', 'title': 'a'},
          {'id': 'x', 'title': 'b'},
        ]),
        throwsA(isA<VibePlanException>()),
      );
      expect(
        () => parseVibePlan([
          {'title': '   '},
        ]),
        throwsA(isA<VibePlanException>()),
      );
      expect(
        () => parseVibePlan([
          for (var i = 0; i <= kVibeMaxPlanItems; i++) {'title': 'step $i'},
        ]),
        throwsA(isA<VibePlanException>()),
      );
    });
  });

  group('rules', () {
    test('merges the three rule files in priority order', () {
      writeFile('AGENTS.md', 'agent rule\n');
      writeFile('CLAUDE.md', 'claude rule\n');
      writeFile('.qfli/rules.md', 'qfli rule\n');
      final rules = loadVibeRules(root.path);
      expect(
        rules.indexOf('### AGENTS.md'),
        lessThan(rules.indexOf('### CLAUDE.md')),
      );
      expect(
        rules.indexOf('### CLAUDE.md'),
        lessThan(rules.indexOf('### .qfli/rules.md')),
      );
      expect(rules, contains('agent rule'));
      expect(rules, contains('qfli rule'));
    });

    test('caps the whole block across three files', () {
      writeFile('AGENTS.md', '${'a' * 40}\n' * 400);
      writeFile('CLAUDE.md', '${'b' * 40}\n' * 400);
      writeFile('.qfli/rules.md', '${'c' * 40}\n' * 400);
      final rules = loadVibeRules(root.path);
      expect(rules.length, lessThan(kVibeMaxRulesChars + 256));
      expect(rules, contains('已达上限'));
    });

    test('marks a single oversized rule file as truncated', () {
      writeFile('AGENTS.md', '${'a' * 40}\n' * 400);
      final rules = loadVibeRules(root.path);
      expect(rules.length, lessThan(kVibeMaxRuleFileChars + 200));
      expect(rules, contains('规则已截断'));
    });

    test('returns an empty string without rule files', () {
      expect(loadVibeRules(root.path), isEmpty);
    });
  });

  group('loop guard', () {
    test('refuses the third identical call and ignores key order', () {
      final guard = VibeLoopGuard();
      const a = '{"path":"a","content":"x"}';
      const b = '{"content":"x","path":"a"}';
      for (var i = 0; i < 3; i++) {
        expect(guard.rejectRepeat('write_file', a), isNull);
        guard.recordCall('write_file', a);
      }
      expect(guard.rejectRepeat('write_file', a), contains('重复'));
      expect(guard.rejectRepeat('write_file', b), contains('重复'));
      expect(guard.rejectRepeat('read_file', a), isNull);
    });

    test(
      'turns a policy rejection into progress, a bare failure into a stall',
      () {
        final guard = VibeLoopGuard();
        expect(
          guard.endRound(VibeRoundFacts()..errors.add('unread: 先 read_file')),
          isNull,
        );
        expect(
          guard.endRound(VibeRoundFacts()..errors.add('not_found: 文件不存在')),
          isNull,
        );
        expect(
          guard.endRound(VibeRoundFacts()..errors.add('not_found: 文件不存在')),
          contains('没有进展'),
        );
      },
    );

    test('an exit code counts as progress', () {
      final guard = VibeLoopGuard();
      final facts = VibeRoundFacts()..exitCodes.add(1);
      expect(guard.endRound(facts), isNull);
      expect(guard.endRound(VibeRoundFacts()..errors.add('error: x')), isNull);
      expect(
        guard.endRound(VibeRoundFacts()..errors.add('error: y')),
        contains('没有进展'),
      );
    });

    test('rejects at the start of each round, not while queuing', () {
      final guard = VibeLoopGuard()..markSnapshot({'old.py': 10});
      expect(guard.rejectUnreadWrite('new.py'), contains('先 read_file'));
      guard.markWritten('new.py');
      expect(guard.rejectUnreadWrite('new.py'), isNull);
      expect(guard.rejectUnreadWrite('old.py'), contains('先 read_file'));
      guard.markRead('old.py');
      expect(guard.rejectUnreadWrite('old.py'), isNull);
    });

    test('grows the round budget with task size but caps it', () {
      expect(vibeRoundBudget('修一个错'), kVibeBaseRounds);
      expect(vibeRoundBudget('做一个待办事项小网站'), kVibeBaseRounds + 12);
      expect(vibeRoundBudget('网站项目应用系统'), kVibeBaseRounds + 12);
      expect(
        vibeRoundBudget('做一个待办事项小网站'),
        lessThanOrEqualTo(kVibeMaxRoundBudget),
      );
    });
  });
}

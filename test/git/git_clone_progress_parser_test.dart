import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/git/git_clone_progress.dart';
import 'package:qfli_studio_core/git/git_clone_progress_parser.dart';

void main() {
  test('parses CR-delimited Git progress without exposing raw text', () {
    final events = <GitCloneProgress>[];
    final parser = GitCloneProgressParser(events.add);
    parser.add(
      'Receiving objects:  25% (1/4), 1.25 MiB | token=hidden\r'
              'Resolving deltas: 100% (4/4)\r'
          .codeUnits,
    );
    parser.close();

    expect(events, hasLength(2));
    expect(events[0].stage, GitCloneStage.receiving);
    expect(events[0].completed, 1);
    expect(events[0].total, 4);
    expect(events[0].receivedBytes, 1310720);
    expect(events[0].fraction, 0.25);
    expect(events[1].stage, GitCloneStage.resolving);
    expect(events[1].fraction, 1);
    expect(events.toString(), isNot(contains('hidden')));
  });

  test('flushes the latest same-stage progress when closed', () {
    final events = <GitCloneProgress>[];
    final parser = GitCloneProgressParser(
      events.add,
      throttleInterval: const Duration(seconds: 5),
    );
    parser.add('Receiving objects: 10% (1/10)\r'.codeUnits);
    parser.add('Receiving objects: 20% (2/10)\r'.codeUnits);
    parser.add('Receiving objects: 30% (3/10)\r'.codeUnits);

    expect(events, hasLength(1));
    expect(events.single.completed, 1);
    parser.close();

    expect(events, hasLength(2));
    expect(events.last.completed, 3);
    expect(events.last.total, 10);
  });

  test('falls back to percentages and clamps reported counts', () {
    final events = <GitCloneProgress>[];
    final parser = GitCloneProgressParser(events.add);
    parser.add('Updating files: 120% (120/100)\n'.codeUnits);

    expect(events.single.stage, GitCloneStage.checkout);
    expect(events.single.fraction, 1);
  });

  test('ignores unrelated stderr and bounds a partial line', () {
    final events = <GitCloneProgress>[];
    final parser = GitCloneProgressParser(events.add);
    parser.add(('x' * 5000).codeUnits);
    parser.close();

    expect(events, isEmpty);
  });
}

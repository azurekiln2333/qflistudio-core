import 'dart:io';

import 'package:path/path.dart' as p;

import 'java_topics.dart';

/// Emits the 100-topic outline (markdown) from the authored source of truth so
/// the outline and the shipped records cannot drift.
///
///   dart run tool/java_content/outline.dart
Future<void> main() async {
  final buffer = StringBuffer()
    ..writeln('# Java 100-topic outline')
    ..writeln()
    ..writeln(
      'Generated from `tool/java_content/java_topics.dart` by '
      '`tool/java_content/outline.dart`. Each topic has a paired example id '
      '(`java-example-NNN`) and tutorial id (`java-tutorial-NNN`).',
    )
    ..writeln();

  var index = 0;
  for (final topic in javaTopics) {
    index++;
    buffer
      ..writeln(
        '${index.toString().padLeft(3, '0')}. **${topic.title}** '
        '(${topic.level}) — ${topic.summary}',
      )
      ..writeln('    - concepts: ${topic.concepts.join('、')}')
      ..writeln('    - example: `${topic.exampleId}`');
  }

  final out = File(
    p.join(
      Directory.current.path,
      '..',
      'qfli_java',
      '.trellis',
      'tasks',
      '10-09-java-tutorial-rewrite',
      'research',
      'java-topic-outline.md',
    ),
  );
  await out.writeAsString(buffer.toString(), flush: true);
  stdout.writeln('Wrote ${javaTopics.length} topics to ${out.path}');
}

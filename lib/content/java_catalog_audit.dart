/// Exhaustive inventory of Java code actually shipped in the content assets.
/// Pure Dart so the host verifier and the real in-app runner share the contract.
library;

import 'dart:convert';

import '../tools/offline_tools.dart';

String javaCatalogBytesSha256(List<int> bytes) => OfflineDigest.sha256Bytes(
  bytes,
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

/// The curriculum's output convention ignores CRLF and one final line ending.
/// Spaces, tabs and extra blank lines remain significant.
String normalizeJavaCatalogOutput(String value) {
  final normalized = value.replaceAll('\r\n', '\n');
  return normalized.endsWith('\n')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

class JavaAuditTopic {
  const JavaAuditTopic({
    required this.id,
    required this.code,
    required this.output,
    this.input,
    this.objective,
    this.prerequisites,
    this.pitfalls,
  });

  final int id;
  final String code;
  final String output;
  final String? input;
  final String? objective;
  final List<String>? prerequisites;
  final List<String>? pitfalls;

  String get tutorialId => 'java-tutorial-${id.toString().padLeft(3, '0')}';
  String get exampleId => 'java-example-${id.toString().padLeft(3, '0')}';
}

class JavaCatalogSnippet {
  JavaCatalogSnippet({
    required this.location,
    required this.topicId,
    required this.code,
    required this.expectedOutput,
    required Map<String, String> fixtures,
  }) : fixtures = Map.unmodifiable(fixtures);

  final String location;
  final String topicId;
  final String code;
  final String expectedOutput;
  final Map<String, String> fixtures;

  late final String sourceSha256 = OfflineDigest.sha256(code);

  /// Identity includes exact source, expectation and all input fixtures.
  /// Only genuinely identical runnable payloads may share an execution.
  late final String payloadSha256 = OfflineDigest.sha256(
    jsonEncode([
      code,
      expectedOutput,
      {for (final key in fixtures.keys.toList()..sort()) key: fixtures[key]},
    ]),
  );

  Map<String, Object?> toJson() => {
    'location': location,
    'topicId': topicId,
    'sourceSha256': sourceSha256,
    'payloadSha256': payloadSha256,
    'sourceBytes': utf8.encode(code).length,
    'expectedOutput': expectedOutput,
    'inputFixtures': fixtures,
  };
}

class JavaCatalogInventory {
  JavaCatalogInventory._(this.snippets, this.issues, this.counts);

  /// Parses every tutorial lesson, aggregate example, legacy lesson and legacy
  /// example. Duplicate/extra rows are retained, reported and never overwritten.
  /// [expectedTopicCount] is the independently declared curriculum size.
  factory JavaCatalogInventory.fromSources({
    required String tutorialsSource,
    required String examplesSource,
    required String legacySource,
    required int expectedTopicCount,
    List<JavaAuditTopic>? authoredTopics,
  }) {
    final builder = _InventoryBuilder(expectedTopicCount, authoredTopics);
    builder.read(tutorialsSource, examplesSource, legacySource);
    return JavaCatalogInventory._(
      List.unmodifiable(builder.snippets),
      List.unmodifiable(builder.issues),
      Map.unmodifiable(builder.counts),
    );
  }

  final List<JavaCatalogSnippet> snippets;
  final List<String> issues;
  final Map<String, int> counts;
  bool get ok => issues.isEmpty;

  Map<String, List<JavaCatalogSnippet>> get executionGroups {
    final groups = <String, List<JavaCatalogSnippet>>{};
    for (final snippet in snippets) {
      groups.putIfAbsent(snippet.payloadSha256, () => []).add(snippet);
    }
    return groups;
  }

  Map<String, Object?> toJson() => {
    'ok': ok,
    'counts': counts,
    'snippetCount': snippets.length,
    'distinctPayloads': executionGroups.length,
    'issues': issues,
    'snippets': snippets.map((snippet) => snippet.toJson()).toList(),
  };
}

class _InventoryBuilder {
  _InventoryBuilder(this.expectedTopicCount, this.authoredTopics);

  final int expectedTopicCount;
  final List<JavaAuditTopic>? authoredTopics;
  final snippets = <JavaCatalogSnippet>[];
  final issues = <String>[];
  final counts = <String, int>{};
  final surfaces = <String, Map<String, List<JavaCatalogSnippet>>>{};

  void read(String tutorials, String examples, String legacy) {
    if (expectedTopicCount < 1) {
      issues.add('expectedTopicCount must be positive');
    }
    _aggregate(_document(tutorials, 'tutorials'), tutorial: true);
    _aggregate(_document(examples, 'examples'), tutorial: false);
    final old = _document(legacy, 'legacy');
    if (old['language'] != 'java' || old['type'] != 'java') {
      issues.add('legacy: language/type must both be java');
    }
    final chapterIds = <String>{};
    var lessonCount = 0;
    for (final (index, value) in _list(
      old['chapters'],
      'legacy.chapters',
    ).indexed) {
      final chapter = _map(value, 'legacy.chapters[$index]');
      final chapterId = _string(chapter['id'], 'legacy.chapters[$index].id');
      if (!chapterIds.add(chapterId)) {
        issues.add('duplicate legacy chapter id: $chapterId');
      }
      for (final (lessonIndex, item) in _list(
        chapter['lessons'],
        'legacy.chapters[$index].lessons',
      ).indexed) {
        final location = 'legacy.chapters[$index].lessons[$lessonIndex]';
        final lesson = _map(item, location);
        final id = _string(lesson['id'], '$location.id');
        _snippet('legacyLessons', id, location, lesson, 'output');
        lessonCount++;
      }
    }
    counts['legacyLessons'] = lessonCount;
    final oldExamples = _list(old['examples'], 'legacy.examples');
    for (final (index, value) in oldExamples.indexed) {
      final location = 'legacy.examples[$index]';
      final example = _map(value, location);
      final id = _string(example['id'], '$location.id');
      _snippet('legacyExamples', id, location, example, 'output');
      _sourceLesson(example, id, location);
    }
    counts['legacyExamples'] = oldExamples.length;
    _verifyInventory();
    _verifyParity();
  }

  void _aggregate(Map<String, Object?> document, {required bool tutorial}) {
    final name = tutorial ? 'tutorials' : 'examples';
    var count = 0;
    final ids = <String>{};
    final lessonIds = <String>{};
    for (final (index, value) in _list(
      document['entries'],
      '$name.entries',
    ).indexed) {
      final location = '$name.entries[$index]';
      final entry = _map(value, location);
      final rawId = entry['id'];
      // Include damaged Java rows as well: changing language must not hide code.
      if (entry['language'] != 'java' &&
          entry['type'] != 'java' &&
          !(rawId is String && rawId.startsWith('java-'))) {
        continue;
      }
      final id = _string(rawId, '$location.id');
      if (!ids.add(id)) issues.add('duplicate $name id: $id');
      if (entry['language'] != 'java' || entry['type'] != 'java') {
        issues.add('$location/$id: language/type must both be java');
      }
      count++;
      if (!tutorial) {
        _snippet(name, id, location, entry, 'expectedOutput');
        _sourceLesson(entry, id, location);
        continue;
      }
      final lessons = _list(entry['lessons'], '$location.lessons');
      if (lessons.length != 1) {
        issues.add(
          '$location/$id: expected exactly one lesson, got ${lessons.length}',
        );
      }
      for (final (lessonIndex, item) in lessons.indexed) {
        final lessonLocation = '$location.lessons[$lessonIndex]';
        final lesson = _map(item, lessonLocation);
        final lessonId = _string(lesson['id'], '$lessonLocation.id');
        if (!lessonIds.add(lessonId)) {
          issues.add('duplicate tutorial lesson id: $lessonId');
        }
        if (lessonId != '$id-lesson') {
          issues.add('$lessonLocation: unexpected lesson id $lessonId for $id');
        }
        _snippet(name, id, lessonLocation, lesson, 'output');
        final topic = authoredTopics
            ?.where((topic) => topic.tutorialId == id)
            .firstOrNull;
        if (topic == null) continue;
        for (final (key, expected) in [
          ('objective', topic.objective),
          ('prerequisites', topic.prerequisites),
          ('pitfalls', topic.pitfalls),
        ]) {
          if (expected != null &&
              jsonEncode(lesson[key]) != jsonEncode(expected)) {
            issues.add('$lessonLocation/$id: authored $key mismatch');
          }
        }
      }
    }
    counts[name] = count;
    // Empty lessons still retain their parent ID for missing-record detection.
    final expected = _expectedIds(tutorial);
    for (final id in expected.difference(ids)) {
      issues.add('missing $name id: $id');
    }
    for (final id in ids.difference(expected)) {
      issues.add('extra $name id: $id');
    }
  }

  void _sourceLesson(Map<String, Object?> entry, String id, String location) {
    final expected = id.replaceFirst('java-example-', 'java-tutorial-');
    if (entry['sourceLessonId'] != expected) {
      issues.add('$location/$id: sourceLessonId must be $expected');
    }
  }

  void _snippet(
    String surface,
    String id,
    String location,
    Map<String, Object?> value,
    String outputKey,
  ) {
    final code = _string(value['code'], '$location.code');
    if (code.trim().isEmpty) issues.add('$location/$id: empty runnable code');
    final output = _string(value[outputKey], '$location.$outputKey');
    final fixtures = <String, String>{};
    if (value['inputFixtures'] != null) {
      final rawFixtures = _map(
        value['inputFixtures'],
        '$location.inputFixtures',
      );
      for (final entry in rawFixtures.entries) {
        if (entry.key != 'stdin') {
          issues.add('$location/$id: unsupported input fixture ${entry.key}');
        }
        fixtures[entry.key] = _string(
          entry.value,
          '$location.inputFixtures.${entry.key}',
        );
      }
    }
    final snippet = JavaCatalogSnippet(
      location: '$location/$id',
      topicId: id.replaceFirst('java-example-', 'java-tutorial-'),
      code: code,
      expectedOutput: output,
      fixtures: fixtures,
    );
    snippets.add(snippet);
    surfaces
        .putIfAbsent(surface, () => {})
        .putIfAbsent(id, () => [])
        .add(snippet);
  }

  Set<String> _expectedIds(bool tutorial) => {
    for (var id = 1; id <= expectedTopicCount; id++)
      'java-${tutorial ? 'tutorial' : 'example'}-${id.toString().padLeft(3, '0')}',
  };

  void _verifyInventory() {
    for (final surface in [
      'tutorials',
      'examples',
      'legacyLessons',
      'legacyExamples',
    ]) {
      final entries = surfaces[surface] ?? {};
      final expected = _expectedIds(
        surface == 'tutorials' || surface == 'legacyLessons',
      );
      for (final id in expected.difference(entries.keys.toSet())) {
        issues.add('missing runnable $surface id: $id');
      }
      for (final id in entries.keys.toSet().difference(expected)) {
        issues.add('extra runnable $surface id: $id');
      }
      for (final entry in entries.entries) {
        if (entry.value.length != 1) {
          issues.add(
            'duplicate runnable $surface id: ${entry.key} (${entry.value.length})',
          );
        }
      }
    }
    if (authoredTopics case final List<JavaAuditTopic> topics) {
      final ids = <int>{};
      for (final topic in topics) {
        if (!ids.add(topic.id)) {
          issues.add('duplicate authored id: ${topic.id}');
        }
      }
      final expected = {for (var i = 1; i <= expectedTopicCount; i++) i};
      if (ids.length != expected.length || !ids.containsAll(expected)) {
        issues.add('authored IDs must be exactly 1..$expectedTopicCount');
      }
    }
  }

  void _verifyParity() {
    final groups = <String, List<JavaCatalogSnippet>>{};
    for (final snippet in snippets) {
      groups.putIfAbsent(snippet.topicId, () => []).add(snippet);
    }
    for (final entry in groups.entries) {
      final reference = entry.value.first;
      for (final snippet in entry.value.skip(1)) {
        if (snippet.payloadSha256 != reference.payloadSha256) {
          issues.add(
            '${snippet.location}: code/output/inputFixtures mirror mismatch with ${reference.location}',
          );
        }
      }
      final authored = authoredTopics
          ?.where((topic) => topic.tutorialId == entry.key)
          .firstOrNull;
      if (authored == null) continue;
      for (final snippet in entry.value) {
        if (snippet.code != authored.code ||
            snippet.expectedOutput != authored.output ||
            jsonEncode(snippet.fixtures) !=
                jsonEncode(
                  authored.input == null
                      ? <String, String>{}
                      : {'stdin': authored.input!},
                )) {
          issues.add(
            '${snippet.location}: authored code/output/inputFixtures mismatch',
          );
        }
      }
    }
  }

  Map<String, Object?> _document(String source, String location) {
    try {
      return _map(jsonDecode(source), location);
    } on FormatException catch (error) {
      issues.add('$location: ${error.message}');
      return {};
    }
  }

  Map<String, Object?> _map(Object? value, String location) {
    if (value is Map<String, Object?>) return value;
    issues.add('$location: expected object');
    return {};
  }

  List<Object?> _list(Object? value, String location) {
    if (value is List<Object?>) return value;
    issues.add('$location: expected array');
    return [];
  }

  String _string(Object? value, String location) {
    if (value is String) return value;
    issues.add('$location: expected string');
    return '';
  }
}

@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/ai_file_header.dart';

/// AI 生成文件的标识行（§3-W3、§4 第 9 条）。
///
/// The rule has to survive real file shapes: a script with a shebang must stay
/// executable, a JSON file must stay parseable. Both are asserted below with the
/// actual parser that would break.
void main() {
  group('line-comment languages', () {
    test('python gets a # note on the first line', () {
      final result = addAiGeneratedHeader(
        'src/main.py',
        'print("hi")\nprint("there")\n',
      );
      expect(result.inserted, isTrue);
      expect(result.content, startsWith('# $kAiGeneratedFileNote\n'));
      expect(result.content, contains('print("hi")'));
    });

    test('dart, java, go and C all use //', () {
      for (final path in ['a.dart', 'a.java', 'a.go', 'a.c', 'a.cpp']) {
        final result = addAiGeneratedHeader(path, 'int main() {}\n');
        expect(
          result.content.startsWith('// $kAiGeneratedFileNote'),
          isTrue,
          reason: path,
        );
      }
    });

    test('sql and lua use --', () {
      for (final path in ['q.sql', 'a.lua']) {
        expect(
          addAiGeneratedHeader(path, 'SELECT 1;\n').content,
          startsWith('-- $kAiGeneratedFileNote'),
          reason: path,
        );
      }
    });

    test('block-comment languages close the note on the same line', () {
      final css = addAiGeneratedHeader('style.css', 'body {}\n');
      expect(css.content, startsWith('/* $kAiGeneratedFileNote */'));
      final html = addAiGeneratedHeader('index.html', '<!DOCTYPE html>\n');
      expect(html.content, startsWith('<!-- $kAiGeneratedFileNote -->'));
    });
  });

  group('content that must stay first', () {
    test('a shebang keeps position 0 so the script still runs', () {
      final result = addAiGeneratedHeader('run.sh', '#!/bin/sh\necho hi\n');
      expect(result.content.split('\n').first, '#!/bin/sh');
      expect(result.content.split('\n')[1], '# $kAiGeneratedFileNote');
      // The note is a # line, which sh already ignores.
      expect(result.content.contains('\necho hi'), isTrue);
    });

    test('python encoding declarations stay within the first two lines', () {
      final result = addAiGeneratedHeader(
        'legacy.py',
        '#!/usr/bin/env python\n# -*- coding: utf-8 -*-\nprint(1)\n',
      );
      final lines = result.content.split('\n');
      expect(lines[0], '#!/usr/bin/env python');
      expect(lines[1], '# -*- coding: utf-8 -*-');
      expect(lines[2], contains(kAiGeneratedFileNote));
    });

    test('an XML declaration stays the first line of an SVG', () {
      final result = addAiGeneratedHeader(
        'logo.svg',
        '<?xml version="1.0"?>\n<svg/>\n',
      );
      expect(result.content.split('\n').first, '<?xml version="1.0"?>');
      expect(result.content, contains(kAiGeneratedFileNote));
    });

    test('CRLF files keep their line endings', () {
      final result = addAiGeneratedHeader('win.cs', 'class A {}\r\n');
      expect(result.content, startsWith('// $kAiGeneratedFileNote\r\n'));
      expect(
        result.content.contains('\n') && !result.content.contains('\r\n'),
        isFalse,
      );
    });

    test('an empty file becomes just the note', () {
      final result = addAiGeneratedHeader('empty.py', '');
      expect(result.content.trim(), '# $kAiGeneratedFileNote');
    });
  });

  group('languages without comment syntax', () {
    test('JSON keeps its bytes and gets a sidecar note', () {
      const original = '{"a": 1}';
      final result = addAiGeneratedHeader('data.json', original);
      expect(result.inserted, isTrue);
      // The promise that matters: the file still parses.
      expect(result.content, original);
      expect(result.inBody, isFalse);
      expect(result.sidecarContent, contains(kAiGeneratedFileNote));
      expect(result.sidecarContent, contains('data.json'));
      expect(jsonDecode(result.content), {'a': 1});
    });

    test('the sidecar path is the file name plus the suffix', () {
      expect(aiGeneratedSidecarPath('data.json'), 'data.json.ai-generated');
      expect(
        aiGeneratedSidecarPath('src\\data\\rows.csv'),
        'src/data/rows.csv.ai-generated',
      );
    });

    test('csv, txt and unknown extensions also get a sidecar', () {
      for (final path in ['a.csv', 'a.txt', 'NOTICE']) {
        final result = addAiGeneratedHeader(path, 'x,y\n');
        expect(result.inserted, isTrue, reason: path);
        expect(result.content, 'x,y\n', reason: path);
        expect(result.inBody, isFalse, reason: path);
        expect(result.sidecarContent, isNotNull, reason: path);
      }
    });

    test('a file that already carries the note needs no sidecar', () {
      final original = '{"note": "$kAiGeneratedFileNote"}';
      final result = addAiGeneratedHeader('data.json', original);
      expect(result.content, original);
      expect(result.sidecarContent, isNull);
    });

    test('applyAiGeneratedMark writes the sidecar only when needed', () async {
      final written = <String, String>{};
      Future<void> write(String target, String body) async {
        written[target] = body;
      }

      final marked = addAiGeneratedHeader('data.json', '{}');
      await applyAiGeneratedMark('data.json', marked, write: write);
      expect(written.keys, ['data.json.ai-generated']);

      final body = addAiGeneratedHeader('a.py', 'print(1)\n');
      await applyAiGeneratedMark('a.py', body, write: write);
      expect(written.keys, ['data.json.ai-generated']);
    });
  });

  group('idempotence', () {
    test('a second pass does not add a second note', () {
      final first = addAiGeneratedHeader('a.py', 'print(1)\n');
      final second = addAiGeneratedHeader('a.py', first.content);
      expect(second.inserted, isTrue);
      expect(kAiGeneratedFileNote.allMatches(second.content).length, 1);
    });
  });

  group('syntax lookup', () {
    test('file names beat extensions for Dockerfile and CMakeLists.txt', () {
      expect(aiCommentSyntaxFor('Dockerfile')?.prefix, '#');
      expect(aiCommentSyntaxFor('deploy/CMakeLists.txt')?.prefix, '#');
    });

    test('extensions are matched case-insensitively', () {
      expect(aiCommentSyntaxFor('Main.JAVA')?.prefix, '//');
      expect(aiCommentSyntaxFor('INDEX.HTML')?.isBlock, isTrue);
    });

    test('a dot only in a directory name is not an extension', () {
      expect(aiCommentSyntaxFor('v1.2/Makefile')?.prefix, '#');
      expect(aiCommentSyntaxFor('v1.2/NOTICE'), isNull);
    });
  });
}

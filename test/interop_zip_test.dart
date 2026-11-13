import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_zip.dart';

void main() {
  test('the zip restores the payload files with their relative paths', () async {
    final temp = await Directory.systemTemp.createTemp('qfli_zip_test');
    addTearDown(() => temp.deleteSync(recursive: true));

    final zipPath = await writePayloadZip(
      cacheDirectory: temp.path,
      sessionId: 'ziproundtrip01',
      files: <InteropPayloadFile>[
        InteropPayloadFile(
          path: 'com/demo/Main.java',
          content: utf8.encode('package demo;\nclass Main {}'),
        ),
        InteropPayloadFile(path: 'util/Helper.java', content: utf8.encode('class Helper {}')),
      ],
    );

    expect(zipPath, endsWith('qfli_interop${Platform.pathSeparator}out'
        '${Platform.pathSeparator}ziproundtrip01.zip'));
    final decoded = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    final main = decoded.findFile('com/demo/Main.java');
    expect(main, isNotNull, reason: 'nested package paths must survive');
    expect(utf8.decode(main!.content as List<int>), contains('package demo;'));
  });

  test('a new run removes leftovers from earlier sessions', () async {
    final temp = await Directory.systemTemp.createTemp('qfli_zip_test');
    addTearDown(() => temp.deleteSync(recursive: true));
    final stale = File(
      '${temp.path}${Platform.pathSeparator}qfli_interop'
      '${Platform.pathSeparator}out${Platform.pathSeparator}stale.zip',
    );
    stale.createSync(recursive: true);
    stale.writeAsBytesSync(<int>[1, 2, 3]);

    await writePayloadZip(
      cacheDirectory: temp.path,
      sessionId: 'ziproundtrip02',
      files: <InteropPayloadFile>[
        InteropPayloadFile(path: 'Main.java', content: utf8.encode('class Main {}')),
      ],
    );

    expect(stale.existsSync(), isFalse, reason: 'stale payloads must not accumulate');
  });
}

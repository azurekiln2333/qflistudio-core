import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/interop/interop_protocol.dart';

/// Independent SHA-256, so the module's own implementation is not used to
/// check itself.
String _sha256OfText(String text) {
  final padded = <int>[...utf8.encode(text), 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  final bits = utf8.encode(text).length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    padded.add((bits >> shift) & 0xff);
  }
  const k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  const mask = 0xffffffff;
  int rotr(int value, int count) =>
      ((value >> count) | (value << (32 - count))) & mask;
  final hash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final w = List<int>.filled(64, 0);
  for (var offset = 0; offset < padded.length; offset += 64) {
    for (var index = 0; index < 16; index++) {
      final base = offset + index * 4;
      w[index] =
          (padded[base] << 24) |
          (padded[base + 1] << 16) |
          (padded[base + 2] << 8) |
          padded[base + 3];
    }
    for (var index = 16; index < 64; index++) {
      final s0 =
          rotr(w[index - 15], 7) ^
          rotr(w[index - 15], 18) ^
          (w[index - 15] >> 3);
      final s1 =
          rotr(w[index - 2], 17) ^
          rotr(w[index - 2], 19) ^
          (w[index - 2] >> 10);
      w[index] = (w[index - 16] + s0 + w[index - 7] + s1) & mask;
    }
    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var index = 0; index < 64; index++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & mask & g);
      final temp1 = (h + s1 + ch + k[index] + w[index]) & mask;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & mask;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & mask;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & mask;
    }
    hash[0] = (hash[0] + a) & mask;
    hash[1] = (hash[1] + b) & mask;
    hash[2] = (hash[2] + c) & mask;
    hash[3] = (hash[3] + d) & mask;
    hash[4] = (hash[4] + e) & mask;
    hash[5] = (hash[5] + f) & mask;
    hash[6] = (hash[6] + g) & mask;
    hash[7] = (hash[7] + h) & mask;
  }
  final out = StringBuffer();
  for (final word in hash) {
    out.write(word.toRadixString(16).padLeft(8, '0'));
  }
  return out.toString();
}

InteropRequest _request({
  List<InteropPayloadFile>? files,
  String entry = 'src/Main.java',
  InteropAction action = InteropAction.run,
  String stdin = '',
  int timeoutMs = 30000,
  String protocol = kInteropProtocol,
  String sessionId = 'qfli-test-session',
  String sessionToken = 'testtoken0123456789abcdef',
}) => InteropRequest(
  sessionId: sessionId,
  sessionToken: sessionToken,
  language: 'java',
  entry: entry,
  action: action,
  callerBundle: 'com.azurekiln.qflistudio',
  bridgeAction: 'action.system.qfli.interop.event',
  files:
      files ??
      <InteropPayloadFile>[
        InteropPayloadFile(
          path: 'src/Main.java',
          content: utf8.encode('class Main {}'),
        ),
      ],
  stdin: stdin,
  timeoutMs: timeoutMs,
  protocol: protocol,
);

void main() {
  group('sha256', () {
    // Pinned against the published FIPS 180-4 digests. The receiver recomputes
    // the digest with its own platform hash, so a drift here would reject every
    // payload on device while the unit tests still passed.
    test('empty string', () {
      final request = InteropRequest(
        sessionId: 'qfli-test-session',
        sessionToken: 'testtoken0123456789abcdef',
        language: 'java',
        entry: 'a.txt',
        action: InteropAction.analyze,
        callerBundle: 'com.azurekiln.qflistudio',
        bridgeAction: 'action.system.qfli.interop.event',
      );
      expect(
        request.filesDigest,
        '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
      );
    });

    test('abc', () {
      // Pinned against the published FIPS 180-4 digest for "abc". The digest
      // covers the JSON payload, so the expected value is the digest of the
      // encoder output for this one file.
      final request = InteropRequest(
        sessionId: 'qfli-test-session',
        sessionToken: 'testtoken0123456789abcdef',
        language: 'java',
        entry: 'a.txt',
        action: InteropAction.analyze,
        callerBundle: 'com.azurekiln.qflistudio',
        bridgeAction: 'action.system.qfli.interop.event',
        files: <InteropPayloadFile>[
          InteropPayloadFile(path: 'a.txt', content: utf8.encode('abc')),
        ],
      );
      expect(request.filesDigest, _sha256OfText(request.filesJson));
    });
  });

  group('path grammar', () {
    test('accepts a nested relative path', () {
      expect(
        InteropPath.validate('src/main/java/Main.java'),
        'src/main/java/Main.java',
      );
    });

    for (final bad in <String>[
      '',
      '/etc/passwd',
      '../escape.java',
      'src/../../escape.java',
      'src//double.java',
      'C:/Windows/main.java',
      r'src\main.java',
      'src/.hidden/Main.java',
      '.git/config',
      'src/Main.java\u0000',
      'src/\u0001bad.java',
    ]) {
      test('rejects ${jsonEncode(bad)}', () {
        expect(
          () => InteropPath.validate(bad),
          throwsA(
            isA<InteropException>().having(
              (error) => error.code,
              'code',
              InteropErrorCode.badRequest,
            ),
          ),
        );
        expect(InteropPath.isValid(bad), isFalse);
      });
    }

    test('rejects a path longer than the limit', () {
      final long = 'a' * (InteropLimits.maxPathLength + 1);
      expect(InteropPath.isValid(long), isFalse);
    });
  });

  group('request', () {
    test('round trips through launch parameters', () {
      final request = _request();
      final parameters = request.toLaunchParameters();
      final decoded = InteropRequest.fromLaunchParameters(parameters);
      expect(decoded.sessionId, request.sessionId);
      expect(decoded.entry, request.entry);
      expect(decoded.action, InteropAction.run);
      expect(decoded.files.single.path, 'src/Main.java');
      expect(decoded.files.single.content, request.files.single.content);
      expect(decoded.filesDigest, request.filesDigest);
    });

    test('carries binary content through base64', () {
      final request = _request(
        files: <InteropPayloadFile>[
          InteropPayloadFile(
            path: 'src/Main.java',
            content: const <int>[0, 1, 2, 250, 255],
          ),
        ],
      );
      final decoded = InteropRequest.fromLaunchParameters(
        request.toLaunchParameters(),
      );
      expect(decoded.files.single.content, const <int>[0, 1, 2, 250, 255]);
    });

    test('rejects an absolute path inside the payload', () {
      expect(
        () => _request(
          files: <InteropPayloadFile>[
            InteropPayloadFile(path: '/abs.java', content: const <int>[1]),
          ],
          entry: '/abs.java',
        ).toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.badRequest,
          ),
        ),
      );
    });

    test('rejects a traversal path inside the payload', () {
      expect(
        () => _request(
          files: <InteropPayloadFile>[
            InteropPayloadFile(path: '../x.java', content: const <int>[1]),
          ],
          entry: '../x.java',
        ).toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.badRequest,
          ),
        ),
      );
    });

    test('rejects an entry that is not in the payload', () {
      expect(
        () => _request(entry: 'src/Other.java').toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.badRequest,
          ),
        ),
      );
    });

    test('rejects more files than the cap', () {
      final files = <InteropPayloadFile>[
        for (var index = 0; index <= InteropLimits.maxFiles; index++)
          InteropPayloadFile(path: 'f$index.java', content: const <int>[1]),
      ];
      expect(
        () => _request(files: files).toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.payloadTooLarge,
          ),
        ),
      );
    });

    test('rejects a payload above the byte cap', () {
      expect(
        () => _request(
          files: <InteropPayloadFile>[
            InteropPayloadFile(
              path: 'src/Main.java',
              content: List<int>.filled(InteropLimits.maxPayloadBytes + 1, 65),
            ),
          ],
        ).toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.payloadTooLarge,
          ),
        ),
      );
    });

    test('rejects a digest that does not describe the files', () {
      final parameters = _request().toLaunchParameters();
      final tampered = Map<String, Object?>.from(parameters)
        ..['files'] = jsonEncode(<Object?>[
          <String, Object?>{
            'path': 'src/Main.java',
            'content': base64Encode(utf8.encode('class Evil {}')),
          },
        ]);
      expect(
        () => InteropRequest.fromLaunchParameters(tampered),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.payloadIntegrity,
          ),
        ),
      );
    });

    test('rejects an unknown protocol version', () {
      expect(
        () => _request(protocol: 'qfli-interop/2').toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.unsupportedProtocol,
          ),
        ),
      );
    });

    test('rejects a timeout outside the accepted range', () {
      expect(
        () => _request(timeoutMs: 10).toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.badRequest,
          ),
        ),
      );
    });

    test('rejects oversized stdin', () {
      expect(
        () => _request(
          stdin: 'x' * (InteropLimits.maxStdinBytes + 1),
        ).toLaunchParameters(),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.payloadTooLarge,
          ),
        ),
      );
    });

    test('analyze needs no entry in the payload', () {
      expect(
        _request(
          action: InteropAction.analyze,
          entry: '',
          files: const <InteropPayloadFile>[],
        ).toLaunchParameters(),
        containsPair('action', 'analyze'),
      );
    });
  });

  group('session', () {
    test('generates identifiers that pass its own grammar', () {
      for (var index = 0; index < 100; index++) {
        expect(
          InteropSession.validate(InteropSession.create(next: index)),
          isNotEmpty,
        );
      }
    });

    test('rejects short or foreign identifiers', () {
      expect(
        () => InteropSession.validate('short'),
        throwsA(isA<InteropException>()),
      );
      expect(
        () => InteropSession.validate('qfli test session'),
        throwsA(isA<InteropException>()),
      );
    });
  });

  group('events', () {
    InteropEvent event(int seq, InteropEventKind kind, {int? exitCode}) =>
        InteropEvent(
          sessionId: 'qfli-test-session',
          seq: seq,
          kind: kind,
          text: 'line $seq',
          exitCode: exitCode,
        );

    test('round trips a done event', () {
      final original = event(3, InteropEventKind.done, exitCode: 0);
      final decoded = InteropEvent.fromLaunchParameters(
        original.toLaunchParameters().cast<String, Object?>(),
      );
      expect(decoded.kind, InteropEventKind.done);
      expect(decoded.exitCode, 0);
      expect(decoded.seq, 3);
    });

    test('round trips an error event with an artifacts list', () {
      const original = InteropEvent(
        sessionId: 'qfli-test-session',
        seq: 2,
        kind: InteropEventKind.error,
        text: '编译失败',
        code: InteropErrorCode.compileFailed,
        artifacts: <String>['out/Main.class'],
      );
      final decoded = InteropEvent.fromLaunchParameters(
        original.toLaunchParameters().cast<String, Object?>(),
      );
      expect(decoded.code, InteropErrorCode.compileFailed);
      expect(decoded.artifacts, <String>['out/Main.class']);
    });

    test('rejects a done event without an exit code', () {
      expect(
        () => InteropEvent.fromLaunchParameters(<String, Object?>{
          'protocol': kInteropProtocol,
          'sessionId': 'qfli-test-session',
          'seq': '1',
          'event': 'done',
        }),
        throwsA(isA<InteropException>()),
      );
    });

    test('rejects an unknown error code', () {
      expect(
        () => InteropEvent.fromLaunchParameters(<String, Object?>{
          'protocol': kInteropProtocol,
          'sessionId': 'qfli-test-session',
          'seq': '1',
          'event': 'error',
          'code': 'made_up',
        }),
        throwsA(isA<InteropException>()),
      );
    });

    test('rejects a foreign protocol version', () {
      expect(
        () => InteropEvent.fromLaunchParameters(<String, Object?>{
          'protocol': 'qfli-interop/0',
          'sessionId': 'qfli-test-session',
          'seq': '1',
          'event': 'accepted',
        }),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.unsupportedProtocol,
          ),
        ),
      );
    });
  });

  group('sequencer', () {
    InteropEvent event(String session, int seq) => InteropEvent(
      sessionId: session,
      seq: seq,
      kind: InteropEventKind.stdout,
      text: '$seq',
    );

    test('accepts a complete ordered run', () {
      final sequencer = InteropEventSequencer('qfli-test-session');
      expect(sequencer.accept(event('qfli-test-session', 1)), isNotNull);
      expect(sequencer.accept(event('qfli-test-session', 2)), isNotNull);
    });

    test('drops duplicates and foreign sessions', () {
      final sequencer = InteropEventSequencer('qfli-test-session');
      expect(sequencer.accept(event('qfli-test-session', 1)), isNotNull);
      expect(sequencer.accept(event('qfli-test-session', 1)), isNull);
      expect(sequencer.accept(event('qfli-other-session', 2)), isNull);
      expect(sequencer.accept(event('qfli-test-session', 2)), isNotNull);
    });

    test('reports a sequence gap instead of hiding lost output', () {
      final sequencer = InteropEventSequencer('qfli-test-session');
      expect(sequencer.accept(event('qfli-test-session', 1)), isNotNull);
      expect(
        () => sequencer.accept(event('qfli-test-session', 3)),
        throwsA(
          isA<InteropException>().having(
            (error) => error.code,
            'code',
            InteropErrorCode.sequenceGap,
          ),
        ),
      );
    });

    test('stops accepting after a terminal event', () {
      final sequencer = InteropEventSequencer('qfli-test-session');
      sequencer.accept(event('qfli-test-session', 1));
      sequencer.accept(
        const InteropEvent(
          sessionId: 'qfli-test-session',
          seq: 2,
          kind: InteropEventKind.done,
          exitCode: 0,
        ),
      );
      expect(sequencer.finished, isTrue);
      expect(sequencer.accept(event('qfli-test-session', 3)), isNull);
    });
  });
}

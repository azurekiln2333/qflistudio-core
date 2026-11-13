/// Wire contract for `qfli-interop/1`, the channel the Studio app uses to ask
/// a sibling language app to compile and run a project.
///
/// The payload travels as text inside a `Want`, not through a shared folder.
/// OHOS gives no cross-bundle writable directory, so this codec is the only
/// place that decides what may cross the boundary. Every rule here has a
/// matching check in the receiver (`InteropReceiver.ets`); both must change
/// together.
///
/// See `.trellis/tasks/11-01-ohos-app-interop/design.md` for the rationale.
library;

import 'dart:convert';

/// Protocol version this client speaks. A receiver that answers anything else
/// is treated as incompatible rather than guessed at.
const String kInteropProtocol = 'qfli-interop/1';

/// Action a request asks for.
enum InteropAction {
  compile,
  run,
  analyze;

  String get wire => name;
}

/// Every documented failure code, plus the ones the client adds locally.
abstract final class InteropErrorCode {
  static const badRequest = 'bad_request';
  static const unsupportedProtocol = 'unsupported_protocol';
  static const callerNotAllowed = 'caller_not_allowed';
  static const payloadTooLarge = 'payload_too_large';
  static const payloadIntegrity = 'payload_integrity';
  static const unsupportedLanguage = 'unsupported_language';
  static const toolchainUnavailable = 'toolchain_unavailable';
  static const compileFailed = 'compile_failed';
  static const runFailed = 'run_failed';
  static const timeout = 'timeout';
  static const cancelled = 'cancelled';
  static const internal = 'internal';

  /// Client-only codes. They never come from a receiver.
  static const appMissing = 'app_missing';
  static const transportFailure = 'transport_failure';
  static const sequenceGap = 'sequence_gap';

  static const all = <String>{
    badRequest,
    unsupportedProtocol,
    callerNotAllowed,
    payloadTooLarge,
    payloadIntegrity,
    unsupportedLanguage,
    toolchainUnavailable,
    compileFailed,
    runFailed,
    timeout,
    cancelled,
    internal,
    appMissing,
    transportFailure,
    sequenceGap,
  };
}

/// Limits shared by both sides of the channel.
abstract final class InteropLimits {
  /// Decoded payload size. Above this the request is refused, never truncated.
  static const int maxPayloadBytes = 256 * 1024;

  /// File count in one payload.
  static const int maxFiles = 64;

  /// Relative path length. The receiver joins it with a session directory that
  /// has its own prefix, so the total stays under the filesystem limit.
  static const int maxPathLength = 240;

  /// Standard input text.
  static const int maxStdinBytes = 4 * 1024;

  /// Requested wall-clock budget.
  static const int minTimeoutMs = 1000;
  static const int maxTimeoutMs = 120000;

  /// One text chunk in a response event.
  static const int maxEventTextBytes = 4 * 1024;

  /// Output retained by the client before it stops appending.
  static const int maxRetainedOutputBytes = 128 * 1024;

  /// Session identifiers.
  static const int minSessionLength = 8;
  static const int maxSessionLength = 64;
}

/// A refusal raised where a real check failed. The message is written for a
/// user, not for a log.
class InteropException implements Exception {
  const InteropException(this.code, this.message);

  final String code;
  final String message;

  bool get isRetryable =>
      code == InteropErrorCode.transportFailure ||
      code == InteropErrorCode.sequenceGap;

  @override
  String toString() => message;
}

/// One file in a request payload. [content] is raw bytes; the wire form is
/// base64 so a binary compile artifact survives the trip.
class InteropPayloadFile {
  const InteropPayloadFile({required this.path, required this.content});

  final String path;
  final List<int> content;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'content': base64Encode(content),
  };

  @override
  bool operator ==(Object other) =>
      other is InteropPayloadFile &&
      other.path == path &&
      _listEquals(other.content, content);

  @override
  int get hashCode => Object.hash(path, Object.hashAll(content));

  @override
  String toString() => 'InteropPayloadFile($path, ${content.length} bytes)';
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Path grammar shared with the receiver.
///
/// A payload path is a relative POSIX path. Anything that could escape the
/// session directory, or that a receiver could misread as an absolute path on
/// another platform, is rejected here and again on the receiving side.
abstract final class InteropPath {
  /// Returns the path unchanged, or throws [InteropException] with
  /// `bad_request`. Callers use the return value so a validation cannot be
  /// written and then forgotten.
  static String validate(String path) {
    if (path.isEmpty) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'payload 路径不能为空',
      );
    }
    if (path.length > InteropLimits.maxPathLength) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'payload 路径超过 240 字符',
      );
    }
    if (path.contains('\u0000')) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'payload 路径包含 NUL',
      );
    }
    if (path.contains('\\')) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'payload 路径必须使用正斜杠',
      );
    }
    if (path.startsWith('/')) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'payload 路径必须是相对路径',
      );
    }
    // A Windows drive prefix would be read as relative by a POSIX receiver and
    // as absolute by a desktop caller. Reject it on both sides.
    if (RegExp(r'^[A-Za-z]:').hasMatch(path)) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'payload 路径不能带盘符',
      );
    }
    for (final rune in path.codeUnits) {
      if (rune < 0x20) {
        throw const InteropException(
          InteropErrorCode.badRequest,
          'payload 路径包含控制字符',
        );
      }
    }
    final segments = path.split('/');
    if (segments.isEmpty) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'payload 路径缺少文件名',
      );
    }
    for (final segment in segments) {
      if (segment.isEmpty) {
        throw const InteropException(
          InteropErrorCode.badRequest,
          'payload 路径有空段',
        );
      }
      if (segment == '.' || segment == '..') {
        throw const InteropException(
          InteropErrorCode.badRequest,
          'payload 路径不能包含 . 或 .. 段',
        );
      }
      if (segment.startsWith('.')) {
        throw const InteropException(
          InteropErrorCode.badRequest,
          'payload 路径不能包含隐藏段',
        );
      }
    }
    return path;
  }

  /// True when [path] would pass [validate]. Used by callers that collect a
  /// directory tree and must skip entries instead of failing the whole run.
  static bool isValid(String path) {
    try {
      validate(path);
      return true;
    } on InteropException {
      return false;
    }
  }
}

/// Session identifier grammar.
abstract final class InteropSession {
  static final RegExp _pattern = RegExp(r'^[A-Za-z0-9_-]+$');

  static String validate(String id) {
    if (id.length < InteropLimits.minSessionLength ||
        id.length > InteropLimits.maxSessionLength ||
        !_pattern.hasMatch(id)) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        '会话标识必须是 8-64 个字母、数字、下划线或连字符',
      );
    }
    return id;
  }

  /// A fresh identifier that satisfies [validate].
  ///
  /// Built from the clock and a counter rather than `Random.secure`: this is a
  /// correlation token inside one device, and the receiver checks the caller
  /// bundle instead of trusting the token for authorisation.
  static String create({int? now, int next = 0}) {
    final stamp = (now ?? DateTime.now().microsecondsSinceEpoch).toRadixString(
      36,
    );
    final suffix = next.toRadixString(36);
    final id = 'qfli-$stamp-$suffix';
    // A truncated id would drop the uniqueness suffix, so the caller must not
    // pass a value that overflows. Programmer error, not user input.
    assert(
      id.length <= InteropLimits.maxSessionLength,
      'session id exceeds the wire limit',
    );
    return id.length > InteropLimits.maxSessionLength
        ? id.substring(0, InteropLimits.maxSessionLength)
        : id;
  }
}

/// A request to compile or run a project in a sibling app.
class InteropRequest {
  InteropRequest({
    required this.sessionId,
    required this.language,
    required this.entry,
    required this.action,
    required this.callerBundle,
    required this.bridgeAction,
    this.sessionToken = '',
    List<InteropPayloadFile> files = const [],
    this.stdin = '',
    this.timeoutMs = 60000,
    this.protocol = kInteropProtocol,
  }) : files = List<InteropPayloadFile>.unmodifiable(files);

  final String protocol;
  final String sessionId;
  final String language;
  final String entry;
  final InteropAction action;
  final String callerBundle;
  final String bridgeAction;

  /// Random per-run secret echoed by every response event.
  ///
  /// Response events cross as broadcast common events that any application
  /// can publish, so the event parameters alone prove nothing. The receiver
  /// copies this token from the request into every event, and the caller
  /// drops events whose token does not match the one it generated.
  final String sessionToken;
  final List<InteropPayloadFile> files;
  final String stdin;
  final int timeoutMs;

  /// Serialized payload. Stable across calls so [filesDigest] always matches.
  String get filesJson =>
      jsonEncode(<Object?>[for (final file in files) file.toJson()]);

  /// Lowercase hex SHA-256 of [filesJson], byte for byte.
  String get filesDigest => _sha256Hex(utf8.encode(filesJson));

  /// Validates every rule and returns the launch parameters, or throws
  /// [InteropException]. The digest is computed from the encoded payload, so a
  /// caller cannot send a digest that does not describe the files.
  Map<String, String> toLaunchParameters() {
    _validate();
    return <String, String>{
      'protocol': protocol,
      'sessionId': sessionId,
      'sessionToken': sessionToken,
      'language': language,
      'entry': entry,
      'action': action.wire,
      'stdin': stdin,
      'timeoutMs': '$timeoutMs',
      'callerBundle': callerBundle,
      'bridgeAction': bridgeAction,
      'files': filesJson,
      'filesDigest': filesDigest,
    };
  }

  /// Decodes launch parameters. Used by tests and by the Dart side of the
  /// receiver contract; the ArkTS receiver mirrors the same checks.
  factory InteropRequest.fromLaunchParameters(Map<String, Object?> raw) {
    String read(String key) {
      final value = raw[key];
      if (value is! String) {
        throw InteropException(InteropErrorCode.badRequest, '缺少参数 $key');
      }
      return value;
    }

    final filesText = read('files');
    final structured = _decodeFiles(filesText);
    final actionText = read('action');
    final action = InteropAction.values
        .where((value) => value.wire == actionText)
        .firstOrNull;
    if (action == null) {
      throw InteropException(
        InteropErrorCode.badRequest,
        '未知 action：$actionText',
      );
    }
    final timeoutText = read('timeoutMs');
    final timeoutMs = int.tryParse(timeoutText);
    if (timeoutMs == null) {
      throw InteropException(InteropErrorCode.badRequest, 'timeoutMs 不是整数');
    }
    final request = InteropRequest(
      protocol: read('protocol'),
      sessionId: read('sessionId'),
      sessionToken: read('sessionToken'),
      language: read('language'),
      entry: read('entry'),
      action: action,
      callerBundle: read('callerBundle'),
      bridgeAction: read('bridgeAction'),
      files: structured,
      stdin: read('stdin'),
      timeoutMs: timeoutMs,
    );
    request._validate(sentDigest: read('filesDigest'));
    return request;
  }

  void _validate({String? sentDigest}) {
    if (protocol != kInteropProtocol) {
      throw InteropException(
        InteropErrorCode.unsupportedProtocol,
        '对方只支持 $kInteropProtocol：$protocol',
      );
    }
    InteropSession.validate(sessionId);
    if (!RegExp(r'^[A-Za-z0-9]{16,64}$').hasMatch(sessionToken)) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        '会话令牌必须是 16-64 个字母或数字',
      );
    }
    if (language.isEmpty) {
      throw const InteropException(InteropErrorCode.badRequest, '缺少语言');
    }
    if (callerBundle.isEmpty) {
      throw const InteropException(InteropErrorCode.badRequest, '缺少调用方包名');
    }
    if (bridgeAction.isEmpty) {
      throw const InteropException(InteropErrorCode.badRequest, '缺少回调 action');
    }
    if (timeoutMs < InteropLimits.minTimeoutMs ||
        timeoutMs > InteropLimits.maxTimeoutMs) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'timeoutMs 超出 1000-120000',
      );
    }
    if (stdin.contains('\u0000')) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'stdin 不能包含 NUL',
      );
    }
    if (utf8.encode(stdin).length > InteropLimits.maxStdinBytes) {
      throw const InteropException(
        InteropErrorCode.payloadTooLarge,
        'stdin 超过 4 KiB',
      );
    }
    // `analyze` is the capability handshake and carries no files.
    if (files.length > InteropLimits.maxFiles) {
      throw const InteropException(
        InteropErrorCode.payloadTooLarge,
        'payload 超过 64 个文件',
      );
    }
    var bytes = 0;
    final seen = <String>{};
    for (final file in files) {
      InteropPath.validate(file.path);
      if (!seen.add(file.path)) {
        throw InteropException(
          InteropErrorCode.badRequest,
          'payload 有重复路径：${file.path}',
        );
      }
      bytes += file.content.length;
    }
    if (bytes > InteropLimits.maxPayloadBytes) {
      throw const InteropException(
        InteropErrorCode.payloadTooLarge,
        'payload 超过 256 KiB',
      );
    }
    if (action != InteropAction.analyze) {
      InteropPath.validate(entry);
      if (!seen.contains(entry)) {
        throw InteropException(
          InteropErrorCode.badRequest,
          '入口文件不在 payload 中：$entry',
        );
      }
    } else if (entry.isNotEmpty) {
      InteropPath.validate(entry);
    }
    if (sentDigest != null && sentDigest != filesDigest) {
      throw const InteropException(
        InteropErrorCode.payloadIntegrity,
        'payload 校验和不匹配',
      );
    }
  }
}

List<InteropPayloadFile> _decodeFiles(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const InteropException(
      InteropErrorCode.badRequest,
      'files 不是合法 JSON',
    );
  }
  if (decoded is! List) {
    throw const InteropException(InteropErrorCode.badRequest, 'files 必须是数组');
  }
  final files = <InteropPayloadFile>[];
  for (final item in decoded) {
    if (item is! Map) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'files 的条目必须是对象',
      );
    }
    final path = item['path'];
    final content = item['content'];
    if (path is! String || content is! String) {
      throw const InteropException(
        InteropErrorCode.badRequest,
        'files 的条目缺少 path 或 content',
      );
    }
    final List<int> bytes;
    try {
      bytes = base64Decode(content);
    } on FormatException {
      throw InteropException(
        InteropErrorCode.badRequest,
        '文件内容不是 base64：$path',
      );
    }
    files.add(InteropPayloadFile(path: path, content: bytes));
  }
  return files;
}

/// Response event kinds.
enum InteropEventKind {
  accepted,
  stdout,
  stderr,
  progress,
  artifact,
  done,
  error;

  static InteropEventKind? parse(Object? value) {
    if (value is! String) return null;
    for (final kind in InteropEventKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// One event sent back by the receiver.
class InteropEvent {
  const InteropEvent({
    required this.sessionId,
    required this.seq,
    required this.kind,
    this.text = '',
    this.exitCode,
    this.artifacts = const [],
    this.code,
  });

  final String sessionId;
  final int seq;
  final InteropEventKind kind;
  final String text;
  final int? exitCode;
  final List<String> artifacts;
  final String? code;

  bool get isTerminal =>
      kind == InteropEventKind.done || kind == InteropEventKind.error;

  /// Launch parameters the receiver sends to the caller's bridge ability.
  Map<String, String> toLaunchParameters() {
    final parameters = <String, String>{
      'protocol': kInteropProtocol,
      'sessionId': sessionId,
      'seq': '$seq',
      'event': kind.name,
      'text': text,
    };
    final code = this.code;
    final exitCode = this.exitCode;
    if (exitCode != null) parameters['exitCode'] = '$exitCode';
    if (artifacts.isNotEmpty) {
      parameters['artifacts'] = jsonEncode(artifacts);
    }
    if (code != null) parameters['code'] = code;
    return parameters;
  }

  /// Parses bridge parameters. Throws [InteropException] for a malformed event
  /// so the transport can report it instead of silently dropping data.
  factory InteropEvent.fromLaunchParameters(Map<String, Object?> raw) {
    final protocol = raw['protocol'];
    if (protocol != kInteropProtocol) {
      throw InteropException(
        InteropErrorCode.unsupportedProtocol,
        '回调事件协议不匹配：$protocol',
      );
    }
    final sessionId = raw['sessionId'];
    if (sessionId is! String) {
      throw const InteropException(InteropErrorCode.badRequest, '回调事件缺少会话标识');
    }
    try {
      InteropSession.validate(sessionId);
    } on InteropException {
      throw const InteropException(InteropErrorCode.badRequest, '回调事件会话标识无效');
    }
    final seq = int.tryParse('${raw['seq']}');
    if (seq == null || seq < 1) {
      throw const InteropException(InteropErrorCode.badRequest, '回调事件缺少序号');
    }
    final kind = InteropEventKind.parse(raw['event']);
    if (kind == null) {
      throw const InteropException(InteropErrorCode.badRequest, '回调事件类型未知');
    }
    final text = raw['text'];
    if (text != null && text is! String) {
      throw const InteropException(InteropErrorCode.badRequest, '回调事件文本无效');
    }
    final exitCode = raw['exitCode'] == null
        ? null
        : int.tryParse('${raw['exitCode']}');
    final artifactsRaw = raw['artifacts'];
    final artifacts = <String>[];
    if (artifactsRaw is String && artifactsRaw.isNotEmpty) {
      final Object? decoded;
      try {
        decoded = jsonDecode(artifactsRaw);
      } on FormatException {
        throw const InteropException(InteropErrorCode.badRequest, '回调事件产物列表无效');
      }
      if (decoded is! List) {
        throw const InteropException(InteropErrorCode.badRequest, '回调事件产物列表无效');
      }
      for (final item in decoded) {
        if (item is! String) {
          throw const InteropException(
            InteropErrorCode.badRequest,
            '回调事件产物列表无效',
          );
        }
        // Artifacts are names inside the receiver's session directory. They
        // are informational here, so a bad name is dropped rather than
        // propagated to the UI.
        if (InteropPath.isValid(item)) artifacts.add(item);
      }
    }
    if (kind == InteropEventKind.done && exitCode == null) {
      throw const InteropException(InteropErrorCode.badRequest, '完成事件缺少退出码');
    }
    final code = raw['code'];
    if (kind == InteropEventKind.error) {
      if (code is! String || !InteropErrorCode.all.contains(code)) {
        throw const InteropException(
          InteropErrorCode.badRequest,
          '错误事件缺少有效错误码',
        );
      }
    }
    return InteropEvent(
      sessionId: sessionId,
      seq: seq,
      kind: kind,
      text: text is String ? text : '',
      exitCode: exitCode,
      artifacts: artifacts,
      code: code is String ? code : null,
    );
  }

  @override
  String toString() =>
      'InteropEvent($sessionId#$seq ${kind.name}'
      '${code == null ? '' : ' $code'})';
}

/// Sequencer that rejects duplicated, reordered or foreign events.
///
/// A receiver may retry a start and deliver the same sequence twice, and a
/// stale session may still be in flight. Both are dropped here so the caller's
/// output can only advance.
class InteropEventSequencer {
  InteropEventSequencer(this.sessionId);

  final String sessionId;
  int _lastSeq = 0;
  bool _finished = false;

  bool get finished => _finished;

  /// Returns null when the event should be ignored, otherwise the accepted
  /// event. Throws [InteropException] with `sequence_gap` when an event skips
  /// ahead, because a gap means output was lost and the caller must not claim
  /// a complete transcript.
  InteropEvent? accept(InteropEvent event) {
    if (event.sessionId != sessionId) return null;
    if (event.seq <= _lastSeq) return null;
    if (event.seq != _lastSeq + 1) {
      throw InteropException(
        InteropErrorCode.sequenceGap,
        '回调事件序号跳变：期望 ${_lastSeq + 1}，收到 ${event.seq}',
      );
    }
    if (_finished) return null;
    _lastSeq = event.seq;
    if (event.isTerminal) _finished = true;
    return event;
  }
}

/// SHA-256 over [bytes], lowercase hex.
///
/// Written here instead of taking a dependency on `package:crypto`: this
/// library is linked into every language App, and a new dependency would have
/// to be added to ten `pubspec.yaml` files to build the interop code at all.
/// The receiver recomputes the same digest with its platform hash, so this
/// implementation only has to match FIPS 180-4, which the tests pin against
/// the published digests for the empty string and for "abc".
String _sha256Hex(List<int> bytes) {
  final digest = _Sha256().convert(bytes);
  final out = StringBuffer();
  for (final byte in digest) {
    out.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// Minimal SHA-256 for the payload digest.
class _Sha256 {
  static const List<int> _k = <int>[
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

  static const int _mask = 0xffffffff;

  static int _rotr(int value, int count) =>
      ((value >> count) | (value << (32 - count))) & _mask;

  List<int> convert(List<int> message) {
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
    final bitLength = message.length * 8;
    final padded = <int>[...message, 0x80];
    while (padded.length % 64 != 56) {
      padded.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      padded.add((bitLength >> shift) & 0xff);
    }
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
            _rotr(w[index - 15], 7) ^
            _rotr(w[index - 15], 18) ^
            (w[index - 15] >> 3);
        final s1 =
            _rotr(w[index - 2], 17) ^
            _rotr(w[index - 2], 19) ^
            (w[index - 2] >> 10);
        w[index] = (w[index - 16] + s0 + w[index - 7] + s1) & _mask;
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
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ (~e & _mask & g);
        final temp1 = (h + s1 + ch + _k[index] + w[index]) & _mask;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & _mask;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) & _mask;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & _mask;
      }
      hash[0] = (hash[0] + a) & _mask;
      hash[1] = (hash[1] + b) & _mask;
      hash[2] = (hash[2] + c) & _mask;
      hash[3] = (hash[3] + d) & _mask;
      hash[4] = (hash[4] + e) & _mask;
      hash[5] = (hash[5] + f) & _mask;
      hash[6] = (hash[6] + g) & _mask;
      hash[7] = (hash[7] + h) & _mask;
    }
    final out = <int>[];
    for (final word in hash) {
      out
        ..add((word >> 24) & 0xff)
        ..add((word >> 16) & 0xff)
        ..add((word >> 8) & 0xff)
        ..add(word & 0xff);
    }
    return out;
  }
}

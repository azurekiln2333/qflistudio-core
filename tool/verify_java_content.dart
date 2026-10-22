import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/content/java_catalog_audit.dart';

import 'java_content/java_topics.dart';

/// Verifies every shipped Java payload, including every tutorial lesson and
/// both legacy mirrors, against the complete authored inventory. This tool
/// never generates assets. Real child processes have bounded time and output.
///
/// dart run tool/verify_java_content.dart [jdkHome] [--report report.json]
///   [--timeout-seconds 60] [--inventory-only]
///   [--wsl-distribution qfli-java-build]
///   [--expected-topics 280] (an explicit smaller historical baseline only)
///
/// With --wsl-distribution, jdkHome is a Linux path. Windows Dart invokes the
/// real WSL JDK through coreutils timeout; no Windows JDK runtime is implied.
Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/verify_java_content.dart [jdkHome] '
      '[--report report.json] [--timeout-seconds 60] '
      '[--inventory-only] [--wsl-distribution distribution] [--expected-topics 280]',
    );
    exitCode = 2;
    return;
  }
  final reportFile = File(options.reportPath).absolute;
  final report = <String, Object?>{
    'schemaVersion': 2,
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'environment': {
      'kind': options.wslDistribution == null ? 'host' : 'wsl-host',
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'dartVersion': Platform.version,
      'wslDistribution': options.wslDistribution,
      'isOhosDeviceEvidence': false,
    },
    'releaseTarget': '17',
    'timeoutSeconds': options.timeout.inSeconds,
    'outputLimitBytesPerStream': _outputLimit,
    'expectedTopicCount': options.expectedTopicCount,
  };
  Directory? workRoot;
  var allProcessesExited = true;
  var ok = false;
  try {
    final assets = <String, File>{
      'tutorials': File('assets/content/tutorials.json').absolute,
      'examples': File('assets/content/examples.json').absolute,
      'legacy': File('assets/tutorials/java.json').absolute,
    };
    final sources = {
      for (final asset in assets.entries)
        asset.key: await asset.value.readAsString(),
    };
    final inventory = JavaCatalogInventory.fromSources(
      tutorialsSource: sources['tutorials']!,
      examplesSource: sources['examples']!,
      legacySource: sources['legacy']!,
      expectedTopicCount: options.expectedTopicCount,
      authoredTopics: [
        for (final topic in javaTopics)
          JavaAuditTopic(
            id: topic.id,
            code: topic.code,
            output: topic.output,
            input: topic.input,
            objective: topic.objective,
            prerequisites: topic.prerequisites,
            pitfalls: topic.pitfalls,
          ),
      ],
    );
    report['assets'] = {
      for (final asset in assets.entries)
        asset.key: {
          'path': asset.value.path,
          'bytes': await asset.value.length(),
          'sha256': javaCatalogBytesSha256(await asset.value.readAsBytes()),
        },
    };
    report['authoredSources'] = [
      for (final file in Directory(
        'tool/java_content',
      ).listSync().whereType<File>())
        if (file.path.endsWith('.dart'))
          {
            'path': file.path,
            'sha256': javaCatalogBytesSha256(await file.readAsBytes()),
          },
    ];
    report['inventory'] = inventory.toJson();
    stdout.writeln(
      'Inventory: ${inventory.snippets.length} snippets, '
      '${inventory.executionGroups.length} distinct payloads, '
      '${inventory.issues.length} issues.',
    );
    for (final issue in inventory.issues) {
      stderr.writeln('Inventory: $issue');
    }
    if (options.inventoryOnly) {
      report['executionPerformed'] = false;
      report['executionComplete'] = false;
      ok = inventory.ok;
    } else {
      final jdk = _HostJdk(options);
      final javaVersion = await jdk.run('java', [
        '-version',
      ], Directory.current.path);
      final javacVersion = await jdk.run('javac', [
        '-version',
      ], Directory.current.path);
      final properties = await jdk.run('java', [
        '-XshowSettings:properties',
        '-version',
      ], Directory.current.path);
      report['javaVersionProbe'] = javaVersion;
      report['javacVersionProbe'] = javacVersion;
      report['runtimePropertiesProbe'] = properties;
      final javaText = '${javaVersion['stdout']}\n${javaVersion['stderr']}';
      final javacText = '${javacVersion['stdout']}\n${javacVersion['stderr']}';
      final javaMajor = RegExp(
        r'(?:openjdk|java) (?:version )?"?(\d+)',
      ).firstMatch(javaText)?.group(1);
      final javacMajor = RegExp(r'javac (\d+)').firstMatch(javacText)?.group(1);
      report['runtimeMajorVersion'] = int.tryParse(javaMajor ?? '');
      report['isJava17Runtime'] = javaMajor == '17';
      report['compilerMajorVersion'] = int.tryParse(javacMajor ?? '');
      report['isJavac17Compiler'] = javacMajor == '17';
      if (javaVersion['ok'] != true ||
          javacVersion['ok'] != true ||
          properties['ok'] != true ||
          javaMajor != '17' ||
          javacMajor != '17') {
        throw StateError(
          'Verification requires real Java 17 and javac 17 probes',
        );
      }
      stdout.writeln(javaText.trim());
      stdout.writeln(javacText.trim());
      workRoot = await Directory.systemTemp.createTemp('qfli-java-catalog-');
      final executions = <Map<String, Object?>>[];
      final snippetResults = <Map<String, Object?>>[];
      var passed = 0;
      var index = 0;
      final executionGroups = inventory.executionGroups;
      for (final group in executionGroups.entries) {
        index++;
        final snippet = group.value.first;
        final project = await Directory(
          p.join(workRoot.path, 'p$index'),
        ).create();
        final classes = await Directory(
          p.join(project.path, 'classes'),
        ).create();
        final source = File(p.join(project.path, 'Main.java'));
        await source.writeAsString(snippet.code, encoding: utf8);
        final compile = await jdk.run('javac', [
          '--release',
          '17',
          '-proc:none',
          '-encoding',
          'UTF-8',
          '-J-Duser.language=en',
          '-J-Duser.country=US',
          '-J-Duser.timezone=UTC',
          '-d',
          jdk.path(classes.path),
          jdk.path(source.path),
        ], project.path);
        allProcessesExited =
            allProcessesExited && compile['processExited'] == true;
        Map<String, Object?>? run;
        if (compile['ok'] == true) {
          run = await jdk.run(
            'java',
            [
              '-Dfile.encoding=UTF-8',
              '-Dstdout.encoding=UTF-8',
              '-Dstderr.encoding=UTF-8',
              '-Dsun.stdout.encoding=UTF-8',
              '-Dsun.stderr.encoding=UTF-8',
              '-Duser.language=en',
              '-Duser.country=US',
              '-Duser.timezone=UTC',
              '-classpath',
              jdk.path(classes.path),
              'Main',
            ],
            project.path,
            input: snippet.fixtures['stdin'] ?? '',
          );
          allProcessesExited =
              allProcessesExited && run['processExited'] == true;
        }
        final actual = run == null
            ? null
            : normalizeJavaCatalogOutput(run['stdout'] as String);
        final expected = normalizeJavaCatalogOutput(snippet.expectedOutput);
        final success =
            compile['ok'] == true && run?['ok'] == true && actual == expected;
        if (success) passed++;
        final status = compile['ok'] != true
            ? 'compile_failure'
            : run?['ok'] != true
            ? 'runtime_failure'
            : actual != expected
            ? 'output_mismatch'
            : 'ok';
        executions.add({
          'payloadSha256': group.key,
          'sourceSha256': snippet.sourceSha256,
          'locations': group.value.map((item) => item.location).toList(),
          'status': status,
          'expected': expected,
          'actual': actual,
          'compile': compile,
          'run': run,
        });
        for (final mirror in group.value) {
          snippetResults.add({
            ...mirror.toJson(),
            'status': status,
            'executionIndex': index - 1,
            'exitCode': run?['exitCode'],
            'actual': actual,
          });
        }
        stdout.writeln(
          '[$index/${executionGroups.length}] ${snippet.topicId}: $status',
        );
        report.addAll({
          'executionPerformed': true,
          'executionComplete': index == executionGroups.length,
          'executions': executions,
          'snippetResults': snippetResults,
          'passedPayloads': passed,
          'failedPayloads': index - passed,
          'verifiedSnippetCount': snippetResults
              .where((result) => result['status'] == 'ok')
              .length,
        });
        await _writeReport(reportFile, report);
        if (!allProcessesExited) {
          throw StateError(
            'Child termination could not be verified; retained workspace ${workRoot.path}',
          );
        }
      }
      ok =
          inventory.ok &&
          passed == executionGroups.length &&
          executionGroups.isNotEmpty;
    }
  } catch (error, stack) {
    report['error'] = error.toString();
    report['stack'] = stack.toString();
    stderr.writeln(error);
  } finally {
    report['ok'] = ok;
    report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    await _writeReport(reportFile, report);
    if (workRoot != null && !allProcessesExited) {
      report['retainedWorkRoot'] = workRoot.path;
      await _writeReport(reportFile, report);
    }
    if (workRoot != null && allProcessesExited && await workRoot.exists()) {
      try {
        await workRoot.delete(recursive: true);
      } on FileSystemException catch (error) {
        stderr.writeln('Temporary-directory cleanup failed: $error');
      }
    }
  }
  stdout.writeln(
    'QFLI_JAVA_CONTENT_AUDIT ${jsonEncode({'ok': ok, 'report': reportFile.path, 'deviceEvidence': false})}',
  );
  if (!ok) exitCode = 1;
}

Future<void> _writeReport(File file, Map<String, Object?> report) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
}

const _outputLimit = 1024 * 1024;

class _Options {
  String? home;
  String reportPath = 'build/java-content-verification.json';
  String? wslDistribution;
  Duration timeout = const Duration(seconds: 60);
  bool inventoryOnly = false;
  int expectedTopicCount = 280;

  static _Options? parse(List<String> args) {
    final options = _Options();
    for (var index = 0; index < args.length; index++) {
      final argument = args[index];
      if (argument == '--inventory-only') {
        options.inventoryOnly = true;
      } else if ([
        '--report',
        '--timeout-seconds',
        '--wsl-distribution',
        '--expected-topics',
      ].contains(argument)) {
        if (++index >= args.length) return null;
        final value = args[index];
        switch (argument) {
          case '--report':
            options.reportPath = value;
          case '--wsl-distribution':
            options.wslDistribution = value;
          case '--timeout-seconds':
            final seconds = int.tryParse(value);
            if (seconds == null || seconds < 1 || seconds > 600) return null;
            options.timeout = Duration(seconds: seconds);
          case '--expected-topics':
            final count = int.tryParse(value);
            if (count == null || count < 1 || count > 10000) return null;
            options.expectedTopicCount = count;
        }
      } else if (!argument.startsWith('-') && options.home == null) {
        options.home = argument;
      } else {
        return null;
      }
    }
    return options;
  }
}

class _HostJdk {
  _HostJdk(this.options);
  final _Options options;

  String path(String windowsPath) {
    if (options.wslDistribution == null) return windowsPath;
    final normalized = windowsPath.replaceAll('\\', '/');
    if (RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      return '/mnt/${normalized[0].toLowerCase()}${normalized.substring(2)}';
    }
    return normalized;
  }

  Future<Map<String, Object?>> run(
    String tool,
    List<String> arguments,
    String cwd, {
    String input = '',
  }) async {
    final home =
        options.home ??
        (options.wslDistribution == null
            ? Platform.environment['QFLI_JAVA_HOME'] ??
                  Platform.environment['JAVA_HOME']
            : null);
    final executable = home == null
        ? tool
        : options.wslDistribution == null
        ? p.join(home, 'bin', Platform.isWindows ? '$tool.exe' : tool)
        : '$home/bin/$tool';
    final wsl = options.wslDistribution;
    return runJavaAuditHostProcess(
      wsl == null ? executable : 'wsl.exe',
      wsl == null
          ? arguments
          : [
              '--distribution',
              wsl,
              '--cd',
              path(cwd),
              '--exec',
              'timeout',
              '--signal=KILL',
              '${options.timeout.inSeconds}s',
              'env',
              'LC_ALL=C.UTF-8',
              'TZ=UTC',
              executable,
              ...arguments,
            ],
      cwd: cwd,
      input: input,
      timeout:
          options.timeout +
          (wsl == null ? Duration.zero : const Duration(seconds: 5)),
    );
  }
}

Future<Map<String, Object?>> runJavaAuditHostProcess(
  String executable,
  List<String> arguments, {
  required String cwd,
  required String input,
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  final report = <String, Object?>{
    'executable': executable,
    'arguments': arguments,
  };
  final output = <int>[];
  final error = <int>[];
  final tooMuch = Completer<void>();
  Process? process;
  StreamSubscription<List<int>>? outSubscription;
  StreamSubscription<List<int>>? errorSubscription;
  final drainedOut = Completer<void>();
  final drainedError = Completer<void>();
  var timedOut = false;
  var processExited = false;
  void collect(List<int> bytes, List<int> target) {
    final available = _outputLimit - target.length;
    target.addAll(bytes.take(available));
    if (bytes.length > available && !tooMuch.isCompleted) tooMuch.complete();
  }

  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: cwd,
      runInShell: false,
      environment: const {'LC_ALL': 'C.UTF-8', 'TZ': 'UTC'},
    );
    outSubscription = process.stdout.listen(
      (bytes) => collect(bytes, output),
      onDone: () {
        if (!drainedOut.isCompleted) drainedOut.complete();
      },
      onError: (Object error) {
        report['stdoutError'] = error.toString();
        if (!drainedOut.isCompleted) drainedOut.complete();
      },
    );
    errorSubscription = process.stderr.listen(
      (bytes) => collect(bytes, error),
      onDone: () {
        if (!drainedError.isCompleted) drainedError.complete();
      },
      onError: (Object error) {
        report['stderrError'] = error.toString();
        if (!drainedError.isCompleted) drainedError.complete();
      },
    );
    unawaited(() async {
      try {
        process!.stdin.add(utf8.encode(input));
        await process.stdin.close();
      } on IOException {
        // Compilers and immediately exiting programs may close their stdin.
      }
    }());
    try {
      final code = await Future.any<int>([
        process.exitCode,
        tooMuch.future.then(
          (_) => throw StateError('Output exceeded $_outputLimit bytes'),
        ),
      ]).timeout(timeout);
      report['exitCode'] = code;
      processExited = true;
      timedOut = code == 124 || code == 137;
    } on TimeoutException {
      timedOut = true;
      report['error'] = 'Process exceeded ${timeout.inSeconds} seconds';
      process.kill(ProcessSignal.sigkill);
    } catch (failure) {
      report['error'] = failure.toString();
      process.kill(ProcessSignal.sigkill);
    }
    report['exitCode'] ??= await process.exitCode.timeout(
      const Duration(seconds: 5),
    );
    processExited = true;
    await Future.wait([
      drainedOut.future,
      drainedError.future,
    ]).timeout(const Duration(seconds: 5));
  } catch (failure) {
    report['error'] = failure.toString();
    process?.kill(ProcessSignal.sigkill);
  } finally {
    if (process != null && !processExited) {
      process.kill(ProcessSignal.sigkill);
      try {
        report['exitCode'] = await process.exitCode.timeout(
          const Duration(seconds: 5),
        );
        processExited = true;
      } catch (error) {
        report['exitWaitError'] = error.toString();
      }
    }
    await outSubscription?.cancel();
    await errorSubscription?.cancel();
  }
  String decode(List<int> bytes, String stream) {
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      report['${stream}EncodingError'] = error.toString();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  final stdout = decode(output, 'stdout');
  final stderr = decode(error, 'stderr');
  report.addAll({
    'stdout': stdout,
    'stderr': stderr,
    'processExited': process == null || processExited,
    'processStarted': process != null,
    'timedOut': timedOut,
    'outputLimitExceeded': tooMuch.isCompleted,
    'elapsedMilliseconds': stopwatch.elapsedMilliseconds,
    'ok':
        report['exitCode'] == 0 &&
        !timedOut &&
        !tooMuch.isCompleted &&
        processExited &&
        !report.keys.any((key) => key.toLowerCase().endsWith('error')),
  });
  return report;
}

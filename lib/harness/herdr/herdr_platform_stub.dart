// Web build: no processes and no filesystem, so Herdr cannot exist here.
//
// Signatures must match `herdr_platform_io.dart` exactly; both are selected by
// `herdr_platform.dart`.

import 'herdr_cli.dart';

/// No `dart:io`, so nothing can be launched.
Future<String?> locateHerdrExecutable({
  String? explicitPath,
  Map<String, String>? environment,
  HerdrPathProbe? isExecutable,
  HerdrDirectoryLister? listDirectory,
  bool? isWindows,
  bool? isMacOS,
}) async => null;

/// No PATH to inspect.
bool executableOnPath(
  String name, {
  Map<String, String>? environment,
  HerdrPathProbe? isExecutable,
  HerdrDirectoryLister? listDirectory,
  bool? isWindows,
  bool? isMacOS,
}) => false;

/// A runner that reports the platform limitation on every call.
class HerdrCliRunner {
  HerdrCliRunner();

  Future<HerdrProcessResult> call(
    List<String> argv, {
    String? workingDirectory,
    required Duration timeout,
  }) async => const HerdrProcessResult(exitCode: -1, spawnError: 'ENOENT');

  Future<void> dispose() async {}
}

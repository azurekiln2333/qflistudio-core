import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/sync/device_git_pull.dart';
import 'package:qfli_studio_core/sync/sync_limits.dart';

GitProjectInfo _info({
  bool supported = true,
  String? remote = 'https://example.com/repo.git',
  int? gitBytes,
  String branch = 'main',
}) => GitProjectInfo(
  root: r'C:\work\repo',
  supported: supported,
  remote: remote,
  gitBytes: gitBytes,
  branch: branch,
);

void main() {
  group('GitProjectInfo', () {
    test('reads a full reply', () {
      final info = GitProjectInfo.fromJson(<String, dynamic>{
        'kind': 'project_git_info',
        'root': r'C:\work\repo',
        'supported': true,
        'gitBytes': 4096,
        'remote': 'git@github.com:qfli/studio.git',
        'branch': 'main',
        'head': 'a' * 40,
        'dirty': false,
      });
      expect(info.supported, isTrue);
      expect(info.gitBytes, 4096);
      expect(info.remote, 'git@github.com:qfli/studio.git');
      expect(info.branch, 'main');
      expect(info.head, 'a' * 40);
      expect(info.dirty, isFalse);
      expect(info.canClone, isTrue);
    });

    test('an unsupported directory reports nothing to clone', () {
      final info = GitProjectInfo.fromJson(<String, dynamic>{
        'root': r'C:\work\plain',
        'supported': false,
      });
      expect(info.supported, isFalse);
      expect(info.gitBytes, isNull);
      expect(info.remote, isNull);
      expect(info.dirty, isNull);
      expect(info.canClone, isFalse);
    });

    test('a blank remote is treated as missing', () {
      final info = GitProjectInfo.fromJson(<String, dynamic>{
        'root': r'C:\work\repo',
        'supported': true,
        'remote': '   ',
      });
      expect(info.remote, isNull);
      expect(info.canClone, isFalse);
    });

    test('a fractional byte count is truncated', () {
      final info = GitProjectInfo.fromJson(<String, dynamic>{
        'root': r'C:\work\repo',
        'supported': true,
        'gitBytes': 4096.9,
      });
      expect(info.gitBytes, 4096);
    });
  });

  group('DeviceGitPull.decide', () {
    const pull = DeviceGitPull();

    test('a small repository is cloned without a prompt', () {
      final report = pull.decide(_info(gitBytes: 1024));
      expect(report.outcome, GitPullOutcome.cloned);
      expect(report.needsUserConfirm, isFalse);
    });

    test('a repository exactly at the limit is cloned without a prompt', () {
      final report = pull.decide(_info(gitBytes: kGitConfirmBytes));
      expect(report.outcome, GitPullOutcome.cloned);
    });

    test('one byte over the limit asks first', () {
      final report = pull.decide(_info(gitBytes: kGitConfirmBytes + 1));
      expect(report.outcome, GitPullOutcome.needsConfirm);
      expect(report.needsUserConfirm, isTrue);
      expect(report.gitBytes, kGitConfirmBytes + 1);
    });

    test('an unknown size is cloned without a prompt', () {
      final report = pull.decide(_info());
      expect(report.outcome, GitPullOutcome.cloned);
      expect(report.gitBytes, isNull);
    });

    test('a directory without git metadata falls back to file sync', () {
      final report = pull.decide(_info(supported: false));
      expect(report.outcome, GitPullOutcome.fallbackToFiles);
      expect(report.reason, '该目录不是可直接读取的 Git 仓库');
    });

    test('a repository without origin falls back to file sync', () {
      final report = pull.decide(_info(remote: null));
      expect(report.outcome, GitPullOutcome.fallbackToFiles);
      expect(report.reason, '仓库没有 origin 远端');
    });

    test('the confirm threshold is configurable', () {
      final report = pull.decide(_info(gitBytes: 2048), confirmBytes: 1024);
      expect(report.outcome, GitPullOutcome.needsConfirm);
    });
  });

  group('DeviceGitPull.pull', () {
    const pull = DeviceGitPull();

    test('an unconfirmed large clone touches nothing', () async {
      final report = await pull.pull(
        _info(gitBytes: kGitConfirmBytes + 1),
        target: r'C:\app\projects\deviceProjects\x\repo',
        targetExists: false,
      );
      expect(report.outcome, GitPullOutcome.needsConfirm);
    });

    test('an unsupported project never reaches the clone path', () async {
      final report = await pull.pull(
        _info(supported: false),
        target: r'C:\app\projects\deviceProjects\x\repo',
        targetExists: false,
      );
      expect(report.outcome, GitPullOutcome.fallbackToFiles);
    });
  });
}

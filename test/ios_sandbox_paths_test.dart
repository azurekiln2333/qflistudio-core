import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/ios_sandbox_paths.dart';

void main() {
  const oldHome =
      '/var/mobile/Containers/Data/Application/'
      '9B813B57-CBD3-4C2A-92A0-F958195BFE48';
  const currentHome =
      '/private/var/mobile/Containers/Data/Application/'
      'B237EF81-E0DE-4B78-86F9-F9E0E80C8263';
  const documents = '$currentHome/Documents';
  const support = '$currentHome/Library/Application Support';
  const paths = IosSandboxPaths(documents: documents, support: support);

  test('a saved iOS project reference survives a changed container UUID', () {
    const moved = '$documents/projects/dartProjects/demo';
    final reference = paths.relativePath(moved);
    expect(reference, 'Documents/projects/dartProjects/demo');
    expect(
      paths.resolve(
        '$oldHome/Documents/projects/dartProjects/demo',
        relative: reference,
      ),
      moved,
    );
  });

  test('older private projects stay under Application Support', () {
    expect(
      paths.resolve('$oldHome/Library/Application Support/projects/demo'),
      '$support/projects/demo',
    );
  });

  test('external paths and similarly named directories are not remapped', () {
    for (final external in [
      '/var/mobile/Containers/Shared/AppGroup/group/Documents/demo',
      '$oldHome/DocumentsOther/projects/demo',
      '/another/Application/${oldHome.split('/').last}/Documents/demo',
    ]) {
      expect(paths.resolve(external), external);
      expect(paths.relativePath(external), isNull);
    }
  });

  test('relative references cannot escape either durable directory', () {
    for (final invalid in [
      'Documents/../../escape',
      'Library/Application Support/../Preferences',
      '/Documents/projects/demo',
    ]) {
      expect(paths.absolutePath(invalid), isNull);
    }
  });

  test('an absolute path already relocated by app restore stays in use', () {
    expect(
      paths.resolve(
        '$support/projects/demo',
        relative: 'Documents/projects/demo',
      ),
      '$support/projects/demo',
    );
  });
}

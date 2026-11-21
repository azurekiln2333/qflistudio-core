import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/project.dart';
import 'project_zip_service.dart';
import 'share_service.dart';

enum ArchiveShareStatus { shared, unsupported }

class ArchiveShareResult {
  const ArchiveShareResult({required this.status, required this.path});

  /// Shared means the OS accepted the handoff, not that a receiver saved it.
  final ArchiveShareStatus status;

  /// Retained on success, dismissal and unsupported platforms for save fallback.
  final String path;
}

/// Selection/project ZIP preparation boundary for editor and Home.
/// Cloud snapshots are C-owned and never mutate the editor working tree.
abstract final class ArchiveShareService {
  static Future<ArchiveShareResult> shareProject(Project project) =>
      shareSelection(project, selectedPath: project.path);

  static Future<ArchiveShareResult> shareSelection(
    Project project, {
    required String selectedPath,
  }) async {
    final root = p.normalize(p.absolute(project.path));
    final selected = p.normalize(p.absolute(selectedPath));
    if (!p.equals(root, selected) && !p.isWithin(root, selected)) {
      throw const ProjectZipException('Selected entry is outside its project.');
    }
    final selectedIsRoot = p.equals(selected, root);
    final name = _archiveName(
      selectedIsRoot ? project.name : p.basename(selected),
    );
    if (project.isCloud) {
      throw const ProjectZipException(
        'Cloud sharing requires a complete snapshot.',
      );
    }
    return _prepareAndShare(root: root, selected: selected, name: name);
  }

  static Future<ArchiveShareResult> _prepareAndShare({
    required String root,
    required String selected,
    required String name,
  }) async {
    // Application-support storage survives sheet dismissal/process restarts.
    // Only this dedicated subtree is exposed by native sharing providers.
    final support = await getApplicationSupportDirectory();
    final shareRoot = Directory(p.join(support.path, 'archive_shares'));
    await shareRoot.create(recursive: true);
    final operation = await shareRoot.createTemp('share-');
    final archive = p.join(operation.path, '$name.zip');
    var handoffStarted = false;
    try {
      await ProjectZipService.exportSelectionToFile(
        projectRoot: root,
        selectedPath: selected,
        destination: archive,
      );
      // A native failure can have an uncertain outcome. Once invoked, retain
      // the file even on errors: a receiver may already hold its URI.
      handoffStarted = true;
      final supported = await ShareService.shareFile(
        path: archive,
        title: name,
      );
      return ArchiveShareResult(
        status: supported
            ? ArchiveShareStatus.shared
            : ArchiveShareStatus.unsupported,
        path: archive,
      );
    } finally {
      // Never delete on share-sheet dismissal or unsupported; save fallback and
      // delayed receivers both need the same retained ZIP.
      if (!handoffStarted) {
        try {
          await operation.delete(recursive: true);
        } on FileSystemException {
          // Preserve the preparation failure.
        }
      }
    }
  }

  static String _archiveName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'project';
    return cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
  }
}

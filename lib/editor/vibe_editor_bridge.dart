import '../vibe_coding/vibe_tools.dart';

/// Project file access for the Vibe Coding agent that also refuses to overwrite
/// a file the editor still holds unsaved changes for.
///
/// Two layers protect the buffer:
/// - An eager check before the tool body runs, which fails fast and avoids
///   creating a backup for a write that will be refused anyway.
/// - [VibeProjectFiles.shouldWrite], re-evaluated by the base implementation
///   immediately before the real disk write, which closes the await window
///   between this check and the commit.
class EditorGuardedProjectFiles extends VibeProjectFiles {
  EditorGuardedProjectFiles({
    required super.projectRoot,
    required bool Function(String absolutePath) hasUnsavedEdits,
  }) : _hasUnsavedEdits = hasUnsavedEdits,
       // [VibeProjectFiles.shouldWrite] is a permissive predicate: true allows
       // the commit, false refuses it. A dirty buffer must refuse, so invert.
       super(shouldWrite: (absolute) => !hasUnsavedEdits(absolute));

  final bool Function(String absolutePath) _hasUnsavedEdits;

  void _rejectDirty(String absolute) {
    if (_hasUnsavedEdits(absolute)) {
      throw const VibeToolException('编辑器中有未保存的修改，已拒绝覆盖', code: 'conflict');
    }
  }

  @override
  Future<VibeWriteResult> write(
    String path,
    String content, {
    bool createOnly = false,
  }) async {
    _rejectDirty(resolve(path));
    return super.write(path, content, createOnly: createOnly);
  }

  @override
  Future<VibeWriteResult> edit(
    String path,
    String oldText,
    String newText, {
    bool replaceAll = false,
  }) async {
    _rejectDirty(resolve(path));
    return super.edit(path, oldText, newText, replaceAll: replaceAll);
  }
}

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import 'editor_diagnostics.dart';

/// 编辑器中一个已打开的文件（对应一个标签页）。
class OpenFile {
  OpenFile({
    required this.path,
    required String content,
    required CodeHighlightTheme? highlightTheme,
    this.ownerProjectName = '',
    required this.projectRootPath,
    this.projectType = '',
    this.readOnly = false,
    this.timeLabel,
    this.encoding = 'UTF-8',
    this.modifiedAt,
  }) : scrollController = CodeScrollController(),
       focusNode = FocusNode() {
    diagnostics = readOnly ? null : EditorFileDiagnostics(path);
    controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(content),
      options: CodeLineOptions(
        lineBreak: content.contains('\r\n')
            ? TextLineBreak.crlf
            : content.contains('\r')
            ? TextLineBreak.cr
            : TextLineBreak.lf,
      ),
      spanBuilder: diagnostics?.decorate,
    );
    diagnostics?.attach(controller);
    lastChangedText = controller.text;
    _highlightTheme = highlightTheme;
    findController = CodeFindController(controller);
  }

  final String path;

  /// 该文件所属项目的名称（用于跨项目标签显示 b/xxx.py）。
  final String ownerProjectName;
  final String projectRootPath;
  final String projectType;

  /// 历史版本只读打开：禁止保存/自动同步，标签显示时间。
  final bool readOnly;

  /// 只读快照的时间标签（如 09-13 22:15），显示在标签页上。
  final String? timeLabel;

  /// 文件编码（打开时自动识别，可在状态栏切换）。
  String encoding;
  DateTime? modifiedAt;
  late final CodeLineEditingController controller;
  late final EditorFileDiagnostics? diagnostics;
  late final CodeFindController findController;
  final CodeScrollController scrollController;
  final FocusNode focusNode;
  CodeHighlightTheme? _highlightTheme;
  bool dirty = false;
  int revision = 0;
  late String lastChangedText;
  Future<String?>? pendingSave;

  /// 文件的语法高亮主题（超大文件为 null，走纯文本渲染）。
  CodeHighlightTheme? get highlightTheme => _highlightTheme;

  String get name => p.basename(path);

  /// 标签页显示文本：本项目文件只显示名称，跨项目显示 项目名/相对路径。
  String tabLabel(String currentProjectName) {
    if (ownerProjectName == currentProjectName || ownerProjectName.isEmpty) {
      return name;
    }
    final relative = p.isWithin(projectRootPath, path)
        ? p.relative(path, from: projectRootPath)
        : path;
    final normalized = relative.replaceAll('\\', '/');
    return '$ownerProjectName/$normalized';
  }

  void dispose() {
    diagnostics?.dispose();
    controller.dispose();
    findController.dispose();
    focusNode.dispose();
  }
}

# Offline diagnostic contract

Public module: package:qfli_studio_core/services/code_analysis.dart. StudioProfile adds optional `CodeAnalyzer? codeAnalyzer` (import and re-export the types for adapter convenience). Existing runner is unchanged.

Freeze these names for product adapters:

```dart
abstract interface class CodeAnalyzer {
  Future<CodeAnalysisResult> analyze(CodeAnalysisRequest request);
}
class CodeDocumentSnapshot {
  const CodeDocumentSnapshot({required String path, required String text,
    required int revision});
  final String path; // normalized absolute owned project path
  final String text; // exact unsaved UTF-16 Dart string; preserve CRLF
  final int revision;
}
class CodeAnalysisRequest {
  CodeAnalysisRequest({required String projectPath, required String activeFilePath,
    required String language, required int revision,
    required List<CodeDocumentSnapshot> documents});
  final String projectPath, activeFilePath, language;
  final int revision; // active file's content revision
  final List<CodeDocumentSnapshot> documents; // immutable; active + other open root buffers
}
enum CodeDiagnosticSeverity { error, warning, information, hint }
class CodeDiagnostic {
  const CodeDiagnostic({required String filePath, required int startOffset,
    required int endOffset, required String message,
    CodeDiagnosticSeverity severity = CodeDiagnosticSeverity.error,
    String source = '', String code = ''});
  final String filePath;
  final int startOffset, endOffset; // zero-based UTF-16, half-open; insertion may be empty
  final String message, source, code;
  final CodeDiagnosticSeverity severity;
}
class CodeAnalysisResult {
  const CodeAnalysisResult({List<CodeDiagnostic> diagnostics = const [],
    String? unavailableReason});
  final List<CodeDiagnostic> diagnostics;
  final String? unavailableReason; // null = actual successful analysis, even if empty
}
```

Core captures all open buffers within the active owner root, including headers, preserving exact source text/revisions. Providers may read additional project source files and must overlay unsaved snapshots in an isolated temporary analysis environment. Never overwrite user files or run their program/annotation processors. Diagnostics for captured files use exact captured text; convert compiler UTF-8 bytes/line columns to UTF-16, never reinterpret bytes as Dart offsets. Diagnostics outside the root are rejected. For unopened disk files, Problems can show path/message, but do not decorate or select an unvalidated old range after loading; reanalyze the new snapshot before precise selection. Providers should prioritize captured-file diagnostics for deterministic navigation.

Core bounds snapshots/work, invalidates affected diagnostics on actual text changes, debounces analysis, and drops whole stale responses if any captured revision/text/root differs. Ignore selection-only changes. Read-only history snapshots do not request analysis. Catch provider errors as availability messages; do not claim clean syntax on backend failure. Clear marks when content changes or provider disappears. No global analyzer lock shared with unrelated products.

Implement wavy spans through re_editor CodeLineEditingController.spanBuilder, preserving highlighted span styles; use forceRepaint after diagnostic changes. Problems integrates as a real bottom-panel tab with bounded layout and jump actions. Existing terminal retains stream/cancel/focus semantics. No vendor fork and no debugger simulation.

Default grammars use installed re_highlight exports; keep custom TextMate/theme caches and large-file safeguards. Rollback is narrow owned paths only.

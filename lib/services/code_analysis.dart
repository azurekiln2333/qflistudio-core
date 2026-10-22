/// Product-owned, offline source analysis. Implementations must never execute
/// user code, overwrite project files, or use a network fallback.
abstract interface class CodeAnalyzer {
  Future<CodeAnalysisResult> analyze(CodeAnalysisRequest request);
}

/// Exact editor text at a content revision. Offsets are UTF-16 code units,
/// including both code units in a CRLF line ending.
class CodeDocumentSnapshot {
  const CodeDocumentSnapshot({
    required this.path,
    required this.text,
    required this.revision,
  });

  final String path;
  final String text;
  final int revision;
}

/// An active document and the other open buffers belonging to its project.
/// Paths are normalized absolute paths. Providers overlay these snapshots when
/// reading additional project files; the disk contents may be older.
class CodeAnalysisRequest {
  CodeAnalysisRequest({
    required this.projectPath,
    required this.activeFilePath,
    required this.language,
    required this.revision,
    required List<CodeDocumentSnapshot> documents,
  }) : documents = List.unmodifiable(documents);

  final String projectPath;
  final String activeFilePath;
  final String language;
  final int revision;
  final List<CodeDocumentSnapshot> documents;
}

enum CodeDiagnosticSeverity { error, warning, information, hint }

/// A half-open, zero-based UTF-16 range in the analyzed document text.
/// Empty ranges represent insertion points. The editor validates the current
/// snapshot before decorating or selecting a range, and rejects foreign paths.
class CodeDiagnostic {
  const CodeDiagnostic({
    required this.filePath,
    required this.startOffset,
    required this.endOffset,
    required this.message,
    this.severity = CodeDiagnosticSeverity.error,
    this.source = '',
    this.code = '',
  });

  final String filePath;
  final int startOffset;
  final int endOffset;
  final String message;
  final CodeDiagnosticSeverity severity;
  final String source;
  final String code;
}

/// A successful empty result means the backend actually checked the source.
/// Unavailable/error results must explain why instead of reporting clean code.
class CodeAnalysisResult {
  const CodeAnalysisResult({
    this.diagnostics = const [],
    this.unavailableReason,
  });

  final List<CodeDiagnostic> diagnostics;
  final String? unavailableReason;
}

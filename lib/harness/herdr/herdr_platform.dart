// Conditional export: desktop/CLI resolves the process-backed platform layer,
// web resolves a stub that reports the limitation instead of crashing.
export 'herdr_platform_stub.dart' if (dart.library.io) 'herdr_platform_io.dart';

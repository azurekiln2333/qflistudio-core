import 'dart:convert';

import 'api_client.dart';

/// Terminal rendering of a cloud MySQL script result (`/api/sql/script`).
/// The output format matches the SQLab project runner.
class CloudSqlOutput {
  const CloudSqlOutput({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final List<String> stdout;
  final List<String> stderr;
  final int exitCode;

  static CloudSqlOutput fromScript(Map<String, dynamic> raw) {
    final results = raw['results'];
    final exitCode = raw['exitCode'];
    if (results is! List || exitCode is! num) {
      throw ApiException('云 MySQL 返回了无效的脚本结果');
    }
    final stdout = <String>[];
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      if (result is! Map) throw ApiException('云 MySQL 返回了无效的结果集');
      final columns = result['columns'];
      final rows = result['rows'];
      if (columns is! List || rows is! List) {
        throw ApiException('云 MySQL 返回了无效的结果集');
      }
      // A failed statement has its own empty entry; the error goes to stderr.
      if (columns.isEmpty && (result['error'] as String? ?? '').isNotEmpty) {
        continue;
      }
      if (results.length > 1) stdout.add('结果 ${index + 1}');
      if (columns.isEmpty) {
        stdout.add('影响 ${(result['affectedRows'] as num?)?.toInt() ?? 0} 行');
        continue;
      }
      stdout.add(columns.join(' | '));
      for (final row in rows) {
        if (row is! List) throw ApiException('云 MySQL 返回了无效的行');
        stdout.add(
          row
              .map((value) => value == null ? 'NULL' : jsonEncode(value))
              .join(' | '),
        );
      }
    }
    final error = raw['error'] as String? ?? '';
    return CloudSqlOutput(
      stdout: stdout,
      stderr: [
        if (error.isNotEmpty) error,
        if (raw['truncated'] == true) '查询结果超过显示上限，输出已截断。',
      ],
      exitCode: exitCode.toInt(),
    );
  }
}

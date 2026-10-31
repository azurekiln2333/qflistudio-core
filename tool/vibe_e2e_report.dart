/// Vibe Coding 验收驱动的报告模型。
///
/// 只记录可复算的事实：每个场景的阶段、工具调用、真实退出码和断言结果。
/// 凭据永不进报告：这里只有 `keyPresent` 与 `keyLength`。
library;

import 'dart:convert';
import 'dart:io';

/// 与 [ReportWriter] 一起使用的 schema 版本；字段变动必须加一。
const int kVibeE2eSchema = 1;

/// 单个入口方案的调试凭据；任一变量缺失即视为未配置。
class VibeE2eCredentials {
  const VibeE2eCredentials({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// 从进程环境读取 `QFLI_DEBUG_*`；缺失时返回 null，绝不读取文件。
  static VibeE2eCredentials? fromEnvironment([
    Map<String, String>? environment,
  ]) {
    final env = environment ?? Platform.environment;
    final baseUrl = env['QFLI_DEBUG_BASE_URL']?.trim();
    final apiKey = env['QFLI_DEBUG_API_KEY']?.trim();
    final model = env['QFLI_DEBUG_MODEL']?.trim();
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        apiKey == null ||
        apiKey.isEmpty ||
        model == null ||
        model.isEmpty) {
      return null;
    }
    return VibeE2eCredentials(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 供报告使用的脱敏摘要：只有主机名和长度，没有密钥内容。
  Map<String, Object> redacted({required String protocol}) => {
    'baseHost': Uri.parse(baseUrl).host,
    'model': model,
    'protocol': protocol,
    'keyPresent': true,
    'keyLength': apiKey.length,
  };

  @override
  String toString() =>
      'VibeE2eCredentials(baseHost: ${Uri.parse(baseUrl).host}, '
      'model: $model, key: [REDACTED])';
}

enum VibeE2eStatus { passed, failed, skipped }

extension VibeE2eStatusName on VibeE2eStatus {
  String get value => switch (this) {
    VibeE2eStatus.passed => 'passed',
    VibeE2eStatus.failed => 'failed',
    VibeE2eStatus.skipped => 'skipped',
  };
}

/// 一条断言的真实结果。`detail` 必须是可观察量，例如 `exit 1`。
class VibeE2eAssertion {
  const VibeE2eAssertion({required this.name, required this.ok, this.detail});

  final String name;
  final bool ok;
  final String? detail;

  Map<String, Object?> toJson() => {
    'name': name,
    'ok': ok,
    if (detail != null) 'detail': detail,
  };
}

/// 一次场景运行的完整证据。
class VibeE2eScenarioResult {
  VibeE2eScenarioResult({
    required this.key,
    required this.status,
    required this.phase,
    required this.durationMs,
    this.lastError,
    this.assistantReply,
    this.skipReason,
    this.timeout = false,
    List<Map<String, Object?>>? tools,
    List<VibeE2eAssertion>? assertions,
    Map<String, Object?>? extra,
  }) : tools = tools ?? const [],
       assertions = assertions ?? const [],
       extra = extra ?? const {};

  final String key;
  final VibeE2eStatus status;

  /// 控制器结束时的 `VibePhase.name`。
  final String phase;
  final int durationMs;
  final String? lastError;
  final String? assistantReply;

  /// 仅 `skipped` 时填写：缺少哪个前置条件。
  final String? skipReason;
  final bool timeout;

  /// 真实工具调用，顺序即发生顺序；输出保留尾部。
  final List<Map<String, Object?>> tools;
  final List<VibeE2eAssertion> assertions;

  /// 场景私有证据，例如生成的文件清单与字节数。
  final Map<String, Object?> extra;

  bool get ok => status == VibeE2eStatus.passed;

  Map<String, Object?> toJson() => {
    'key': key,
    'status': status.value,
    'phase': phase,
    'durationMs': durationMs,
    if (lastError != null) 'lastError': lastError,
    if (assistantReply != null) 'assistantReply': assistantReply,
    if (skipReason != null) 'skipReason': skipReason,
    if (timeout) 'timeout': true,
    'tools': tools,
    'assertions': [for (final assertion in assertions) assertion.toJson()],
    if (extra.isNotEmpty) 'extra': extra,
  };
}

/// 顶层报告：生成时间、脱敏环境摘要与全部场景。
class VibeE2eReport {
  VibeE2eReport({
    required this.generatedAt,
    required this.environment,
    required this.scenarios,
    this.driverRevision,
  });

  final DateTime generatedAt;

  /// [VibeE2eCredentials.redacted] 的结果，或只有 `keyPresent: false`。
  final Map<String, Object?> environment;
  final List<VibeE2eScenarioResult> scenarios;

  /// 被测仓库的 HEAD，用于把报告对回代码。
  final String? driverRevision;

  VibeE2eStatus get status {
    if (scenarios.any((scenario) => scenario.status == VibeE2eStatus.failed)) {
      return VibeE2eStatus.failed;
    }
    if (scenarios.every(
      (scenario) => scenario.status == VibeE2eStatus.skipped,
    )) {
      return VibeE2eStatus.skipped;
    }
    return VibeE2eStatus.passed;
  }

  Map<String, Object?> toJson() => {
    'schema': kVibeE2eSchema,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'status': status.value,
    'tool': {
      'driver': 'qfli_studio_core/tool/vibe_e2e.dart',
      if (driverRevision != null) 'revision': driverRevision,
    },
    'environment': environment,
    'scenarios': [for (final scenario in scenarios) scenario.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// 把报告写到磁盘；调用方负责选择仓库外的路径。
abstract final class VibeE2eReportWriter {
  static Future<File> write(File file, VibeE2eReport report) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(report.toPrettyJson(), flush: true);
    return file;
  }

  /// 默认落点：`<scratch>/.artifacts/vibe-e2e/report-<时间戳>.json`。
  static File defaultFile(DateTime at, {Directory? scratch}) {
    final stamp = at
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .split('.')
        .first;
    final root = scratch ?? Directory.systemTemp;
    return File(
      '${root.path}${Platform.pathSeparator}.artifacts'
      '${Platform.pathSeparator}vibe-e2e'
      '${Platform.pathSeparator}report-$stamp.json',
    );
  }
}

/// 读取报告摘要的辅助；运维脚本用它打印表格。
abstract final class VibeE2eReportReader {
  static Map<String, Object?> read(String path) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw FormatException('报告顶层必须是对象', path);
    }
    if (decoded['schema'] != kVibeE2eSchema) {
      throw FormatException('报告 schema 不匹配', path);
    }
    return decoded;
  }
}

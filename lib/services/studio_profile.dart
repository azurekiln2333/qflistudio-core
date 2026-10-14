import 'dart:async';

import 'package:flutter/widgets.dart';

import '../store/project_store.dart';
import '../content/content_repository.dart';
import '../terminal/shell/sandbox_shell_backend.dart';
import 'project_templates.dart';

/// 产品线名称登记表。语言 App 的 UI 标题从这里取，后续新增产品时不必散落硬编码。
abstract final class StudioProductCatalog {
  static const qfliStudioKey = 'qflistudio';
  static const scriptKey = 'script';
  static const rustCoreKey = 'rustcore';
  static const goShiftKey = 'goshift';
  static const jvmxKey = 'jvmx';
  static const webForgeKey = 'webforge';
  static const pyFlowKey = 'pyflow';
  static const forgeKey = 'forge';
  static const dartWingKey = 'dartwing';
  static const sqlabKey = 'sqlab';
  static const jsonKey = 'json';
  static const noteKey = 'note';

  static const qfliStudio = 'QFLIStudio+';
  static const qfliStudioDescription = '多语言编辑器（暂定）';
  static const script = 'QFLIScript';
  static const rustCore = 'QFLIRustCore';
  static const goShift = 'QFLIGoShift';
  static const jvmx = 'QFLIJVMX';
  static const webForge = 'QFLIWebForge';
  static const pyFlow = 'QFLIPyFlow';
  static const forge = 'QFLIForge';
  static const dartWing = 'QFLIDartWing';
  static const sqlab = 'QFLISQLab';
  static const json = 'QFLIJson';
  static const note = 'QFLINote';

  /// The only installable products. Keep this list as the product identity source.
  static const products = <String, String>{
    qfliStudioKey: qfliStudio,
    scriptKey: script,
    rustCoreKey: rustCore,
    goShiftKey: goShift,
    jvmxKey: jvmx,
    webForgeKey: webForge,
    pyFlowKey: pyFlow,
    forgeKey: forge,
    dartWingKey: dartWing,
    sqlabKey: sqlab,
    jsonKey: json,
    noteKey: note,
  };

  static const packagePrefix = 'com.azurekiln.qfli';

  static String packageName(String key) => '$packagePrefix.$key';

  /// Product name by source language/type. This is also used for tutorial labels.
  static const languageProducts = <String, String>{
    'lua': script,
    'javascript': script,
    'typescript': script,
    'shell': script,
    'java': jvmx,
    'web': webForge,
    'python': pyFlow,
    'c': forge,
    'cpp': forge,
    'rust': rustCore,
    'go': goShift,
    'dart': dartWing,
    'sql': sqlab,
    'json': json,
    'markdown': note,
  };

  static String forLanguage(String language) =>
      languageProducts[language.toLowerCase()] ?? qfliStudio;
}

/// 语言专属 App 的「档位」。
///
/// 共享内核默认是全能版（所有模板 + 桌面端原生工具链）。各语言 App 在
/// `main()` 里设置一次 [current]，即可把同一套 UI 收窄成该语言的专用产品：
/// 新建项目只出现本语言的模板，运行按钮交给该语言自己的本地运行时。
///
/// 之所以用可变的静态字段而不是 InheritedWidget：档位在 `runApp` 之前就确定，
/// 全程不变，且要在 `ProjectStore` / `RunnerService` 这类非 Widget 代码里读取。
class StudioProfile {
  const StudioProfile({
    required this.id,
    required this.appTitle,
    required this.templates,
    this.runner,
    this.webPreviewFactory,
    this.toolsPageBuilder,
    this.documentToolBuilder,
    this.terminalCommandDelegate,
    this.contentRepositoryFactory,
    this.editorFileTools = const [],
    this.entryFileNames = const [],
    this.isOffline = false,
    this.offlineOnly = false,
    this.productKey = StudioProductCatalog.qfliStudioKey,
    this.showHomeTabs = true,
    this.runtimeKind = 'unavailable',
    this.runtimeStatus = 'unavailable',
    this.supportedFileExtensions = const [],
  });

  /// 档位标识，同时用于项目元数据里记录「由哪个 App 创建」。
  final String id;

  /// 产品名：窗口标题、任务切换器和应用内顶栏都用它，
  /// 例如联网全能版 `QFLIStudio+`、C/C++ 工具 `QFLIForge`。
  final String appTitle;

  /// Stable product key used by platform identifiers and exported metadata.
  final String productKey;

  /// 新建项目时可选的模板。空列表表示不限制。
  final List<ProjectTemplate> templates;

  /// 本地运行后端。null 表示沿用 [RunnerService] 的默认行为。
  final ProgramRunner? runner;

  /// Product-owned local web preview implementation.
  final Future<WebPreviewSession> Function(String projectPath)?
  webPreviewFactory;

  /// Product-owned tools screen in the existing Functions navigation.
  final Widget Function(ProjectStore store)? toolsPageBuilder;

  /// Optional terminal command hook.
  ///
  /// The shared terminal only knows the common file commands; each language App
  /// injects its own toolchain here (Java: `javac`/`java`; Python: `python`).
  /// When null, unknown commands report an honest "unsupported" message and the
  /// common file commands keep working — other projects are unaffected.
  final TerminalCommandDelegate? terminalCommandDelegate;

  /// Product-owned full-screen editor for one open file (e.g. Markdown
  /// edit/preview workspace). Used for files in [supportedFileExtensions];
  /// null keeps the built-in content tools.
  final Widget Function(DocumentToolRequest request)? documentToolBuilder;

  /// Actions contributed by a language product to the current-file menu.
  final List<EditorFileTool> editorFileTools;

  /// 额外识别的入口文件名（优先于默认列表），例如 `'main.c'`。
  final List<String> entryFileNames;

  /// 是否为不接入社区、认证、云端项目和在线终端的本地语言 App。
  ///
  /// 根工程不设置档位，因此保持联网全能版；各语言 App 显式设置为 true。
  final bool isOffline;

  /// Whether homepage project-scope and language tabs are shown.
  final bool showHomeTabs;

  /// Whether this product is purely offline, so the profile page must hide every
  /// part that needs the network: the login entry, the account summary and the
  /// sync/community actions.
  ///
  /// Distinct from [isOffline], which also swaps the tutorial and example tabs
  /// to their local variants. A product can keep the local content tabs while
  /// still offering an account page, so the two are separate switches. Defaults
  /// to false, which leaves other products' behaviour unchanged.
  final bool offlineOnly;

  /// Concrete execution or preview boundary advertised by this product.
  final String runtimeKind;

  /// `available` is reserved for a tested target-platform path.
  final String runtimeStatus;

  /// File types that the declared runtime handles.
  final List<String> supportedFileExtensions;

  /// Product-owned offline content source. Null keeps the shared catalog.
  ///
  /// When set, the offline tutorial/example tabs read this repository instead of
  /// the shared aggregate assets, so a language app can ship its own curriculum
  /// without editing other languages' content.
  final ContentRepository Function()? contentRepositoryFactory;

  /// 当前生效的档位。为 null 时即全能版。
  static StudioProfile? current;

  /// 该模板在本档位下是否可选。
  bool allowsTemplate(ProjectTemplate template) =>
      templates.isEmpty || templates.contains(template);

  /// 新建对话框的默认模板：档位里第一个真实语言模板。
  ProjectTemplate get defaultTemplate => templates.firstWhere(
    (t) => t != ProjectTemplate.empty,
    orElse: () => ProjectTemplate.empty,
  );

  /// 按档位过滤模板列表。
  List<ProjectTemplate> filterTemplates(Iterable<ProjectTemplate> source) =>
      source.where(allowsTemplate).toList(growable: false);

  /// 按档位过滤语言标签（首页语言筛选芯片）。
  List<String> filterLanguages(Iterable<String> source) {
    if (templates.isEmpty) return source.toList(growable: false);
    final allowed = templates.map((t) => t.language).toSet();
    return source.where(allowed.contains).toList(growable: false);
  }
}

/// The file handed to [StudioProfile.documentToolBuilder].
///
/// The tool edits text in memory; [save] writes it back through the project
/// editor so dirty state, backups and history stay owned by the editor.
class DocumentToolRequest {
  const DocumentToolRequest({
    required this.path,
    required this.name,
    required this.text,
    required this.projectPath,
    required this.readOnly,
    required this.save,
  });

  final String path;
  final String name;
  final String text;
  final String projectPath;
  final bool readOnly;

  /// Applies [text] to the editor and saves; returns an error message or null.
  final Future<String?> Function(String text) save;
}

class EditorFileTool {
  const EditorFileTool({
    required this.id,
    required this.label,
    required this.icon,
    required this.extensions,
    required this.run,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<String> extensions;
  final Future<EditorFileToolResult> Function(String file, String projectPath)
  run;
}

class EditorFileToolResult {
  const EditorFileToolResult({required this.success, required this.message});

  final bool success;
  final String message;
}

abstract interface class WebPreviewSession {
  String get url;
  Stream<String> get debugStream;
  Future<void> stop();
}

/// 当前档位下可选的模板。未设置档位时即全部模板。
List<ProjectTemplate> availableTemplates() =>
    StudioProfile.current?.filterTemplates(ProjectTemplate.values) ??
    ProjectTemplate.values;

/// 当前档位新建对话框的默认模板。
ProjectTemplate defaultTemplate() =>
    StudioProfile.current?.defaultTemplate ?? ProjectTemplate.empty;

/// 语言 App 提供的本地运行后端。
///
/// 实现方只需负责「把源码跑起来并吐出输出行」，终端面板的呈现交给内核。
abstract interface class ProgramRunner {
  /// 运行 [entryFile]。返回 null 表示本后端不接管这种文件，交回默认逻辑。
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  });
}

/// 「程序根本没跑起来」时应该用的退出码。
///
/// 终端面板会把非 0 一律渲染成「（运行结束，退出码 N）」
/// （见 `lib/editor/terminal_pane.dart`）。所以只要后端没起来，就**不能**回 1：
/// 「运行结束，退出码 1」读起来是「程序自己跑完、报错退出 1」，而真相是
/// 程序一行都没执行。真机上真实误导过人一次（Python 版后端没打进 HAP 时）。
///
/// 借 shell 的约定 127 = command not found。任何正常程序都不会主动返回它，
/// 于是终端上的两句话一眼就能分开：
///   - 退出码 127 → 是 App / 后端的问题，程序没跑；
///   - 其它退出码 → 程序真的跑了，这是它自己的退出码。
///
/// 所有语言 App 的「后端不可用 / 运行前失败」分支都必须用它。
const int kProgramNotRunExitCode = 127;

/// 一次本地运行的输出。stdout / stderr 均为按行切分的字符串流。
class ProgramRunResult {
  const ProgramRunResult({
    required this.title,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.cancel,
  });

  /// 终端首行显示的标题，例如 `运行 main.c（本地解释器）`。
  final String title;

  final Stream<String> stdout;
  final Stream<String> stderr;
  final Future<int> exitCode;

  /// Cancels an external or native run when the editor is disposed.
  final Future<void> Function()? cancel;
}

import 'dart:math';

import 'package:path/path.dart' as p;

import '../config/api_config.dart';
import 'cloud_project.dart';

/// 一个已注册到 QFLIStudioN 的项目。
class Project {
  Project({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.lastOpenedAt,
    this.cloudId,
    this.cloudOrigin,
    this.cloudAccountId,
    this.favorite = false,
    this.language = '',
    this.type = '',
    this.deviceHostId,
    this.deviceSessionId,
    this.deviceRoot,
    this.placeholder = false,
    this.filesPulled = false,
  });

  final String id;
  String name;
  String path;
  DateTime createdAt;
  DateTime lastOpenedAt;

  /// 云端项目在服务器上的 proj_ ID；本地项目为 null。
  String? cloudId;

  /// Explicit owner for scoped cloud data. Legacy rows without one stay intact.
  String? cloudOrigin;
  String? cloudAccountId;

  bool belongsToCloudScope(CloudProjectScope scope) =>
      isCloud &&
      cloudOrigin == scope.origin &&
      cloudAccountId == scope.accountId;

  /// 是否已收藏。
  bool favorite;

  /// 语言标注：优先来自项目配置文件 .qfli/project.json；
  /// 创建时来自模板，添加已有文件夹时按扩展名检测并写入配置。
  String language;

  /// Stable source-language discriminator, for example `cpp` or `python`.
  String type;

  bool get isCloud => cloudId != null;

  // -------------------------------------------------------------------------
  // 设备同步附加字段（追加块，不改动上面的既有字段与顺序）
  //
  // 这几个字段只为「从配对电脑拉下来的项目」服务。普通本地项目与云端项目
  // 这些值全为 null / false，行为与之前一致。
  // -------------------------------------------------------------------------

  /// 来源电脑的 agent id。为 null 表示这不是设备项目。
  String? deviceHostId;

  /// 来源会话 id。占位项目由会话生成，换成真实项目后仍保留这个值。
  String? deviceSessionId;

  /// 电脑上该项目的绝对路径。同步时作为远端根目录。
  String? deviceRoot;

  /// 占位项目：只为承载一个会话而存在，用户尚未拉取文件。
  bool placeholder;

  /// 用户已确认并拉取过项目文件。占位项目删除时的判定依据。
  bool filesPulled;

  /// 是否为设备项目（来自配对电脑）。
  bool get isDevice => deviceHostId != null;

  static String _newId() {
    final rnd = Random();
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$stamp-${rnd.nextInt(36 * 36 * 36).toRadixString(36)}';
  }

  factory Project.create({
    required String name,
    required String path,
    String? cloudId,
    String? cloudOrigin,
    String? cloudAccountId,
    bool favorite = false,
    String language = '',
    String type = '',
  }) {
    final now = DateTime.now();
    return Project(
      id: _newId(),
      name: name,
      path: path,
      createdAt: now,
      lastOpenedAt: now,
      cloudId: cloudId,
      cloudOrigin: cloudOrigin ?? (cloudId == null ? null : ApiConfig.origin),
      cloudAccountId: cloudAccountId,
      favorite: favorite,
      language: language,
      type: type,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'createdAt': createdAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    if (cloudId != null) 'cloudId': cloudId,
    if (cloudId != null) 'cloudOrigin': cloudOrigin ?? ApiConfig.origin,
    if (cloudAccountId != null) 'cloudAccountId': cloudAccountId,
    'favorite': favorite,
    'language': language,
    'type': type,
    // 设备字段仅在有时写出，旧版读到未知键会忽略。
    if (deviceHostId != null) 'deviceHostId': deviceHostId,
    if (deviceSessionId != null) 'deviceSessionId': deviceSessionId,
    if (deviceRoot != null) 'deviceRoot': deviceRoot,
    if (placeholder) 'placeholder': true,
    if (filesPulled) 'filesPulled': true,
  };

  static Project fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    return Project(
      id: json['id'] as String? ?? _newId(),
      name: (json['name'] as String?) ?? p.basename(path),
      path: path,
      createdAt: created,
      lastOpenedAt:
          DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ?? created,
      // 旧自定义服务器的 ID 不能直接拿到官方服务使用。
      // 来源不明的旧镜像保留为本地项目，用户可重新刷新导入官方云目录。
      cloudId: ApiConfig.ownsSession(json['cloudOrigin'] as String?)
          ? json['cloudId'] as String?
          : null,
      cloudOrigin: json['cloudOrigin'] as String?,
      cloudAccountId: json['cloudAccountId'] as String?,
      favorite: json['favorite'] as bool? ?? false,
      language: json['language'] as String? ?? '',
      type: json['type'] as String? ?? '',
      deviceHostId: json['deviceHostId'] as String?,
      deviceSessionId: json['deviceSessionId'] as String?,
      deviceRoot: json['deviceRoot'] as String?,
      placeholder: json['placeholder'] as bool? ?? false,
      filesPulled: json['filesPulled'] as bool? ?? false,
    );
  }
}

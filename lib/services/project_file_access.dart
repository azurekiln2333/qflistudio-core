// 项目文件读写的唯一入口。
//
// 外部文件夹里的文件受系统协调约束：写盘要过 NSFileCoordinator，读占位文件
// 要先下载。这两件事只有原生能做，所以这里按路径归属分流。
//
// 其它路径保持 `dart:io`：应用沙箱内的文件不需要协调，错误语义也与现有代码
// 一致。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'external_folder_service.dart';

abstract final class ProjectFileAccess {
  static bool isExternal(String path) => ExternalFolderService.isExternal(path);

  /// 读原始字节。外部根走协调读取，iCloud 占位先下载。
  static Future<Uint8List> readBytes(String path) async {
    if (isExternal(path)) return ExternalFolderService.read(path);
    return File(path).readAsBytes();
  }

  /// 读文本。解码宽松，坏字节不抛出。
  static Future<String> readString(String path) async =>
      utf8.decode(await readBytes(path), allowMalformed: true);

  /// 写原始字节。外部根走协调写入。
  static Future<void> writeBytes(String path, List<int> bytes) async {
    if (isExternal(path)) {
      await ExternalFolderService.write(path, Uint8List.fromList(bytes));
      return;
    }
    await File(path).writeAsBytes(bytes, flush: true);
  }

  static Future<void> writeString(String path, String text) =>
      writeBytes(path, utf8.encode(text));

  /// 列目录。外部根走原生，占位条目也会返回。
  static Future<List<ExternalFolderEntry>> listEntries(String directoryPath) =>
      ExternalFolderService.list(directoryPath);

  /// 外部根禁止由 QFLI 删除。第一版只允许读取与改写。
  static Future<void> delete(String path) async {
    if (isExternal(path)) {
      throw const FileSystemException('外部文件夹不支持由 QFLI 删除文件');
    }
    await File(path).delete();
  }
}

import 'package:flutter/services.dart';

/// 系统分享：鸿蒙走 Share Kit 系统分享面板；
/// 桌面端（Windows 等）没有系统分享 UI，调用方回退到剪贴板复制。
abstract final class ShareService {
  static const MethodChannel _channel = MethodChannel('qflistudio/platform');

  /// Hands a retained ZIP to the native file-share UI, never text sharing.
  /// True means handed off, not delivered. The caller retains the archive even
  /// when the sheet is dismissed. Unavailable transports return false; real
  /// failures stay errors so callers do not report a successful share.
  static Future<bool> shareFile({
    required String path,
    required String title,
    String mimeType = 'application/zip',
  }) async {
    try {
      return await _channel.invokeMethod<bool>('shareFile', {
            'path': path,
            'title': title,
            'mimeType': mimeType,
          }) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      if (error.code == 'UNSUPPORTED' || error.code == 'SHARE_UNAVAILABLE') {
        return false;
      }
      rethrow;
    }
  }

  /// 返回 true 表示已调起系统分享面板；false 表示平台不支持（回退剪贴板）。
  static Future<bool> shareText({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod('shareText', {'title': title, 'text': text});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

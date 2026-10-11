import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _viewType = 'qflistudio/huawei_quick_login';

class HuaweiQuickLoginView extends StatefulWidget {
  const HuaweiQuickLoginView({
    super.key,
    required this.agreementAccepted,
    required this.onAuthorizationCode,
    required this.onError,
  });

  final bool agreementAccepted;
  final ValueChanged<String> onAuthorizationCode;
  final ValueChanged<String> onError;

  @override
  State<HuaweiQuickLoginView> createState() => _HuaweiQuickLoginViewState();
}

class _HuaweiQuickLoginViewState extends State<HuaweiQuickLoginView> {
  MethodChannel? _channel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_updateTheme());
  }

  @override
  void didUpdateWidget(covariant HuaweiQuickLoginView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agreementAccepted != widget.agreementAccepted) {
      unawaited(_updateAgreementStatus());
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onPlatformViewCreated(int viewId) async {
    final channel = MethodChannel('$_viewType$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'loginSuccess':
          final code = call.arguments;
          if (code is String && code.isNotEmpty) {
            widget.onAuthorizationCode(code);
          } else {
            widget.onError('华为账号未返回授权码');
          }
          break;
        case 'loginError':
          final message = call.arguments;
          widget.onError(message is String ? message : '华为账号一键登录失败');
          break;
      }
    });
    await _updateTheme();
    if (mounted) await _updateAgreementStatus();
  }

  Map<String, int> _themeColors() {
    final scheme = Theme.of(context).colorScheme;
    final disabledBackground = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.12),
      scheme.surface,
    );
    return {
      'background': scheme.primary.toARGB32(),
      'foreground': scheme.onPrimary.toARGB32(),
      'disabledBackground': disabledBackground.toARGB32(),
      'disabledForeground': Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.38),
        disabledBackground,
      ).toARGB32(),
    };
  }

  Future<void> _updateTheme() async {
    final channel = _channel;
    if (channel == null || !mounted) return;
    try {
      await channel.invokeMethod<void>('setTheme', _themeColors());
    } on PlatformException catch (e) {
      if (mounted) widget.onError('更新按钮颜色失败：${e.message ?? e.code}');
    } on MissingPluginException {
      if (mounted) widget.onError('华为一键登录组件未加载');
    }
  }

  Future<void> _updateAgreementStatus() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(
        'setAgreementAccepted',
        widget.agreementAccepted,
      );
    } on PlatformException catch (e) {
      widget.onError('更新协议状态失败：${e.message ?? e.code}');
    } on MissingPluginException {
      widget.onError('华为一键登录组件未加载');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.ohos) {
      return const SizedBox.shrink();
    }
    return OhosView(
      viewType: _viewType,
      creationParams: _themeColors(),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}

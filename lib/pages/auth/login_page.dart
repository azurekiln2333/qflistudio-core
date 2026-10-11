import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/agreement_config.dart';
import '../../community/models.dart';
import '../../services/api_client.dart';
import '../../store/auth_store.dart';
import 'account_login_page.dart';
import 'agreement_page.dart';
import 'huawei_quick_login_view.dart';
import 'second_factor_dialog.dart';

/// Huawei one-tap login entry page.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});

  final AuthStore auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _huaweiChannel = MethodChannel('qflistudio/huawei_account');

  String? _anonymousPhone;
  String? _phoneError;
  String? _loginError;
  bool _loadingPhone = true;
  bool _agreementAccepted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAnonymousPhone());
  }

  Future<void> _loadAnonymousPhone() async {
    setState(() {
      _loadingPhone = true;
      _phoneError = null;
    });
    try {
      final phone = await _huaweiChannel.invokeMethod<String>(
        'getAnonymousPhone',
      );
      if (!mounted) return;
      setState(() {
        _anonymousPhone = phone == null || phone.isEmpty
            ? null
            : _maskPhone(phone);
      });
    } on MissingPluginException {
      if (mounted) {
        setState(() => _phoneError = '华为手机号仅支持鸿蒙设备读取');
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _phoneError = '读取华为手机号失败：${e.message ?? e.code}');
      }
    } finally {
      if (mounted) setState(() => _loadingPhone = false);
    }
  }

  String _maskPhone(String phone) {
    if (phone.contains('*')) return phone;

    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 13 && digits.startsWith('86')) {
      digits = digits.substring(2);
    }
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}****${digits.substring(7)}';
    }

    // Never render a value that does not match a recognizable masked number.
    return '华为账号手机号已获取';
  }

  void _openAgreement(String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgreementPage(title: title, url: url),
      ),
    );
  }

  Widget _agreementLink(String title, String url) {
    return TextButton(
      onPressed: () => _openAgreement(title, url),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(title),
    );
  }

  Future<void> _completeHuaweiLogin(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _loginError = null;
    });
    try {
      ({String token, CommunityUser user})? result;
      try {
        final login = await ApiClient.instance.huaweiLogin(code);
        if (login.bindingId != null) {
          if (!mounted) return;
          final signedIn = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => AccountLoginPage(
              auth: widget.auth,
              bindingId: login.bindingId,
              phoneAvailable: login.phoneAvailable,
            )),
          );
          if (signedIn == true && mounted) Navigator.of(context).pop(true);
          return;
        }
        result = (token: login.token!, user: login.user!);
      } on ApiException catch (e) {
        final challengeId = e.details['challengeId'];
        final factor = e.details['factor'];
        if (e.statusCode != 428 || challengeId is! String || factor is! String) {
          rethrow;
        }
        if (!mounted) return;
        final verificationCode = await showDialog<String>(
          context: context,
          builder: (_) => SecondFactorDialog(
            factor: factor,
            emailMasked: e.details['emailMasked'] as String?,
          ),
        );
        if (verificationCode == null || !mounted) return;
        result = await ApiClient.instance.completeHuaweiLogin(
          challengeId,
          verificationCode,
        );
      }
      await widget.auth.signIn(result.token, result.user);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loginError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showHuaweiLoginError(String message) {
    if (mounted) setState(() => _loginError = message);
  }

  Future<void> _openOtherLogin() async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AccountLoginPage(auth: widget.auth)),
    );
    if (signedIn == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOhos = defaultTargetPlatform == TargetPlatform.ohos;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: 80,
                      height: 80,
                      cacheWidth: (80 * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '欢迎回到 QFLIStudio+',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 42,
                    child: _loadingPhone
                        ? const Center(
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _anonymousPhone ?? '未获取到脱敏手机号',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_anonymousPhone == null)
                                IconButton(
                                  tooltip: '重新读取手机号',
                                  onPressed: _busy ? null : _loadAnonymousPhone,
                                  icon: const Icon(Icons.refresh, size: 20),
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '设备展示号码（仅供参考）',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_phoneError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _phoneError!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 26),
                  if (isOhos)
                    SizedBox(
                      height: 52,
                      child: HuaweiQuickLoginView(
                        agreementAccepted: _agreementAccepted,
                        onAuthorizationCode: _completeHuaweiLogin,
                        onError: _showHuaweiLoginError,
                      ),
                    )
                  else
                    Text(
                      '华为账号一键登录仅支持鸿蒙设备',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox.adaptive(
                        value: _agreementAccepted,
                        onChanged: _busy
                            ? null
                            : (accepted) => setState(
                                () => _agreementAccepted = accepted ?? false,
                              ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('我已阅读并同意'),
                              _agreementLink('用户协议', userAgreementUrl),
                              const Text('、'),
                              _agreementLink('隐私政策', privacyPolicyUrl),
                              const Text('及'),
                              _agreementLink(
                                '华为账号用户认证协议',
                                huaweiAuthenticationAgreementUrl,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  TextButton.icon(
                    onPressed: _busy ? null : _openOtherLogin,
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('其他方式登录'),
                  ),
                  if (_loginError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _loginError!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 14),
                    const Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

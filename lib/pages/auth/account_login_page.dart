import 'package:flutter/material.dart';

import '../../community/models.dart';
import '../../services/api_client.dart';
import '../../store/auth_store.dart';
import 'register_page.dart';
import 'captcha_dialog.dart';
import 'second_factor_dialog.dart';

class AccountLoginPage extends StatefulWidget {
  const AccountLoginPage({super.key, required this.auth, this.bindingId, this.phoneAvailable = false});

  final AuthStore auth;
  final String? bindingId;
  final bool phoneAvailable;

  @override
  State<AccountLoginPage> createState() => _AccountLoginPageState();
}

class _AccountLoginPageState extends State<AccountLoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _factor;
  String? _emailMasked;
  String? _verificationCode;
  bool _requirementsChecked = false;
  bool _needsCaptcha = false;
  String? _captchaId;
  String? _captchaCode;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _resetVerification(String _) {
    setState(() {
      _requirementsChecked = false;
      _factor = null;
      _emailMasked = null;
      _verificationCode = null;
      _needsCaptcha = false;
      _captchaId = null;
      _captchaCode = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    if (username.isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_requirementsChecked) {
        final requirements = await ApiClient.instance.loginRequirements(
          username,
          _password.text,
        );
        if (!mounted) return;
        _factor = requirements.factor;
        _emailMasked = requirements.emailMasked;
        _needsCaptcha = requirements.captchaRequired;
        _requirementsChecked = true;
      }
      if (_factor != null && _verificationCode == null) {
        final code = await showDialog<String>(
          context: context,
          builder: (_) =>
              SecondFactorDialog(factor: _factor!, emailMasked: _emailMasked),
        );
        if (!mounted || code == null) return;
        _verificationCode = code;
      }
      if (_needsCaptcha) {
        final captcha = await showDialog<({String id, String code})>(
          context: context,
          builder: (_) => const CaptchaDialog(),
        );
        if (!mounted || captcha == null) return;
        _captchaId = captcha.id;
        _captchaCode = captcha.code;
      }
      final result = widget.bindingId == null
          ? await ApiClient.instance.login(
              username, _password.text,
              emailCode: _factor == 'email' ? _verificationCode : null,
              totpCode: _factor == 'totp' ? _verificationCode : null,
              captchaId: _captchaId, captchaCode: _captchaCode,
            )
          : await ApiClient.instance.bindHuaweiAccount(
              widget.bindingId!, username, _password.text,
              emailCode: _factor == 'email' ? _verificationCode : null,
              totpCode: _factor == 'totp' ? _verificationCode : null,
              captchaId: _captchaId, captchaCode: _captchaCode,
            );
      await widget.auth.signIn(result.token, result.user);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        final errorKey = e.details['errorKey'];
        setState(() {
          _error = e.message;
          if (e.details['factor'] is String) {
            _factor = e.details['factor'] as String;
            _emailMasked = e.details['emailMasked'] as String?;
            _verificationCode = null;
          }
          if (errorKey is String && errorKey.startsWith('captcha.')) {
            _needsCaptcha = true;
          }
          if (errorKey is String &&
              (errorKey.startsWith('auth.totp.') ||
                  errorKey.startsWith('email_code.') ||
                  errorKey.startsWith('auth.mfa.'))) {
            _verificationCode = null;
          }
          if (errorKey == 'auth.invalid_credentials') {
            _requirementsChecked = false;
            _verificationCode = null;
          }
          if (errorKey == 'email_code.expired') {
            _requirementsChecked = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skipBinding() async {
    if (_busy || widget.bindingId == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      ({String token, CommunityUser user}) result;
      try {
        result = await ApiClient.instance.skipHuaweiBinding(widget.bindingId!);
      } on ApiException catch (e) {
        final challengeId = e.details['challengeId'];
        final factor = e.details['factor'];
        if (e.statusCode != 428 || challengeId is! String || factor is! String) rethrow;
        if (!mounted) return;
        final code = await showDialog<String>(
          context: context,
          builder: (_) => SecondFactorDialog(factor: factor, emailMasked: e.details['emailMasked'] as String?),
        );
        if (code == null || !mounted) return;
        result = await ApiClient.instance.completeHuaweiLogin(challengeId, code);
      }
      await widget.auth.signIn(result.token, result.user);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRegister() async {
    final username = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const RegisterPage()));
    if (username != null && mounted) {
      _username.text = username;
      _password.clear();
      _resetVerification('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.bindingId == null ? '账号密码登录' : '绑定已有账号')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.bindingId == null ? '云端账号登录' : '绑定已有账号',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (widget.bindingId != null) ...[
                    Text(
                      widget.phoneAvailable
                          ? '华为手机号未匹配到已验证的已有账号。验证账号后即可绑定并登录。'
                          : '华为未提供可匹配的完整手机号。验证已有账号后即可绑定并登录。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                  TextField(
                    controller: _username,
                    onChanged: _resetVerification,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    onChanged: _resetVerification,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? '处理中…' : widget.bindingId == null ? '登录' : '绑定并登录'),
                  ),
                  if (widget.bindingId == null)
                    TextButton(
                      onPressed: _busy ? null : _openRegister,
                      child: const Text('没有账号？注册'),
                    )
                  else
                    TextButton(
                      onPressed: _busy ? null : _skipBinding,
                      child: const Text('跳过，创建新账号'),
                    ),
                  if (_busy) ...[
                    const SizedBox(height: 8),
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

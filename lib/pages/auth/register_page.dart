import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import 'gateway_captcha_field.dart';

/// 注册页。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _emailCode = TextEditingController();
  final _nickname = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _message;
  String? _registeredUsername;
  bool _sendingCode = false;
  int _codeCooldown = 0;
  Timer? _codeTimer;
  bool _needsCaptcha = false;
  final _captchaKey = GlobalKey<GatewayCaptchaFieldState>();
  String? _captchaId;
  String? _captchaCode;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _emailCode.dispose();
    _codeTimer?.cancel();
    _nickname.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_sendingCode || _codeCooldown > 0) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    setState(() {
      _sendingCode = true;
      _error = null;
      _message = null;
    });
    try {
      final message = await ApiClient.instance.sendRegistrationCode(email);
      if (!mounted) return;
      setState(() {
        _message = message;
        _codeCooldown = 60;
      });
      _codeTimer?.cancel();
      _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _codeCooldown--);
        if (_codeCooldown == 0) timer.cancel();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _registeredUsername != null) return;
    final username = _username.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(username)) {
      setState(() => _error = '用户名需为 3-24 位字母、数字或下划线');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '密码至少 6 位');
      return;
    }
    if (password != _password2.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(_emailCode.text.trim())) {
      setState(() => _error = '请输入邮箱中的 6 位验证码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final message = await ApiClient.instance.register(
        username: username,
        email: email,
        password: password,
        emailCode: _emailCode.text.trim(),
        nickname: _nickname.text.trim(),
        captchaId: _captchaId,
        captchaCode: _captchaCode,
      );
      if (mounted) {
        setState(() {
          _registeredUsername = username;
          _message = message?.trim().isNotEmpty == true ? message : '注册请求已提交。';
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        final key = e.details['errorKey'];
        setState(() {
          _error = e.message;
          if (key is String && key.startsWith('captcha.')) _needsCaptcha = true;
        });
        if (_needsCaptcha) unawaited(_captchaKey.currentState?.refresh());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canEdit = !_busy && !_sendingCode && _registeredUsername == null;
    return Scaffold(
      appBar: AppBar(title: const Text('注册')),
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
                  TextField(
                    controller: _username,
                    enabled: canEdit,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.newUsername],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      helperText: '3-24 位字母、数字或下划线',
                      helperMaxLines: 2,
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    enabled: canEdit,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCode,
                    enabled: canEdit,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '邮箱验证码',
                      prefixIcon: Icon(Icons.mark_email_read_outlined),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: canEdit && _codeCooldown == 0
                          ? _sendCode
                          : null,
                      icon: const Icon(Icons.send_outlined, size: 18),
                      label: Text(
                        _sendingCode
                            ? '发送中'
                            : _codeCooldown > 0
                            ? '${_codeCooldown}s'
                            : '发送验证码',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nickname,
                    enabled: canEdit,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '昵称（可选）',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    enabled: canEdit,
                    autofillHints: const [AutofillHints.newPassword],
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      helperText: '至少 6 位',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password2,
                    enabled: canEdit,
                    textInputAction: TextInputAction.done,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '确认密码',
                      prefixIcon: Icon(Icons.lock_reset_outlined),
                    ),
                  ),
                  if (_needsCaptcha) ...[
                    const SizedBox(height: 16),
                    GatewayCaptchaField(
                      key: _captchaKey,
                      enabled: canEdit,
                      onChanged: (id, code) {
                        _captchaId = id;
                        _captchaCode = code;
                      },
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.primary),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy || _sendingCode
                        ? null
                        : _registeredUsername == null
                        ? _submit
                        : () => Navigator.of(context).pop(_registeredUsername),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _busy
                          ? '注册中…'
                          : _registeredUsername == null
                          ? '注册'
                          : '返回登录',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

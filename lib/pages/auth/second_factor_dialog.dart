import 'package:flutter/material.dart';

class SecondFactorDialog extends StatefulWidget {
  const SecondFactorDialog({super.key, required this.factor, this.emailMasked});

  final String factor;
  final String? emailMasked;

  @override
  State<SecondFactorDialog> createState() => _SecondFactorDialogState();
}

class _SecondFactorDialogState extends State<SecondFactorDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isNotEmpty) Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.factor == 'totp' ? '验证器验证' : '邮箱验证'),
    content: SingleChildScrollView(
      child: TextField(
        controller: _code,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.factor == 'totp' ? '动态验证码或恢复码' : '邮箱验证码',
          helperText: widget.emailMasked,
          helperMaxLines: 2,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('验证')),
    ],
  );
}

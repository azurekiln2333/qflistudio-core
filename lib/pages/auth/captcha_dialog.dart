import 'package:flutter/material.dart';

import 'gateway_captcha_field.dart';

class CaptchaDialog extends StatefulWidget {
  const CaptchaDialog({super.key});

  @override
  State<CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<CaptchaDialog> {
  String? _id;
  String? _code;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('图形验证'),
    content: SingleChildScrollView(
      child: GatewayCaptchaField(
        enabled: true,
        onChanged: (id, code) => setState(() {
          _id = id;
          _code = code;
        }),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _id != null && (_code?.isNotEmpty ?? false)
            ? () => Navigator.of(context).pop((id: _id!, code: _code!))
            : null,
        child: const Text('验证'),
      ),
    ],
  );
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';

class GatewayCaptchaField extends StatefulWidget {
  const GatewayCaptchaField({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final void Function(String? id, String? code) onChanged;

  @override
  State<GatewayCaptchaField> createState() => GatewayCaptchaFieldState();
}

class GatewayCaptchaFieldState extends State<GatewayCaptchaField> {
  final _code = TextEditingController();
  String? _id;
  Uint8List? _image;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(refresh());
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _id = null;
      _image = null;
      _error = null;
    });
    _code.clear();
    widget.onChanged(null, null);
    try {
      final captcha = await ApiClient.instance.captcha();
      final data = UriData.parse(captcha.image);
      if (data.mimeType != 'image/png') throw const FormatException();
      final bytes = data.contentAsBytes();
      if (!mounted) return;
      setState(() {
        _id = captcha.id;
        _image = bytes;
      });
      widget.onChanged(_id, null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FormatException {
      if (mounted) setState(() => _error = '验证码图片加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _code,
        enabled: widget.enabled && _id != null,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (value) => widget.onChanged(_id, value.trim()),
        decoration: const InputDecoration(
          labelText: '图形验证码',
          prefixIcon: Icon(Icons.verified_user_outlined),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Flexible(
            child: SizedBox(
              width: 150,
              height: 53,
              child: _loading
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _image == null
                  ? const SizedBox.shrink()
                  : Image.memory(_image!, fit: BoxFit.contain),
            ),
          ),
          IconButton(
            tooltip: '刷新验证码',
            onPressed: widget.enabled && !_loading ? refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

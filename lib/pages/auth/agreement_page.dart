import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  static const _channel = MethodChannel('qflistudio/platform');
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted || _opening) return;
    final uri = Uri.tryParse(widget.url.trim());
    if (widget.url.trim().isEmpty) {
      setState(() => _error = '协议暂未发布');
      return;
    }
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _error = '协议地址无效');
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.ohos) {
      setState(() => _error = '当前平台暂不支持应用内协议阅读');
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await _channel.invokeMethod<void>('openAgreement', {
        'title': widget.title,
        'url': uri.toString(),
      });
      if (mounted) Navigator.of(context).pop();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? '协议加载失败');
    } on MissingPluginException {
      if (mounted) setState(() => _error = '协议阅读组件未加载，请更新应用');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _opening ? null : _open,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}

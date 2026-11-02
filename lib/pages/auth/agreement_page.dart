import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用内协议阅读页。
///
/// 鸿蒙宿主通过 `qflistudio/platform.openAgreement` 打开原生 ArkWeb 页面
/// （`pages/AgreementReader`）；其余平台没有该通道时不再给出一条死路，
/// 而是显示可复制的地址，让用户自己去浏览器打开，并说明原因。
///
/// 整改任务书 §3-W3：设置页里的“用户协议”“隐私政策”入口从这里打开。
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

  /// 宿主没有应用内阅读器时显示的可复制地址；有阅读器时为 null。
  String? _manualUrl;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted || _opening) return;
    final url = widget.url.trim();
    if (url.isEmpty) {
      setState(() => _error = '协议暂未发布');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _error = '协议地址无效');
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.ohos) {
      setState(() {
        _error = null;
        _manualUrl = uri.toString();
      });
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
      _manualUrl = null;
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
      // 旧版宿主没有实现 openAgreement：退回可复制地址，不让用户卡住。
      if (mounted) {
        setState(() {
          _error = null;
          _manualUrl = uri.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _copy() async {
    final url = _manualUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('协议地址已复制')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_opening) const CircularProgressIndicator(),
              if (!_opening && _error != null)
                Text(_error!, textAlign: TextAlign.center),
              if (!_opening && _manualUrl != null) ...[
                const Icon(Icons.open_in_new, size: 28),
                const SizedBox(height: 12),
                Text(
                  '当前平台没有应用内协议阅读器。\n请复制下面的地址，在浏览器中打开。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _manualUrl!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (!_opening) ...[
                const SizedBox(height: 16),
                if (_manualUrl != null)
                  FilledButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.content_copy_outlined, size: 18),
                    label: const Text('复制地址'),
                  ),
                if (_manualUrl == null)
                  TextButton.icon(
                    onPressed: _open,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新加载'),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

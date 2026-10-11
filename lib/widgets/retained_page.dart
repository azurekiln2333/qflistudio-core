import 'package:flutter/material.dart';

/// Retain visited pager content and isolate its painting from adjacent pages.
class RetainedPage extends StatefulWidget {
  const RetainedPage({super.key, required this.child});

  final Widget child;

  @override
  State<RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Mirrors the two existing EGYSHOW sections without duplicating their data.
class WebsiteSection extends StatefulWidget {
  const WebsiteSection({super.key, required this.kind, required this.ar});
  final String kind;
  final bool ar;
  @override
  State<WebsiteSection> createState() => _WebsiteSectionState();
}
class _WebsiteSectionState extends State<WebsiteSection> {
  late WebViewController viewer;
  bool failed = false;
  int progress = 0;
  Uri get uri => Uri.parse(widget.kind == 'matches'
    ? 'https://egyshow.com/matches/'
    : 'https://egyshow.com/ar/youtube');
  @override
  void initState() {
    super.initState();
    viewer = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0A0D))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (v) { if (mounted) setState(() => progress = v); },
        onPageStarted: (_) { if (mounted) setState(() => failed = false); },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) setState(() => failed = true);
        },
      ))
      ..loadRequest(uri);
  }
  @override
  void didUpdateWidget(covariant WebsiteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind || oldWidget.ar != widget.ar) {
      viewer.loadRequest(uri);
    }
  }
  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: WebViewWidget(controller: viewer)),
    if (progress < 100) const Positioned(top: 0, left: 0, right: 0,
      child: LinearProgressIndicator(color: Color(0xFFE50914), minHeight: 2)),
    if (failed) Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('تعذر تحميل القسم'),
      const SizedBox(height: 12),
      ElevatedButton.icon(onPressed: () { setState(() => failed = false); viewer.reload(); },
        icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
    ])),
  ]);
}

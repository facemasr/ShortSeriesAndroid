import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Only the video screen embeds EGYSHOW's existing player.
/// Catalog, search, accounts, and episode listings remain native Flutter.
class EgyshowSitePlayer extends StatefulWidget {
  const EgyshowSitePlayer({
    super.key,
    required this.type,
    required this.id,
    required this.mediaId,
    required this.title,
    this.token,
    this.reelMode = false,
    this.onFailure,
  });
  final String type;
  final int id;
  final int mediaId;
  final String title;
  final String? token;
  final bool reelMode;
  final VoidCallback? onFailure;

  @override
  State<EgyshowSitePlayer> createState() => _EgyshowSitePlayerState();
}

class _EgyshowSitePlayerState extends State<EgyshowSitePlayer>
    with WidgetsBindingObserver {
  late final WebViewController controller;
  int progress = 0;
  bool failed = false;

  Uri get url => Uri.https('egyshow.com', '/watch', {
    'target_type': widget.type,
    'target_id': widget.id.toString(),
    'media_id': widget.mediaId.toString(),
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() { failed = false; progress = 0; });
        },
        onPageFinished: (_) async {
          if (mounted) setState(() => progress = 100);
          // Synchronize a signed-in account only with our own first-party page.
          final token = widget.token;
          if (token != null && token.isNotEmpty) {
            try {
              await controller.runJavaScript(
                "localStorage.setItem('egyshow.token', " + jsonEncode(token) + ");"
              );
            } catch (_) {}
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => failed = true);
            widget.onFailure?.call();
          }
        },
        onNavigationRequest: (request) {
          // Never turn advertisements or external links into a top-level app page.
          // Subresource requests (including ads/media) remain untouched.
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (!request.isMainFrame) return NavigationDecision.navigate;
          if (uri.host == 'egyshow.com' || uri.host == 'www.egyshow.com') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ));
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    controller.loadRequest(url);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Pause the web video without touching or bypassing its ad controller.
      controller.runJavaScript(
        "try{document.querySelector('video')?.pause();}catch(e){}"
      ).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.runJavaScript(
      "try{document.querySelector('video')?.pause();}catch(e){}"
    ).catchError((Object _) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Colors.black, child: Stack(children: [
      Positioned.fill(child: WebViewWidget(controller: controller)),
      if (progress < 100 && !failed)
        const Positioned(left: 0, top: 0, right: 0,
          child: LinearProgressIndicator(
            color: Color(0xFFE50914), minHeight: 2)),
      if (failed)
        Center(child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xEE16161A),
            borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_outlined,
              color: Colors.orangeAccent, size: 42),
            const SizedBox(height: 12),
            const Text('تعذر تحميل مشغل EGYSHOW',
              textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () { setState(() => failed = false); controller.reload(); },
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ]))),
    ]));
  }
}

class NativePlayer extends StatelessWidget {
  const NativePlayer({
    super.key,
    required this.type,
    required this.id,
    required this.mediaId,
    required this.title,
    this.token,
  });
  final String type;
  final int id;
  final int mediaId;
  final String title;
  final String? token;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      backgroundColor: Colors.black,
    ),
    body: SafeArea(child: EgyshowSitePlayer(
      type: type, id: id, mediaId: mediaId,
      title: title, token: token)),
  );
}

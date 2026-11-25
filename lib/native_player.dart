import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'egyshow_global_ads.dart';

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
    this.ar = true,
    this.onFailure,
  });
  final String type;
  final int id;
  final int mediaId;
  final String title;
  final String? token;
  final bool reelMode;
  final bool ar;
  final VoidCallback? onFailure;

  @override
  State<EgyshowSitePlayer> createState() => _EgyshowSitePlayerState();
}

class _EgyshowSitePlayerState extends State<EgyshowSitePlayer>
    with WidgetsBindingObserver {
  late final WebViewController controller;
  int progress = 0;
  bool failed = false;

  bool _preparingSession = true;
  bool _sessionError = false;
  DateTime? _lastTap;
  DateTime? _lastOpen;
  String? _lastOpenedUrl;

  bool get _recentTap => _lastTap != null &&
      DateTime.now().difference(_lastTap!) < const Duration(seconds: 2);

  Future<void> _openExternal(String raw) async {
    final uri = Uri.tryParse(raw);
    if (!mounted || _preparingSession || !_recentTap || uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        _firstParty(uri)) return;
    final now = DateTime.now();
    if (_lastOpenedUrl == uri.toString() && _lastOpen != null &&
        now.difference(_lastOpen!) < const Duration(seconds: 2)) return;
    _lastOpenedUrl = uri.toString();
    _lastOpen = now;
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
    catch (_) { /* Browser failure must not interrupt the player. */ }
  }

  bool _firstParty(Uri uri) => uri.scheme == 'https' &&
      uri.userInfo.isEmpty && (!uri.hasPort || uri.port == 443) &&
      (uri.host == 'egyshow.com' || uri.host == 'www.egyshow.com');

  Future<void> _installExternalAdBridge() async {
    try {
      await controller.runJavaScript(r"""
        (function () {
          if (window.__egyshowNativeBrowserBridge || !window.EgyshowExternalAd) return;
          window.__egyshowNativeBrowserBridge = true;
          let lastAdTap = 0;
          function external(raw) {
            try {
              const u = new URL(String(raw), location.href);
              return /^https?:$/.test(u.protocol) && u.hostname &&
                !u.username && !u.password &&
                !['egyshow.com','www.egyshow.com'].includes(u.hostname) ? u.href : '';
            } catch (_) { return ''; }
          }
          function forward(raw) {
            const target = external(raw);
            if (target) window.EgyshowExternalAd.postMessage(target);
            return !!target;
          }
          document.addEventListener('click', function (event) {
            if (!event.isTrusted) return;
            const el = event.target;
            const link = el && el.closest && el.closest('a[href]');
            if (link && external(link.href)) {
              event.preventDefault();
              event.stopImmediatePropagation();
              forward(link.href);
              return;
            }
            if (el && el.closest && el.closest('[data-ad-placement],[data-ad-click],[data-ad-id],[class*="ad-slot"],[id*="AdBanner"],[id*="adBanner"]')) {
              lastAdTap = Date.now();
            }
          }, true);
          const originalOpen = window.open;
          window.open = function (url) {
            if (external(url)) {
              if (Date.now() - lastAdTap < 2000) forward(url);
              return null;
            }
            return originalOpen.apply(window, arguments);
          };
        })();
      """);
    } catch (_) {}
  }

  Uri get url => Uri.https('egyshow.com', '/watch', {
    'target_type': widget.type,
    'target_id': widget.id.toString(),
    'media_id': widget.mediaId.toString(),
    'lang': widget.ar ? 'ar' : 'en',
  });

  Future<void> _startPlayer() async {
    if (!mounted) return;
    setState(() { failed = false; progress = 0; _preparingSession = true; _sessionError = false; });
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() { failed = true; _sessionError = true; _preparingSession = false; });
      return;
    }
    try {
      // The first-party profile endpoint validates the bearer token and sets
      // the server's HttpOnly member cookie before /watch is requested.
      await controller.loadRequest(Uri.https('egyshow.com', '/api/v1/profile'),
          headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'});
    } catch (_) {
      if (mounted) setState(() { failed = true; _preparingSession = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('EgyshowExternalAd',
          onMessageReceived: (message) => unawaited(_openExternal(message.message)))
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() { failed = false; progress = 0; });
        },
        onPageFinished: (finishedUrl) async {
          if (!mounted) return;
          final current = Uri.tryParse(finishedUrl);
          if (current == null || !_firstParty(current)) return;
          if (_preparingSession && current.path == '/api/v1/profile') {
            try {
              final verified = await controller.runJavaScriptReturningResult(
                "try { JSON.parse(document.body.innerText).ok === true } catch(e) { false }");
              if (!mounted) return;
              if (verified == true || verified.toString() == 'true') {
                setState(() { _preparingSession = false; progress = 0; });
                await controller.loadRequest(url);
              } else {
                setState(() { failed = true; _sessionError = true; _preparingSession = false; });
              }
            } catch (_) {
              if (mounted) setState(() { failed = true; _preparingSession = false; });
            }
            return;
          }
          if (current.path == '/' || current.path.endsWith('/account')) {
            setState(() { failed = true; _sessionError = true; _preparingSession = false; });
            return;
          }
          if (!_preparingSession && !failed) {
            setState(() => progress = 100);
            await _installExternalAdBridge();
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() { failed = true; _preparingSession = false; });
            widget.onFailure?.call();
          }
        },
        onNavigationRequest: (request) {
          // Never turn advertisements or external links into a top-level app page.
          // Subresource requests (including ads/media) remain untouched.
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (!request.isMainFrame) return NavigationDecision.navigate;
          if (_firstParty(uri)) return NavigationDecision.navigate;
          if (_recentTap && !_preparingSession) unawaited(_openExternal(request.url));
          return NavigationDecision.prevent;
        },
      ));
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    unawaited(_startPlayer());
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
      Positioned.fill(child: Offstage(offstage: _preparingSession || failed,
        child: Listener(onPointerDown: (_) => _lastTap = DateTime.now(),
          child: WebViewWidget(controller: controller)))),
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
            Text(_sessionError
                ? (widget.ar ? 'سجّل الدخول إلى حسابك ثم أعد المحاولة' : 'Sign in again to continue watching')
                : (widget.ar ? 'تعذر تحميل مشغل EGYSHOW' : 'Unable to load EGYSHOW player'),
              textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _startPlayer,
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
    this.ar = true,
  });
  final String type;
  final int id;
  final int mediaId;
  final String title;
  final String? token;
  final bool ar;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      backgroundColor: Colors.black,
    ),
    body: SafeArea(child: Column(children: [
      Expanded(child: EgyshowSitePlayer(
        type: type, id: id, mediaId: mediaId,
        title: title, token: token, ar: ar)),
      const EgyshowAdPlacement(format: EgyshowAdFormat.adaptiveAads,
        compact: true),
    ])),
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Isolated and labelled advertising slots for EGYSHOW Android.
/// Each ad runs in its own WebView, outside all playback layers.
/// An intentional ad tap opens the device's browser; automatic redirects stay blocked.
enum EgyshowAdFormat {
  leaderboard,
  nativeWidget,
  partnerScript,
  adaptiveAads,
}

class EgyshowAdPlacement extends StatefulWidget {
  const EgyshowAdPlacement({
    super.key,
    required this.format,
    this.compact = false,
    this.ar = true,
  });

  final EgyshowAdFormat format;
  final bool compact;
  final bool ar;

  @override
  State<EgyshowAdPlacement> createState() => _EgyshowAdPlacementState();
}

class _EgyshowAdPlacementState extends State<EgyshowAdPlacement> {
  late final WebViewController _webview;
  bool _failed = false;
  DateTime? _lastGesture;
  DateTime? _lastOpen;
  String? _lastOpenedUrl;

  bool get _recentTap => _lastGesture != null &&
      DateTime.now().difference(_lastGesture!) < const Duration(seconds: 2);

  Future<void> _openAdLink(String raw) async {
    if (!_recentTap) return;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty || uri.host.isEmpty) return;
    final now = DateTime.now();
    if (_lastOpenedUrl == uri.toString() && _lastOpen != null &&
        now.difference(_lastOpen!) < const Duration(seconds: 2)) return;
    _lastOpenedUrl = uri.toString();
    _lastOpen = now;
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
    catch (_) { /* Keep the app and ad slot in place on failure. */ }
  }

  static const String _clickBridge = r'''
<script>
(function () {
  var nativeAd = window.EgyshowAdClick;
  if (!nativeAd) return;
  var lastTouch = 0;
  function forward(raw) {
    try {
      var target = new URL(String(raw), document.baseURI);
      if ((target.protocol === 'https:' || target.protocol === 'http:') &&
          target.hostname) nativeAd.postMessage(target.href);
    } catch (_) {}
  }
  document.addEventListener('pointerdown', function(event) {
    if (event.isTrusted) lastTouch = Date.now();
  }, true);
  document.addEventListener('click', function(event) {
    if (!event.isTrusted) return;
    lastTouch = Date.now();
    var a = event.target && event.target.closest && event.target.closest('a[href]');
    if (!a) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    forward(a.href);
  }, true);
  // Open only user-initiated script destinations, never timer pop-unders.
  window.open = function(url) {
    if (url && Date.now() - lastTouch < 2000) forward(url);
    return null;
  };
})();
</script>
''';

  static const _root = '''
<!doctype html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>
:root{color-scheme:dark;}
*{box-sizing:border-box;}
html,body{margin:0;padding:0;width:100%;min-height:100%;overflow-x:hidden;
background:#101620;color:#8194a5;font-family:Arial,sans-serif;}
#ad-label{height:12px;text-align:center;font-size:10px;letter-spacing:.5px;color:#718093;}
</style></head><body><div id="ad-label">Sponsored</div>
''';

  static const _leaderboard = '''
<div id="board" style="width:728px;height:90px;transform-origin:0 0;margin:auto">
<script>
atOptions = {
  'key' : '37ea6330594f94801f2ba1eb50c762a0',
  'format' : 'iframe',
  'height' : 90,
  'width' : 728,
  'params' : {}
};
</script>
<script src="https://astrayentireillegimateillegimate.com/37ea6330594f94801f2ba1eb50c762a0/invoke.js"></script>
</div>
<script>
function resizeBoard(){
  var b=document.getElementById('board');
  var scale=Math.min(1,(document.documentElement.clientWidth||320)/728);
  b.style.transform='scale('+scale+')';
  b.style.marginLeft=((document.documentElement.clientWidth-728*scale)/2)+'px';
  b.style.marginRight='0';
  document.body.style.height=(12+90*scale)+'px';
}
window.addEventListener('resize',resizeBoard);
resizeBoard();
</script>
''';

  static const _native = '''
<div id="container-f2d83af2e65a70897bc7682d2a8aa66e"></div>
<script async="async" data-cfasync="false"
 src="https://astrayentireillegimateillegimate.com/f2d83af2e65a70897bc7682d2a8aa66e/invoke.js"></script>
''';

  static const _script = '''
<div style="height:54px;display:flex;align-items:center;justify-content:center">
  <span style="font-size:11px;color:#8194a5">Sponsored content</span>
</div>
<script src="https://astrayentireillegimateillegimate.com/42/e0/01/42e001815a55634ec456dac693eba30a.js"></script>
''';

  static const _aads = '''
<div id="frame" style="width:100%;margin:auto;position:relative">
  <iframe data-aa='2458950'
    src='https://acceptable.a-ads.com/2458950/?size=Adaptive'
    loading='lazy'
    referrerpolicy='strict-origin-when-cross-origin'
    style='border:0;padding:0;width:70%;height:115px;overflow:hidden;display:block;margin:auto'></iframe>
</div>
''';

  String get _html {
    final root = _root.replaceFirst('</head>', _clickBridge + '</head>');
    switch (widget.format) {
      case EgyshowAdFormat.leaderboard: return root + _leaderboard + '</body></html>';
      case EgyshowAdFormat.nativeWidget: return root + _native + '</body></html>';
      case EgyshowAdFormat.partnerScript: return root + _script + '</body></html>';
      case EgyshowAdFormat.adaptiveAads: return root + _aads + '</body></html>';
    }
  }

  @override
  void initState() {
    super.initState();
    _webview = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF101620))
      ..addJavaScriptChannel('EgyshowAdClick',
          onMessageReceived: (message) => unawaited(_openAdLink(message.message)))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // Allow embedded ad assets to load without navigating the app.
          // External main-frame links require a recent actual pointer gesture.
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final target = Uri.tryParse(request.url);
          if (target != null &&
              (target.scheme == 'about' || target.scheme == 'data' ||
               (target.scheme == 'https' && target.host == 'egyshow.com'))) {
            return NavigationDecision.navigate;
          }
          if (_recentTap) unawaited(_openAdLink(request.url));
          return NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => _failed = true);
          }
        },
      ));
    _webview.loadHtmlString(_html, baseUrl: 'https://egyshow.com/');
  }

  @override
  void didUpdateWidget(covariant EgyshowAdPlacement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.format != widget.format) {
      _failed = false;
      _webview.loadHtmlString(_html, baseUrl: 'https://egyshow.com/');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final available = (screenWidth - (widget.compact ? 12.0 : 24.0))
        .clamp(160.0, 728.0).toDouble();
    final height = switch (widget.format) {
      EgyshowAdFormat.leaderboard =>
          (90 * available / 728).clamp(32.0, 90.0).toDouble() + 12.0,
      EgyshowAdFormat.nativeWidget => widget.compact ? 112.0 : 210.0,
      EgyshowAdFormat.partnerScript => widget.compact ? 75.0 : 105.0,
      EgyshowAdFormat.adaptiveAads => widget.compact ? 100.0 : 135.0,
    };
    return Semantics(
      label: widget.ar ? 'مساحة إعلانية' : 'Sponsored advertising area',
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 3 : 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.compact ? 7 : 13),
            child: SizedBox(width: available, height: height,
              child: Listener(
                onPointerDown: (_) => _lastGesture = DateTime.now(),
                child: WebViewWidget(controller: _webview))),
          ),
        ),
      ),
    );
  }
}

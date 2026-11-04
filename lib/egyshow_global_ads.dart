import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Isolated and labelled advertising slots for EGYSHOW Android.
/// Each ad runs in its own WebView, outside all playback layers.
/// Popup windows and unsolicited top-level redirects are disabled.
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
    switch (widget.format) {
      case EgyshowAdFormat.leaderboard: return _root + _leaderboard + '</body></html>';
      case EgyshowAdFormat.nativeWidget: return _root + _native + '</body></html>';
      case EgyshowAdFormat.partnerScript: return _root + _script + '</body></html>';
      case EgyshowAdFormat.adaptiveAads: return _root + _aads + '</body></html>';
    }
  }

  @override
  void initState() {
    super.initState();
    _webview = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF101620))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // Subframes can load ad content; never replace the app's screen
          // with an automatic redirect or pop-under destination.
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final target = Uri.tryParse(request.url);
          if (target != null &&
              (target.scheme == 'about' || target.scheme == 'data' ||
               (target.scheme == 'https' && target.host == 'egyshow.com'))) {
            return NavigationDecision.navigate;
          }
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
        .clamp(160.0, 728.0);
    final double height;
    switch (widget.format) {
      case EgyshowAdFormat.leaderboard:
        height = (90 * available / 728).clamp(32.0, 90.0) + 12;
      case EgyshowAdFormat.nativeWidget:
        height = widget.compact ? 112 : 210;
      case EgyshowAdFormat.partnerScript:
        height = widget.compact ? 75 : 105;
      case EgyshowAdFormat.adaptiveAads:
        height = widget.compact ? 100 : 135;
    }
    return Semantics(
      label: widget.ar ? 'مساحة إعلانية' : 'Sponsored advertising area',
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 3 : 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.compact ? 7 : 13),
            child: SizedBox(width: available, height: height,
              child: WebViewWidget(controller: _webview)),
          ),
        ),
      ),
    );
  }
}

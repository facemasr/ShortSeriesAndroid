import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'native_api.dart';

/// Display only banner campaigns already configured in the EGYSHOW ads manager.
/// Ad destinations open in the device's external browser only after a real tap.
class EgyshowBannerAd extends StatefulWidget {
  const EgyshowBannerAd({super.key, required this.api, this.placement = 'home',
    this.height = 92});
  final EgyApi api;
  final String placement;
  final double height;
  @override
  State<EgyshowBannerAd> createState() => _EgyshowBannerAdState();
}

class _EgyshowBannerAdState extends State<EgyshowBannerAd> {
  WebViewController? browser;
  Map<String, dynamic>? banner;
  DateTime? _lastGesture;
  DateTime? _lastOpen;
  String? _lastOpenedUrl;

  bool get _recentTap => _lastGesture != null &&
      DateTime.now().difference(_lastGesture!) < const Duration(seconds: 2);

  Future<void> _openAdLink(String url) async {
    if (!_recentTap) return;
    final target = Uri.tryParse(url.trim());
    if (target == null || !target.hasAuthority ||
        !const {'https', 'http'}.contains(target.scheme) ||
        target.userInfo.isNotEmpty || target.host.isEmpty) return;
    final now = DateTime.now();
    if (_lastOpenedUrl == target.toString() && _lastOpen != null &&
        now.difference(_lastOpen!) < const Duration(seconds: 2)) return;
    _lastOpen = now;
    _lastOpenedUrl = target.toString();
    try { await launchUrl(target, mode: LaunchMode.externalApplication); }
    catch (_) { /* A failed advertiser intent must not break the catalog. */ }
  }

  static const String _clickBridge = r'''
<script>
(function () {
  var channel = window.EgyshowBannerClick;
  if (!channel) return;
  var lastTouch = 0;
  function forward(raw) {
    try {
      var u = new URL(String(raw), document.baseURI);
      if ((u.protocol === 'https:' || u.protocol === 'http:') &&
          u.hostname) channel.postMessage(u.href);
    } catch (_) {}
  }
  document.addEventListener('pointerdown', function(e) {
    if (e.isTrusted) lastTouch = Date.now();
  }, true);
  document.addEventListener('click', function(e) {
    if (!e.isTrusted) return;
    lastTouch = Date.now();
    var link = e.target && e.target.closest && e.target.closest('a[href]');
    if (!link) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    forward(link.href);
  }, true);
  // Reject automatic pop-unders; forward user-initiated popup URLs instead.
  window.open = function(url) {
    if (url && Date.now() - lastTouch < 2000) forward(url);
    return null;
  };
})();
</script>
''';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final ctx = await widget.api.playerContext('movie', 26926);
      final ads = asList(ctx['ads']).map(asMap).where((ad) {
        final placement = txt(ad['placement']).toLowerCase();
        final format = txt(ad['format']).toLowerCase();
        final active = ad['is_active'] == true || ad['is_active'] == 1;
        final bannerPlacement = placement.contains('banner') ||
            placement == widget.placement || placement == 'global';
        return active && bannerPlacement &&
          (format == 'image' || format == 'html' || format == 'script' ||
           txt(ad['code_html']).isNotEmpty);
      }).toList();
      if (ads.isEmpty || !mounted) return;
      ads.sort((a,b) => numId(b['priority']).compareTo(numId(a['priority'])));
      final selected = ads.first;
      final html = txt(selected['code_html']);
      if (html.isNotEmpty) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.transparent)
          ..addJavaScriptChannel('EgyshowBannerClick',
              onMessageReceived: (message) {
                unawaited(_openAdLink(message.message));
              })
          ..setNavigationDelegate(NavigationDelegate(
            onNavigationRequest: (request) {
              if (!request.isMainFrame) return NavigationDecision.navigate;
              final uri = Uri.tryParse(request.url);
              if (uri == null) return NavigationDecision.prevent;
              if (uri.scheme == 'about' || uri.scheme == 'data' ||
                  (uri.scheme == 'https' && uri.host == 'egyshow.com')) {
                return NavigationDecision.navigate;
              }
              if (_recentTap) unawaited(_openAdLink(request.url));
              return NavigationDecision.prevent;
            },
          ));
        await controller.loadHtmlString(
          '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
          + _clickBridge + '</head>'
          '<body style="margin:0;display:flex;align-items:center;justify-content:center;background:transparent;overflow:hidden">'
          + html + '</body></html>',
          baseUrl: 'https://egyshow.com/',
        );
        browser = controller;
      }
      if (mounted) setState(() => banner = selected);
    } catch (_) {
      // Never block catalog navigation if a banner cannot load.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = banner;
    if (ad == null) return const SizedBox.shrink();
    final image = txt(ad['media_url']).isNotEmpty
      ? txt(ad['media_url']) : txt(ad['creative_url']);
    if (browser == null && !image.startsWith('https://')) {
      return const SizedBox.shrink();
    }
    final clickUrl = txt(ad['click_url']);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: SizedBox(height: widget.height, child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: browser != null
          ? Listener(
              onPointerDown: (_) => _lastGesture = DateTime.now(),
              child: WebViewWidget(controller: browser!))
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: clickUrl.isNotEmpty
                ? () { _lastGesture = DateTime.now(); unawaited(_openAdLink(clickUrl)); } : null,
              child: Image.network(image, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink())),
      )));
  }
}

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';

const siteHost = 'egyshow.com';
bool isOfficialSite(Uri? uri) => uri != null && uri.scheme == 'https' &&
    uri.host == siteHost && uri.port == 443 && uri.userInfo.isEmpty;
Uri siteWatchEntry(String type, int id, int mediaId, bool ar) =>
    Uri.https(siteHost, '/mobile-player', {
      'target_type': type, 'target_id': '$id', 'media_id': '$mediaId',
      if (type == 'episode') 'episode_id': '$id',
      'lang': ar ? 'ar' : 'en',
    });
bool isOfficialWatch(Uri? uri) => isOfficialSite(uri) &&
    (uri!.path == '/mobile-player' || RegExp(r'^/watch/[A-Za-z0-9_-]{32}$').hasMatch(uri.path));
bool isCatalogueEntry(Uri? uri) => isOfficialSite(uri) &&
    RegExp(r'^/(ar|en)/(movie|series|short-series)/[^/]+(?:/season/[0-9]+/episode/[0-9]+)?/?$').hasMatch(uri!.path);

class SiteWatchView extends StatefulWidget {
  const SiteWatchView({super.key, required this.type, required this.id,
    required this.mediaId, required this.ar, required this.onClose,
    this.reels = false});
  final String type;
  final int id, mediaId;
  final bool ar, reels;
  final VoidCallback onClose;
  @override State<SiteWatchView> createState() => _SiteWatchViewState();
}

class _SiteWatchViewState extends State<SiteWatchView> {
  late final WebViewController controller;
  bool loading = true, failed = false;
  Uri? externalLink;
  String t(String ar, String en) => widget.ar ? ar : en;
  Uri get entry => siteWatchEntry(widget.type, widget.id, widget.mediaId, widget.ar);

  @override void initState() {
    super.initState();
    controller = WebViewController()
      ..setBackgroundColor(Colors.black)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          if (isOfficialWatch(uri)) return NavigationDecision.navigate;
          if (uri != null && uri.scheme == 'https' && uri.userInfo.isEmpty && mounted) {
            setState(() => externalLink = uri);
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() { loading = true; failed = false; });
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() => loading = false);
          if (widget.reels && isOfficialWatch(Uri.tryParse(url))) {
            await installReelsNavigation();
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() { loading = false; failed = true; });
          }
        },
      ));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    controller.loadRequest(entry);
  }

  Future<void> installReelsNavigation() async {
    final current = Uri.tryParse(await controller.currentUrl() ?? '');
    if (!mounted || !isOfficialWatch(current)) return;
    try {
      await controller.runJavaScript('''
(() => {
  if (location.origin !== 'https://egyshow.com' || location.pathname !== '/mobile-player' || window.__egyReelsInstalled) return;
  const root = document.getElementById('playerRoot');
  if (!root) return;
  window.__egyReelsInstalled = true;
  let start = null;
  const interactive = el => el?.closest?.('button,a,input,select,textarea,.drawer,.settings-panel,[role="slider"]');
  root.addEventListener('touchstart', e => {
    if (e.touches.length !== 1 || interactive(e.target) || root.classList.contains('drawer-open') || root.classList.contains('gesture-locked')) { start = null; return; }
    start = {x:e.touches[0].clientX,y:e.touches[0].clientY};
  }, {passive:true});
  root.addEventListener('touchcancel', () => { start=null; }, {passive:true});
  root.addEventListener('touchend', e => {
    if (!start || !e.changedTouches.length) return;
    const dx=e.changedTouches[0].clientX-start.x, dy=e.changedTouches[0].clientY-start.y;
    start=null;
    if (Math.abs(dy)<75 || Math.abs(dy)<Math.abs(dx)*1.5 || root.classList.contains('drawer-open') || root.classList.contains('gesture-locked')) return;
    const items=Array.from(document.querySelectorAll('#episodeList button.episode-item'));
    const index=items.findIndex(x=>x.classList.contains('active'));
    const button=index<0?null:items[index+(dy<0?1:-1)];
    if(button&&!button.disabled) button.click();
  }, {passive:true});
})();''');
    } catch (_) {}
  }

  Future<void> retry() async {
    if (mounted) setState(() { failed = false; loading = true; });
    await controller.loadRequest(entry);
  }

  @override Widget build(BuildContext context) => ColoredBox(
    color: Colors.black, child: Column(children: [
      SafeArea(bottom: false, child: Row(children: [
        IconButton(onPressed: widget.onClose, tooltip: t('إغلاق المشغل','Close player'), icon: const Icon(Icons.arrow_back)),
        Expanded(child: Text(t('مشغل EGYSHOW','EGYSHOW player'), maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(onPressed: retry, tooltip: t('إعادة فتح المشاهدة','Reopen playback'), icon: const Icon(Icons.refresh)),
      ])),
      if (loading) const LinearProgressIndicator(minHeight: 2),
      if (externalLink != null) MaterialBanner(
        content: Text(t('رابط خارجي. افتحه في المتصفح إذا أردت.','External link. Open in your browser if needed.')),
        actions: [
          TextButton(onPressed: () { final uri = externalLink; setState(() => externalLink = null); if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication); }, child: Text(t('فتح','Open'))),
          TextButton(onPressed: () => setState(() => externalLink = null), child: Text(t('إلغاء','Cancel'))),
        ]),
      if (failed) Expanded(child: Center(child: FilledButton.icon(onPressed: retry,
        icon: const Icon(Icons.refresh), label: Text(t('تعذر فتح المشغل · إعادة المحاولة','Could not open player · Retry')))))
      else Expanded(child: WebViewWidget(controller: controller)),
    ]),
  );
}

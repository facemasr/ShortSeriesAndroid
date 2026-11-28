import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';

const siteHost = 'egyshow.com';
bool isOfficialSite(Uri? uri) => uri != null && uri.scheme == 'https' &&
    uri.host == siteHost && uri.port == 443 && uri.userInfo.isEmpty;
Uri siteWatchEntry(String type, int id, int mediaId, bool ar) =>
    Uri.https(siteHost, '/watch', {
      'target_type': type, 'target_id': '$id', 'media_id': '$mediaId',
      if (type == 'episode') 'episode_id': '$id',
      'lang': ar ? 'ar' : 'en',
    });
bool isOfficialWatch(Uri? uri) => isOfficialSite(uri) &&
    RegExp(r'^/watch/[A-Za-z0-9_-]{32}$').hasMatch(uri!.path);
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
  bool loading = true, watching = false, attempted = false;
  bool failed = false;
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
          if (isOfficialSite(uri)) return NavigationDecision.navigate;
          if (uri != null && uri.scheme == 'https' && uri.userInfo.isEmpty && mounted) {
            setState(() => externalLink = uri);
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() { loading = true; failed = false; watching = isOfficialWatch(Uri.tryParse(url)); });
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          final uri = Uri.tryParse(url);
          setState(() { loading = false; watching = isOfficialWatch(uri); });
          if (!attempted && isCatalogueEntry(uri)) {
            attempted = true;
            await openVisibleWatchLink();
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

  // Use the site's own visible Watch action. Its normal access checks and
  // one-time link creation remain in charge; never copy or read credentials.
  Future<void> openVisibleWatchLink() async {
    final current = Uri.tryParse(await controller.currentUrl() ?? '');
    if (!mounted || !isCatalogueEntry(current)) return;
    final expected = jsonEncode({'type': widget.type, 'id': widget.id});
    try {
      await controller.runJavaScript('''
(() => {
  const expected = $expected;
  let attempts = 0;
  const find = () => {
    if (location.origin !== 'https://egyshow.com' || ++attempts > 12) return;
    for (const a of document.querySelectorAll('a[href]')) {
      let u; try { u = new URL(a.href, location.origin); } catch (_) { continue; }
      if (u.origin !== location.origin || u.pathname !== '/watch') continue;
      if (u.searchParams.get('target_type') !== expected.type ||
          Number(u.searchParams.get('target_id') || u.searchParams.get('episode_id')) !== expected.id) continue;
      if (!a.getClientRects().length || a.closest('[hidden],[inert],.hidden') ||
          a.matches('[disabled],[aria-disabled="true"],.disabled') ||
          getComputedStyle(a).pointerEvents === 'none') continue;
      a.click(); return;
    }
    setTimeout(find, 350);
  };
  find();
})();''');
    } catch (_) {}
  }

  Future<void> retry() async {
    attempted = false;
    if (mounted) setState(() { failed = false; loading = true; });
    // Never reload a consumed watch token; restart the normal watch flow.
    await controller.loadRequest(entry);
  }

  @override Widget build(BuildContext context) => ColoredBox(
    color: Colors.black, child: Column(children: [
      SafeArea(bottom: false, child: Row(children: [
        IconButton(onPressed: widget.onClose, tooltip: t('إغلاق المشغل','Close player'), icon: const Icon(Icons.arrow_back)),
        Expanded(child: Text(watching ? t('مشغل EGYSHOW','EGYSHOW player') :
          t('EGYSHOW · المشاهدة عبر الموقع','EGYSHOW · website playback'),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (!watching && !loading) IconButton(onPressed: openVisibleWatchLink,
          tooltip: t('فتح المشغل','Open player'), icon: const Icon(Icons.play_circle_outline)),
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
        icon: const Icon(Icons.refresh), label: Text(t('تعذر فتح الموقع · إعادة المحاولة','Could not open site · Retry')))))
      else Expanded(child: WebViewWidget(controller: controller)),
    ]),
  );
}

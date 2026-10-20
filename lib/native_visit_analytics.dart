import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'native_api.dart';

/// Native-page analytics that reuse the site's existing tracking code.
/// The admin panel already injects Histats (and any additional supported
/// analytics scripts) in EGYSHOW's public HTML. Never hard-code account IDs
/// here: changing/disabling the tracker in admin should affect the app too.
/// Video and match/YouTube pages execute their own analytics in their existing
/// first-party WebView, so those pages must not be counted again here.
class EgyshowVisitAnalytics {
  EgyshowVisitAnalytics._();
  static final EgyshowVisitAnalytics instance = EgyshowVisitAnalytics._();

  final ValueNotifier<VisitPage> current =
      ValueNotifier<VisitPage>(const VisitPage('/', 0));
  String _lastPath = '';
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _sequence = 0;

  void track(String path) {
    if (!path.startsWith('/') || path.startsWith('//')) return;
    final now = DateTime.now();
    if (_lastPath == path &&
        now.difference(_lastAt) < const Duration(seconds: 6)) return;
    _lastPath = path;
    _lastAt = now;
    current.value = VisitPage(path, ++_sequence);
  }

  static String tabPath(int index) => switch (index) {
    0 => '/',
    1 => '/ar/movies',
    2 => '/ar/series',
    3 => '/ar/short-series',
    4 => '/ar/channels',
    // 5 = matches and 6 = YouTube: their real webpages already track visits.
    7 => '/ar/?app_section=profile',
    8 => '/ar/?app_section=search',
    _ => '/',
  };

  static String mediaPath(Media media) {
    final segment = switch (media.type) {
      'movie' => 'movie',
      'short_series' => 'short-series',
      _ => 'series'
    };
    final slug = txt(media.raw['slug']);
    // Never include search terms, tokens, emails, or device identifiers.
    final identifier = slug.isNotEmpty ? Uri.encodeComponent(slug)
        : media.id.toString();
    return '/ar/$segment/$identifier';
  }
}

class VisitPage {
  const VisitPage(this.path, this.serial);
  final String path;
  final int serial;
}

/// A tiny, non-interactive Android WebView executes only the real tracking
/// scripts configured in EGYSHOW. It is attached once above the Navigator.
/// No player, ads, or catalog webpage is loaded in the tracking view.
class EgyshowVisitPixel extends StatefulWidget {
  const EgyshowVisitPixel({super.key});
  @override
  State<EgyshowVisitPixel> createState() => _EgyshowVisitPixelState();
}

class _EgyshowVisitPixelState extends State<EgyshowVisitPixel> {
  late final WebViewController controller;
  late final EgyshowVisitAnalytics tracker;
  List<String> scripts = <String>[];
  DateTime? lastFetch;
  Future<void>? fetching;
  bool disposed = false;
  int requestVersion = 0;

  @override
  void initState() {
    super.initState();
    tracker = EgyshowVisitAnalytics.instance;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          // Tracking scripts may fetch remote resources in subframes but
          // should not redirect the app's tracking view away from EGYSHOW.
          final uri = Uri.tryParse(request.url);
          return (uri?.host == 'egyshow.com')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ));
    tracker.current.addListener(_visit);
    // First launch is a homepage pageview; follow-up visits reflect navigation.
    tracker.track('/');
    _visit();
  }

  Future<List<String>> _readTrackingScripts() async {
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch!) <
          const Duration(minutes: 15)) {
      return scripts;
    }
    if (fetching != null) {
      await fetching;
      return scripts;
    }
    final completer = Completer<void>();
    fetching = completer.future;
    try {
      final result = await http.get(
        Uri.parse('$origin/'),
        headers: {'Accept': 'text/html'},
      ).timeout(const Duration(seconds: 12));
      if (result.statusCode != 200) return scripts;
      final page = result.body;
      final pattern = RegExp(r'<script\b[^>]*>[\s\S]*?<\/script\s*>',
          caseSensitive: false);
      final detector = RegExp(
        r'histats|google-analytics|googletagmanager|gtag\(|'
        r'statcounter|matomo|clarity\.ms|plausible\.io|'
        r'_paq|facebook\.net/en_US/fbevents|'
        r'analytics\.js|pixel\.js',
        caseSensitive: false);
      final selected = <String>[];
      for (final m in pattern.allMatches(page)) {
        final tag = m.group(0);
        if (tag != null && detector.hasMatch(tag)) selected.add(tag);
      }
      scripts = selected;
      lastFetch = DateTime.now();
      return scripts;
    } catch (e) {
      debugPrint('EGYSHOW tracking scripts unavailable: $e');
      return scripts;
    } finally {
      fetching = null;
      completer.complete();
    }
  }

  void _visit() {
    final sequence = ++requestVersion;
    final page = tracker.current.value.path;
    // The sections with existing full first-party WebViews automatically
    // execute the same site's code; avoid a duplicate analytics hit.
    if (page == '/matches/' || page.startsWith('/ar/youtube')) return;
    unawaited(_loadVisit(page, sequence));
  }

  Future<void> _loadVisit(String page, int version) async {
    final tags = await _readTrackingScripts();
    if (disposed || version != requestVersion || tags.isEmpty) return;
    // App-source query distinguishes native app traffic in analytics
    // reports without collecting identifiers or search text.
    final url = Uri.parse(origin).resolve(page);
    final params = Map<String, String>.from(url.queryParameters);
    params['app_source'] = 'egyshow_android';
    final pageUrl = url.replace(queryParameters: params).toString();
    final html = '<!DOCTYPE html><html lang="ar"><head>'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="referrer" content="strict-origin-when-cross-origin">'
      + tags.join('\n') +
      '</head><body style="margin:0;background:transparent"></body></html>';
    try {
      await controller.loadHtmlString(html, baseUrl: pageUrl);
    } catch (e) {
      debugPrint('EGYSHOW analytics page load failed: $e');
    }
  }

  @override
  void dispose() {
    disposed = true;
    tracker.current.removeListener(_visit);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
    IgnorePointer(child: SizedBox(width: 1, height: 1,
      child: WebViewWidget(controller: controller)));
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'native_api.dart';

const sectionRed = Color(0xFFE50914);
const sectionDark = Color(0xFF111116);

/// Only match/video WATCH pages use the existing website player.
/// Listings, filters and search below are native Flutter UI.
class SiteWatch extends StatefulWidget {
  const SiteWatch({super.key, required this.title, required this.path});
  final String title, path;
  @override State<SiteWatch> createState() => _SiteWatchState();
}
class _SiteWatchState extends State<SiteWatch> {
  late final WebViewController browser;
  int progress = 0;
  String error = '';
  @override void initState() {
    super.initState();
    final address = Uri.parse(origin).resolve(widget.path);
    if (address.host != 'egyshow.com' || address.scheme != 'https') {
      error = 'رابط مشاهدة غير صالح';
    }
    browser = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) { if (mounted) setState(() => progress = p); },
        onWebResourceError: (e) { if (e.isForMainFrame == true && mounted) {
          setState(() => error = e.description);
        } },
      ));
    if (error.isEmpty) browser.loadRequest(address);
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: Text(widget.title, maxLines: 1,
        overflow: TextOverflow.ellipsis)),
    body: Stack(children: [
      Positioned.fill(child: WebViewWidget(controller: browser)),
      if (progress < 100 && error.isEmpty) const Positioned(
        top: 0, left: 0, right: 0, child: LinearProgressIndicator(
          color: sectionRed, minHeight: 2)),
      if (error.isNotEmpty) Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error, textAlign: TextAlign.center),
          OutlinedButton.icon(onPressed: () {
            setState(() => error = '');
            browser.reload();
          }, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
        ]))),
    ]),
  );
}

class MatchInfo {
  MatchInfo(this.raw);
  final Map<String,dynamic> raw;
  String get id => txt(raw['id']);
  String get home => txt(raw['home']);
  String get away => txt(raw['away']);
  String get score => txt(raw['score']);
  String get time => txt(raw['time']);
  String get state => txt(raw['state']);
  String get homeLogo => txt(raw['homeLogo']);
  String get awayLogo => txt(raw['awayLogo']);
  String get title => txt(raw['title']).isNotEmpty ? txt(raw['title'])
      : home + ' × ' + away;
}

class YoutubeClip {
  YoutubeClip(this.raw);
  final Map<String,dynamic> raw;
  String get id => txt(raw['id']).isNotEmpty
      ? txt(raw['id']) : txt(raw['youtube_id']);
  String get title => txt(raw['title']);
  String get channel => txt(raw['channel']).isNotEmpty
      ? txt(raw['channel']) : txt(raw['channel_name']);
  String get picture => txt(raw['thumbnail']).isNotEmpty
      ? txt(raw['thumbnail']) : txt(raw['thumbnail_url']);
  String get path {
    final p = txt(raw['url']);
    if (p.startsWith('/watch?egy=')) return p;
    return '/watch?egy=' + Uri.encodeComponent(id);
  }
}

class WebsiteSection extends StatefulWidget {
  const WebsiteSection({super.key, required this.kind, required this.ar,
    required this.api});
  final String kind;
  final bool ar;
  final EgyApi api;
  @override State<WebsiteSection> createState() => _WebsiteSectionState();
}

class _WebsiteSectionState extends State<WebsiteSection> {
  String matchDay = 'today';
  String youtubeCategory = 'music';
  String search = '', error = '';
  List<MatchInfo> matches = [];
  List<YoutubeClip> clips = [];
  List<Map<String,dynamic>> categories = [];
  bool busy = true;
  int requestVersion = 0;
  Timer? debounce;

  bool get isMatch => widget.kind == 'matches';
  String t(String a, String en) => widget.ar ? a : en;

  @override void initState() {
    super.initState();
    _load();
  }

  @override void didUpdateWidget(covariant WebsiteSection previous) {
    super.didUpdateWidget(previous);
    if (previous.kind != widget.kind || previous.ar != widget.ar) _load();
  }

  Future<void> _load() async {
    final version = ++requestVersion;
    if (mounted) setState(() { busy = true; error = ''; });
    try {
      if (isMatch) {
        final result = await widget.api.call('/matches/api?day=' + matchDay);
        final list = asList(result['matches']).map((m) => MatchInfo(asMap(m))).toList();
        if (mounted && version == requestVersion) {
          setState(() { matches = list; busy = false; });
        }
      } else {
        // The live site uses discover/search, not /api/v1/youtube/videos.
        if (categories.isEmpty) {
          try {
            final result = await widget.api.call('/api/v1/youtube/categories');
            categories = asList(result['categories']).map(asMap).toList();
          } catch (_) {
            categories = [
              {'key':'music','ar':'موسيقى','en':'Music'},
              {'key':'sports','ar':'رياضة','en':'Sports'},
              {'key':'gaming','ar':'ألعاب','en':'Gaming'},
            ];
          }
        }
        final path = search.trim().isEmpty
            ? '/api/v1/youtube/discover?lang=' + (widget.ar ? 'ar' : 'en') +
                '&category=' + Uri.encodeQueryComponent(youtubeCategory)
            : '/api/v1/youtube/search?lang=' + (widget.ar ? 'ar' : 'en') +
                '&q=' + Uri.encodeQueryComponent(search.trim());
        final result = await widget.api.call(path);
        final list = asList(result['items']).map((m) => YoutubeClip(asMap(m)))
            .where((v) => v.id.isNotEmpty).toList();
        if (mounted && version == requestVersion) {
          setState(() { clips = list; busy = false; });
        }
      }
    } catch (e) {
      if (mounted && version == requestVersion) {
        setState(() { busy = false; error = e.toString(); });
      }
    }
  }

  @override void dispose() { debounce?.cancel(); super.dispose(); }

  void _openMatch(MatchInfo m) {
    if (m.id.isEmpty) return;
    // The internal website route uses the same server list and player.
    final watch = '/app?match_day=' + matchDay +
      '&match_id=' + Uri.encodeComponent(m.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        SiteWatch(title: m.title, path: watch)));
  }

  void _openYoutube(YoutubeClip clip) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      SiteWatch(title: clip.title, path: clip.path)));
  }

  Widget _logo(String url) => SizedBox(height: 46, width: 46,
    child: url.startsWith('https://') ? Image.network(url, fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
        const Icon(Icons.sports_soccer, color: Colors.white54)) :
      const Icon(Icons.sports_soccer, color: Colors.white54));

  Widget _matchCard(MatchInfo m) => Card(
    color: sectionDark, margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
    clipBehavior: Clip.antiAlias, child: InkWell(
      onTap: () => _openMatch(m),
      child: Padding(padding: const EdgeInsets.all(13), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Expanded(child: Column(children: [
            _logo(m.homeLogo), const SizedBox(height: 7),
            Text(m.home, textAlign: TextAlign.center, maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
          SizedBox(width: 95, child: Column(children: [
            Text(m.score.isEmpty ? 'VS' : m.score,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(m.time, style: const TextStyle(color: Colors.white60)),
          ])),
          Expanded(child: Column(children: [
            _logo(m.awayLogo), const SizedBox(height: 7),
            Text(m.away, textAlign: TextAlign.center, maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
        ]),
        const Divider(height: 20, color: Colors.white12),
        Row(children: [
          const Icon(Icons.circle, size: 8, color: Colors.red),
          const SizedBox(width: 7),
          Expanded(child: Text(m.state, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70))),
          Text(t('تفاصيل المباراة', 'Match details'),
            style: const TextStyle(color: sectionRed)),
          const Icon(Icons.chevron_right, color: sectionRed),
        ]),
      ])),
    ),
  );

  Widget _videoCard(YoutubeClip v) => Card(color: sectionDark,
    margin: const EdgeInsets.fromLTRB(10, 5, 10, 5), clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: () => _openYoutube(v),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(aspectRatio: 16 / 9,
          child: v.picture.startsWith('https://') ?
            Image.network(v.picture, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Colors.black, child: Icon(Icons.play_circle_outline))) :
            const ColoredBox(color: Colors.black,
              child: Icon(Icons.play_circle_outline, size: 50))),
        Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 5),
            Text(v.channel, style: const TextStyle(color: Colors.white60)),
          ])),
      ])));

  Widget _header() {
    if (isMatch) return Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.sports_soccer, color: sectionRed),
          const SizedBox(width: 8),
          Expanded(child: Text(t('المباريات', 'Matches'), style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold))),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ]),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final day in ['yesterday', 'today', 'tomorrow'])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(day == 'today' ? t('اليوم','Today') :
                    day == 'yesterday' ? t('أمس','Yesterday') :
                      t('غدًا','Tomorrow')),
                  selected: matchDay == day,
                  onSelected: (_) {
                    matchDay = day;
                    _load();
                  },
                )),
          ])),
      ]));
    return Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.play_circle_fill, color: sectionRed),
          const SizedBox(width: 8),
          Expanded(child: Text('EGYSHOW YouTube',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ]),
        TextField(
          onChanged: (v) {
            search = v;
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 450), _load);
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: t('ابحث في فيديوهات YouTube','Search YouTube'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 9),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: categories.map((c) =>
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(txt(c[widget.ar ? 'ar' : 'en'])),
                selected: youtubeCategory == txt(c['key']),
                onSelected: (_) {
                  youtubeCategory = txt(c['key']);
                  search = '';
                  _load();
                },
              ))).toList())),
      ]));
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
      _header(),
      if (busy) const Padding(padding: EdgeInsets.all(36),
        child: Center(child: CircularProgressIndicator(color: sectionRed))),
      if (error.isNotEmpty) Padding(padding: const EdgeInsets.all(25),
        child: Column(children: [
          Text(error, textAlign: TextAlign.center),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh),
            label: Text(t('إعادة المحاولة','Retry'))),
        ])),
      if (!busy && error.isEmpty && (isMatch ? matches.isEmpty : clips.isEmpty))
        Padding(padding: const EdgeInsets.all(32),
          child: Text(t('لا توجد نتائج حاليًا','No results'),
            textAlign: TextAlign.center)),
      if (!busy && isMatch) ...matches.map(_matchCard),
      if (!busy && !isMatch) ...clips.map(_videoCard),
      const SizedBox(height: 22),
    ]),
  );
}

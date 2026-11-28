import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'native_api.dart';
import 'native_banner_ads.dart';
import 'native_visit_analytics.dart';
import 'in_app_updates.dart';
import 'egyshow_global_ads.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EgyshowNativeApp());
}
const red = Color(0xFFE50914);
const dark = Color(0xFF09090C);
const panel = Color(0xFF17171C);

String tr(bool ar, String a, String en) => ar ? a : en;
String categoryTitle(String type, bool ar) {
  if (type == 'movie') return tr(ar, 'أفلام', 'Movies');
  if (type == 'series') return tr(ar, 'مسلسلات', 'Series');
  return tr(ar, 'مسلسلات قصيرة', 'Short series');
}

class EgyshowNativeApp extends StatelessWidget {
  const EgyshowNativeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'EGYSHOW',
    theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: dark,
      colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: dark, foregroundColor: Colors.white),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: panel, indicatorColor: Color(0xFF721319)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: red)),
    ),
    home: const NativeShell(),
    builder: (context, child) => Stack(fit: StackFit.expand, children: [
      if (child != null) child,
      const Positioned(right: 0, bottom: 0, width: 1, height: 1,
        child: EgyshowVisitPixel()),
    ]),
  );
}

class Art extends StatelessWidget {
  const Art(this.url, {super.key, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => url.startsWith('http')
      ? CachedNetworkImage(
          imageUrl: url, fit: fit,
          placeholder: (_, __) => const ColoredBox(color: panel,
            child: Center(child: Icon(Icons.movie_outlined, color: Colors.white24))),
          errorWidget: (_, __, ___) => const ColoredBox(color: panel,
            child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38))),
        )
      : const ColoredBox(color: panel,
          child: Center(child: Icon(Icons.movie_outlined, size: 36, color: Colors.white24)));
}

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.media, required this.ar,
    required this.tap, this.width = 142});
  final Media media;
  final bool ar;
  final VoidCallback tap;
  final double width;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: tap,
    child: SizedBox(width: width, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12),
          child: Stack(fit: StackFit.expand, children: [
            Art(media.poster),
            const Align(alignment: Alignment.bottomCenter,
              child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xD9000000)],
                  begin: Alignment.center, end: Alignment.bottomCenter)),
                child: SizedBox(height: 65, width: double.infinity))),
            Positioned(top: 7, right: 7, child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0xC5000000),
                borderRadius: BorderRadius.circular(5)),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(media.year, style: const TextStyle(fontSize: 10))))),
          ]))),
        const SizedBox(height: 6),
        Text(media.title(ar), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        if (media.rating.isNotEmpty)
          Text('★ ' + media.rating, style: const TextStyle(color: Colors.amber,
              fontSize: 11)),
      ],
    )),
  );
}

class NativeShell extends StatefulWidget {
  const NativeShell({super.key});
  @override
  State<NativeShell> createState() => _NativeShellState();
}

class _NativeShellState extends State<NativeShell> with WidgetsBindingObserver {
  final api = EgyApi();
  SharedPreferences? prefs;
  bool ar = true;
  int tab = 0;
  final Map<String, Media> favorites = {};
  Map<String, List<Media>> homeData = {};
  final Map<String, List<Media>> catalogs = {};
  final Map<String, int> pages = {};
  List<Media> searchResults = [];
  String query = '';
  bool busy = true, listBusy = false, searchBusy = false;
  String error = '';
  Timer? searchTimer;
  int sessionEpoch = 0;
  bool openingPlayer = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) EgyshowAppUpdates.check(context, ar: ar);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      EgyshowAppUpdates.check(context, ar: ar);
    }
  }

  Future<void> _start() async {
    try {
      prefs = await SharedPreferences.getInstance();
      ar = prefs?.getBool('language_ar') ?? true;
      for (final row in prefs?.getStringList('guest_favorites') ?? <String>[]) {
        try {
          final media = Media(asMap(jsonDecode(row)));
          if (media.id > 0) favorites[media.key] = media;
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) await _loadHome();
  }

  Future<void> _loadHome() async {
    final requestEpoch = sessionEpoch;
    if (mounted) setState(() { busy = true; error = ''; });
    try {
      final data = await api.home();
      if (mounted && sessionEpoch == requestEpoch) setState(() { homeData = data; busy = false; error = ''; });
    } catch (e) {
      if (sessionEpoch != requestEpoch) return;
      final fallback = <Media>[];
      for (final type in ['movie', 'series', 'short_series']) {
        try { fallback.addAll(await api.catalog(type)); } catch (_) {}
      }
      if (!mounted || sessionEpoch != requestEpoch) return;
      setState(() {
        homeData = fallback.isEmpty ? {} : {
          'featured': fallback.take(1).toList(),
          'trending': fallback.take(20).toList(),
          'latest': fallback.take(24).toList(),
        };
        busy = false;
        error = fallback.isEmpty ? e.toString() : '';
      });
    }
  }

  Future<void> _select(int next) async {
    if (![0, 1, 2, 3, 7, 8].contains(next)) return;
    setState(() { tab = next; error = ''; });
    if (next != 5 && next != 6) {
      EgyshowVisitAnalytics.instance.track(EgyshowVisitAnalytics.tabPath(next));
    }
    if (next >= 1 && next <= 3) {
      final t = ['movie', 'series', 'short_series'][next - 1];
      if (!catalogs.containsKey(t)) await _loadCatalog(t, fresh: true);
    }
  }

  Future<void> _loadCatalog(String type, {bool fresh = false}) async {
    if (listBusy) return;
    final requestEpoch = sessionEpoch;
    if (mounted) setState(() { listBusy = true; error = ''; });
    try {
      final page = fresh ? 1 : (pages[type] ?? 0) + 1;
      final items = await api.catalog(type, page: page);
      if (mounted && sessionEpoch == requestEpoch) setState(() {
        catalogs[type] = fresh ? items : [...catalogs[type] ?? [], ...items];
        pages[type] = page;
        listBusy = false;
      });
    } catch (e) {
      if (mounted && sessionEpoch == requestEpoch) setState(() { error = e.toString(); listBusy = false; });
    }
  }

  void _search(String value) {
    final requestEpoch = sessionEpoch;
    searchTimer?.cancel();
    query = value;
    if (value.trim().isEmpty) {
      setState(() { searchResults = []; searchBusy = false; });
      return;
    }
    setState(() => searchBusy = true);
    searchTimer = Timer(const Duration(milliseconds: 450), () async {
      final q = value.trim();
      try {
        final result = await api.search(q);
        if (mounted && sessionEpoch == requestEpoch && query.trim() == q) {
          setState(() { searchResults = result; searchBusy = false; });
        }
      } catch (e) {
        if (mounted && sessionEpoch == requestEpoch && query.trim() == q) {
          setState(() { searchBusy = false; error = e.toString(); });
        }
      }
    });
  }

  Future<void> _favorite(Media media) async {
    final enabled = !favorites.containsKey(media.key);
    setState(() {
      if (enabled) favorites[media.key] = media;
      else favorites.remove(media.key);
    });
    await prefs?.setStringList('guest_favorites',
        favorites.values.map((e) => jsonEncode(e.raw)).toList());
  }

  void _open(Media media) {
    final previousPath = EgyshowVisitAnalytics.instance.current.value.path;
    EgyshowVisitAnalytics.instance.track(EgyshowVisitAnalytics.mediaPath(media));
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      NativeDetails(api: api, media: media, ar: ar,
        favorite: favorites.containsKey(media.key),
        onFavorite: _favorite, onPlay: _play, onReels: _openReels,
        onOpenMedia: _open))).then((_) {
      EgyshowVisitAnalytics.instance.track(previousPath);
    });
  }

  void _openReels(Media media, int episodeIndex) {
    if (episodeIndex < 0 || episodeIndex >= media.episodes.length) return;
    _play('episode', media.episodes[episodeIndex].id, media.title(ar), media.id.toString(), true);
  }

  void _play(String type, int id, String title, [String mediaKey = '', bool reels = false]) async {
    if (openingPlayer || id < 1 || !['movie','episode'].contains(type)) return;
    openingPlayer = true;
    try {
      final uri = Uri(scheme: 'egyplayer', host: 'play', queryParameters: {
        'type': type, 'id': id.toString(), 'lang': ar ? 'ar' : 'en',
        if (reels && type == 'episode') 'mode': 'reels',
        if (type == 'episode' && (int.tryParse(mediaKey) ?? 0) > 0) 'media_id': mediaKey,
      });
      final intent = AndroidIntent(action: 'action_view',
        package: 'com.egyshow.player', data: uri.toString());
      await intent.launch();
    } catch (_) {
      if (!mounted) return;
      final install = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(tr(ar, 'يلزم تثبيت EGY Player', 'EGY Player required')),
        content: Text(tr(ar, 'ثبّت المشغل الرسمي ثم اضغط مشاهدة مرة أخرى.',
          'Install the official player, then tap Watch again.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ar, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ar, 'صفحة التطبيقات', 'Apps page'))),
        ],
      ));
      if (install == true) {
        await launchUrl(Uri.parse('https://egyshow.com/download-app'), mode: LaunchMode.externalApplication);
      }
    } finally {
      openingPlayer = false;
    }
  }

  void _switchLang() {
    setState(() => ar = !ar);
    prefs?.setBool('language_ar', ar);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchTimer?.cancel();
    api.dispose();
    super.dispose();
  }

  Widget _error() => Padding(padding: const EdgeInsets.all(20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(error, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.orangeAccent)),
      TextButton.icon(onPressed: () { if (tab == 0) _loadHome();
          else if (tab > 0 && tab < 4) _loadCatalog(
              ['movie','series','short_series'][tab - 1], fresh: true);
        }, icon: const Icon(Icons.refresh), label: Text(tr(ar, 'إعادة المحاولة', 'Retry'))),
    ]));

  Widget _rail(String title, List<Media> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
      SizedBox(height: 251, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 13),
        itemBuilder: (_, i) => PosterCard(media: items[i], ar: ar,
            tap: () => _open(items[i])),
      )),
    ]);
  }

  Widget _home() {
    if (busy) return const Center(child: CircularProgressIndicator());
    if (homeData.isEmpty) return _error();
    final featured = homeData['featured'] ?? [];
    return RefreshIndicator(onRefresh: _loadHome, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), children: [
      if (featured.isNotEmpty) GestureDetector(
        onTap: () => _open(featured.first),
        child: Stack(children: [
          SizedBox(height: 260, width: double.infinity,
              child: Art(featured.first.backdrop)),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [dark, Colors.transparent, dark],
              begin: Alignment.bottomCenter, end: Alignment.topCenter)))),
          Positioned(left: 18, right: 18, bottom: 20,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(featured.first.title(ar), maxLines: 2,
                  style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: () => _open(featured.first),
                icon: const Icon(Icons.play_arrow), label: Text(tr(ar, 'شاهد الآن', 'Watch now'))),
            ])),
        ])),
      EgyshowBannerAd(api: api, placement: 'home'),
      const EgyshowAdPlacement(format: EgyshowAdFormat.nativeWidget),
      _rail(tr(ar, 'الأكثر مشاهدة', 'Trending'), homeData['trending'] ?? []),
      _rail(tr(ar, 'وصل حديثاً', 'Recently added'), homeData['latest'] ?? []),
      EgyshowBannerAd(api: api, placement: 'banner'),
      const EgyshowAdPlacement(format: EgyshowAdFormat.adaptiveAads),
      const SizedBox(height: 24),
    ]));
  }

  Widget _grid(List<Media> data, {bool paginate = false, String type = ''}) =>
      ListView(children: [
        EgyshowBannerAd(api: api, placement: 'banner'),
        const EgyshowAdPlacement(format: EgyshowAdFormat.adaptiveAads),
        if (error.isNotEmpty) _error(),
        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Text(paginate ? categoryTitle(type, ar) :
              tr(ar, 'نتائج البحث', 'Search results'),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, childAspectRatio: 0.53,
            mainAxisSpacing: 12, crossAxisSpacing: 9),
          itemCount: data.length,
          itemBuilder: (_, i) => PosterCard(media: data[i], ar: ar,
              tap: () => _open(data[i]), width: 160),
        ),
        if (paginate) Padding(padding: const EdgeInsets.all(20),
          child: OutlinedButton(
            onPressed: listBusy ? null : () => _loadCatalog(type),
            child: Text(listBusy ? tr(ar, 'جاري التحميل', 'Loading') :
                tr(ar, 'عرض المزيد', 'Load more')))),
        if (listBusy && data.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(20),
            child: CircularProgressIndicator())),
      ]);

  Widget _profile() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(tr(ar, 'قائمتي', 'My list'),
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      if (favorites.isEmpty)
        Text(tr(ar, 'لا توجد عناصر محفوظة', 'No saved titles'),
          style: const TextStyle(color: Colors.white60)),
      ...favorites.values.map((m) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(width: 48, height: 72, child: Art(m.poster)),
        title: Text(m.title(ar), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(categoryTitle(m.type, ar)),
        trailing: IconButton(icon: const Icon(Icons.favorite, color: red),
          onPressed: () => _favorite(m)),
        onTap: () => _open(m),
      )),
      const SizedBox(height: 24),
      const EgyshowAdPlacement(format: EgyshowAdFormat.partnerScript),
      Text(tr(ar, 'الإعدادات', 'Settings'),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      SwitchListTile(
        value: ar, onChanged: (_) => _switchLang(),
        title: Text(tr(ar, 'الواجهة العربية', 'Arabic interface')),
      ),
      ListTile(
        leading: const Icon(Icons.system_update_alt),
        title: Text(tr(ar, 'التحقق من تحديثات التطبيق', 'Check for app updates')),
        onTap: () => EgyshowAppUpdates.check(context, ar: ar, manual: true),
      ),
      const ListTile(title: Text('EGYSHOW Native'),
        subtitle: Text('Android • update checks enabled')),
    ]);
  }

  Widget _searchBody() => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: TextField(
      autofocus: true, onChanged: _search,
      decoration: InputDecoration(
        hintText: tr(ar, 'ابحث عن فيلم أو مسلسل', 'Search movies or series'),
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    )),
    if (searchBusy) const LinearProgressIndicator(color: red),
    Expanded(child: _grid(searchResults)),
  ]);

  Widget _navItem(int index, IconData glyph, String label) {
    final selected = tab == index;
    return InkWell(
      onTap: () => _select(index),
      child: SizedBox(width: 80,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF60121A) : Colors.transparent,
              borderRadius: BorderRadius.circular(16)),
            child: Icon(glyph, size: 24,
              color: selected ? red : Colors.white70)),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5,
              color: selected ? Colors.white : Colors.white60,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSearch = tab == 8;
    Widget body;
    if (tab == 0) body = _home();
    else if (tab >= 1 && tab <= 3) {
      final type = ['movie', 'series', 'short_series'][tab - 1];
      body = _grid(catalogs[type] ?? [], paginate: true, type: type);
    }
    else if (isSearch) body = _searchBody();
    else body = _profile();
    return Directionality(textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Image.asset('assets/brand/logo-full.png', height: 38, fit: BoxFit.contain, semanticLabel: 'EGYSHOW'),
          actions: [
            IconButton(
              tooltip: tr(ar, 'بحث', 'Search'),
              onPressed: () => setState(() { tab = isSearch ? 0 : 8; error = ''; }),
              icon: Icon(isSearch ? Icons.close : Icons.search_rounded)),
            IconButton(
              tooltip: 'AR/EN', onPressed: _switchLang,
              icon: const Icon(Icons.translate_outlined)),
          ]),
        body: body,
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            EgyshowAdPlacement(
              key: const ValueKey('egyshow-global-footer-ad'),
              format: EgyshowAdFormat.leaderboard, compact: true, ar: ar),
            SizedBox(height: 75,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _navItem(0, Icons.home_outlined, tr(ar, 'الرئيسية', 'Home')),
              _navItem(1, Icons.movie_outlined, tr(ar, 'أفلام', 'Movies')),
              _navItem(2, Icons.tv_outlined, tr(ar, 'مسلسلات', 'Series')),
              _navItem(3, Icons.smart_display_outlined, tr(ar, 'قصيرة', 'Shorts')),
              _navItem(7, Icons.favorite_outline, tr(ar, 'قائمتي', 'My list')),
            ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class NativeDetails extends StatefulWidget {
  const NativeDetails({super.key, required this.api, required this.media,
    required this.ar, required this.favorite, required this.onFavorite,
    required this.onPlay, required this.onReels, required this.onOpenMedia});
  final EgyApi api;
  final Media media;
  final bool ar;
  final bool favorite;
  final Future<void> Function(Media) onFavorite;
  final void Function(String, int, String, [String]) onPlay;
  final void Function(Media, int) onReels;
  final void Function(Media) onOpenMedia;
  @override
  State<NativeDetails> createState() => _NativeDetailsState();
}

class _NativeDetailsState extends State<NativeDetails> {
  Media? detail;
  String error = '';
  bool favorite = false;
  int selectedSeason = 0;
  int visibleEpisodes = 12;
  int visibleSuggestions = 9, suggestionPage = 0;
  bool suggestionsBusy = false, suggestionsHaveMore = true;
  List<Media> suggestions = [];
  String suggestionsError = '';
  @override
  void initState() {
    super.initState();
    favorite = widget.favorite;
    _fetch();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    if (suggestionsBusy || !suggestionsHaveMore) return;
    if (mounted) setState(() { suggestionsBusy = true; suggestionsError = ''; });
    try {
      final nextPage = suggestionPage + 1;
      List<Media> page;
      if (nextPage == 1) {
        // Use the site's actual recommendation engine before generic listings.
        try {
          final response = await widget.api.call(
            '/api/v1/mobile/guest/recommendations/' + widget.media.id.toString());
          page = asList(response['items']).map((e) => Media(asMap(e))).toList();
        } catch (_) {
          page = await widget.api.catalog(widget.media.type, page: nextPage);
        }
      } else {
        page = await widget.api.catalog(widget.media.type, page: nextPage);
      }
      if (!mounted) return;
      final existing = suggestions.map((m) => m.key).toSet();
      final fresh = page.where((m) =>
        m.id != widget.media.id && !existing.contains(m.key)).toList();
      setState(() {
        suggestions = [...suggestions, ...fresh];
        suggestionPage = nextPage;
        suggestionsHaveMore = page.length >= 24;
        suggestionsBusy = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        suggestionsBusy = false;
        suggestionsError = e.toString();
      });
    }
  }

  Future<void> _showMoreSuggestions() async {
    if (visibleSuggestions < suggestions.length) {
      setState(() => visibleSuggestions += 9);
    } else if (suggestionsHaveMore) {
      final before = suggestions.length;
      await _loadSuggestions();
      if (mounted && suggestions.length > before) {
        setState(() => visibleSuggestions += 9);
      }
    }
  }

  Future<void> _fetch() async {
    try {
      final d = await widget.api.details(widget.media.id);
      if (mounted) setState(() {
        detail = d; error = '';
        if (selectedSeason != 0 && !d.episodes.any((ep) => ep.season == selectedSeason)) {
          selectedSeason = 0; visibleEpisodes = 12;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }
  @override
  Widget build(BuildContext context) {
    final m = detail ?? widget.media;
    final ar = widget.ar;
    final episodes = m.episodes.where((e) =>
        selectedSeason == 0 || e.season == selectedSeason).toList();
    final shownEpisodes = episodes.take(visibleEpisodes).toList();
    final seasons = m.episodes.map((e) => e.season).where((n) => n > 0).toSet().toList()..sort();
    return Directionality(textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(appBar: AppBar(title: Text(m.title(ar), maxLines: 1,
            overflow: TextOverflow.ellipsis)),
        body: ListView(children: [
          AspectRatio(aspectRatio: 16 / 9, child: Stack(fit: StackFit.expand, children: [
            Art(m.backdrop, fit: BoxFit.contain),
            const DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [dark, Colors.transparent],
              begin: Alignment.bottomCenter, end: Alignment.center))),
          ])),
          EgyshowAdPlacement(format: EgyshowAdFormat.nativeWidget, ar: ar),
          Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title(ar), style: const TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              Text([categoryTitle(m.type, ar), m.year,
                if (m.rating.isNotEmpty) '★ ' + m.rating]
                .where((e) => e.isNotEmpty).join('  •  '),
                style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 15),
              if (m.overview(ar).isNotEmpty)
                Text(m.overview(ar), style: const TextStyle(height: 1.65)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: FilledButton.icon(
                  onPressed: m.isSeries ? (episodes.isEmpty ? null : () {
                    if (m.type == 'short_series') widget.onReels(m, m.episodes.indexWhere((e) => e.id == episodes.first.id));
                    else widget.onPlay('episode', episodes.first.id, m.title(ar), m.id.toString());
                  }) : () => widget.onPlay('movie', m.id, m.title(ar)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(tr(ar, 'المشاهدة الآن', 'Play now')),
                )),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () async {
                    await widget.onFavorite(m);
                    if (mounted) setState(() => favorite = !favorite);
                  },
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_outline,
                    color: favorite ? red : null)),
              ]),
              if (detail == null && error.isEmpty)
                const Padding(padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator())),
              if (error.isNotEmpty) ...[
                Text(error, style: const TextStyle(color: Colors.orangeAccent)),
                TextButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh),
                  label: Text(tr(ar, 'إعادة المحاولة', 'Retry'))),
              ],
              if (m.isSeries) ...[
                const SizedBox(height: 16),
                Text(tr(ar, 'الحلقات', 'Episodes'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (seasons.isNotEmpty)
                  SingleChildScrollView(scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ChoiceChip(label: Text(tr(ar, 'الكل', 'All')),
                        selected: selectedSeason == 0,
                        onSelected: (_) => setState(() { selectedSeason = 0; visibleEpisodes = 12; })),
                      ...seasons.map((n) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(tr(ar, 'الموسم ', 'Season ') + n.toString()),
                          selected: selectedSeason == n,
                          onSelected: (_) => setState(() { selectedSeason = n; visibleEpisodes = 12; })),
                      )),
                    ])),
                if (episodes.isEmpty && detail != null)
                  Padding(padding: const EdgeInsets.all(15), child: Text(
                    tr(ar, 'لا توجد حلقات منشورة', 'No episodes available'))),
                ...shownEpisodes.map((ep) => Card(color: panel, child: ListTile(
                  leading: SizedBox(width: 80, height: 50,
                    child: ClipRRect(borderRadius: BorderRadius.circular(5),
                      child: Art(ep.image.isNotEmpty ? ep.image : m.poster))),
                  title: Text(ep.title(ar), maxLines: 2),
                  subtitle: Text(tr(ar, 'الموسم ', 'Season ') +
                    ep.season.toString() + ' • ' +
                    tr(ar, 'الحلقة ', 'Episode ') + ep.number.toString()),
                  trailing: const Icon(Icons.play_circle_outline, color: red),
                  onTap: () {
                    if (m.type == 'short_series') widget.onReels(m, m.episodes.indexWhere((e) => e.id == ep.id));
                    else widget.onPlay('episode', ep.id, m.title(ar), m.id.toString());
                  },
                ))),
                if (episodes.length > visibleEpisodes)
                  Padding(padding: const EdgeInsets.all(12),
                    child: Center(child: FilledButton.icon(
                      onPressed: () => setState(() => visibleEpisodes += 12),
                      icon: const Icon(Icons.expand_more),
                      label: Text(tr(ar, 'مشاهدة المزيد من الحلقات', 'Show more episodes') +
                        ' (' + (episodes.length - visibleEpisodes).toString() + ')'),
                    ))),
              ],
              // Content recommendations are shown for movies and both
              // standard/short series, independently of the episode list.
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.video_collection_outlined, color: red),
                const SizedBox(width: 9),
                Expanded(child: Text(tr(ar, 'مشاهدة المزيد', 'Watch more'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 4),
              Text(tr(ar, 'محتوى آخر من نفس القسم', 'More from this category'),
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 15),
              if (suggestions.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, childAspectRatio: 0.52,
                    mainAxisSpacing: 12, crossAxisSpacing: 9),
                  itemCount: suggestions.length < visibleSuggestions
                    ? suggestions.length : visibleSuggestions,
                  itemBuilder: (_, index) {
                    final other = suggestions[index];
                    return PosterCard(media: other, ar: ar, width: 150,
                        tap: () => widget.onOpenMedia(other));
                  },
                ),
              if (suggestionsBusy)
                const Padding(padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator())),
              if (suggestionsError.isNotEmpty) ...[
                Text(suggestionsError,
                  style: const TextStyle(color: Colors.orangeAccent)),
                OutlinedButton.icon(onPressed: _loadSuggestions,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr(ar, 'إعادة المحاولة', 'Retry'))),
              ],
              if (!suggestionsBusy &&
                  (visibleSuggestions < suggestions.length || suggestionsHaveMore))
                Padding(padding: const EdgeInsets.only(top: 16, bottom: 14),
                  child: SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showMoreSuggestions,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(tr(ar, 'مشاهدة المزيد', 'Show more')),
                    ))),
              if (!suggestionsBusy && suggestions.isEmpty &&
                  !suggestionsHaveMore && suggestionsError.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(tr(ar, 'لا يوجد محتوى إضافي حاليًا', 'No more titles available'),
                    style: const TextStyle(color: Colors.white54))),
            ])),
        ])));
  }
}


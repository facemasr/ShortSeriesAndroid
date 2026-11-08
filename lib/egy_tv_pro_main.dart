import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_api.dart';
import 'yacine_catalog_cache.dart';
import 'yacine_channel_groups.dart';
import 'yacine_direct_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EgyTvProApp());
}

const bg = Color(0xFF080D17);
const surface = Color(0xFF121D2B);
const accent = Color(0xFF22DAC5);
const muted = Color(0xFF91A2B5);

class EgyTvProApp extends StatelessWidget {
  const EgyTvProApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EGY TV PRO',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent, brightness: Brightness.dark, surface: surface),
      appBarTheme: const AppBarTheme(backgroundColor: bg),
    ),
    home: const ChannelHome(),
  );
}

class ChannelHome extends StatefulWidget {
  const ChannelHome({super.key});
  @override
  State<ChannelHome> createState() => _ChannelHomeState();
}

class _ChannelHomeState extends State<ChannelHome> with WidgetsBindingObserver {
  static const cacheKey = 'egytvpro_catalog_v1';
  static const favoriteKey = 'egytvpro_favorites_v1';
  static const languageKey = 'egytvpro_ar_v1';
  final EgyApi api = EgyApi();
  final search = TextEditingController();
  final Set<String> favorites = {};
  List<LiveChannel> channels = [];
  String mode = 'sports', category = '';
  String? error;
  bool busy = true, refreshing = false, ar = true;
  DateTime? lastFetch;
  SharedPreferences? prefs;
  String t(String a, String e) => ar ? a : e;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    search.addListener(rebuild);
    unawaited(initialize());
  }
  void rebuild() { if (mounted) setState(() {}); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (lastFetch == null || DateTime.now().difference(lastFetch!) >
            const Duration(minutes: 15))) {
      unawaited(refresh());
    }
  }
  Future<void> initialize() async {
    try {
      prefs = await SharedPreferences.getInstance();
      ar = prefs?.getBool(languageKey) ?? true;
      favorites.addAll(prefs?.getStringList(favoriteKey) ?? <String>[]);
      channels = decodeYacineCatalog(prefs?.getString(cacheKey));
      if (mounted) setState(() {});
    } catch (_) {}
    await refresh();
  }
  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    if (mounted) setState(() { busy = true; error = null; });
    try {
      // Only channel catalog metadata is stored. Signed media URLs are
      // fetched on demand by the on-device channel source service.
      final items = await api.live();
      if (items.isEmpty) throw const ApiException('provider_catalog_empty');
      if (!mounted) return;
      setState(() { channels = items; lastFetch = DateTime.now(); });
      try {
        await prefs?.setString(cacheKey, encodeYacineCatalog(items));
      } catch (_) {}
    } catch (_) {
      if (mounted) setState(() => error = channels.isEmpty
          ? t('تعذر جلب القنوات من المصدر.', 'Could not retrieve channels.')
          : t('فشل تحديث الفهرس؛ القائمة المحفوظة قد تحتوي معرفات قديمة.',
              'Catalog refresh failed. Saved IDs may be stale.'));
    } finally {
      refreshing = false;
      if (mounted) setState(() => busy = false);
    }
  }
  String keyFor(YacineQualityGroup g) =>
      (g.title(false) + '|' + g.category).toLowerCase();
  Future<void> toggle(YacineQualityGroup g) async {
    final key = keyFor(g);
    setState(() { if (!favorites.add(key)) favorites.remove(key); });
    await prefs?.setStringList(favoriteKey, favorites.toList());
  }
  bool sports(YacineQualityGroup g) {
    final s = (g.category + ' ' + g.title(false)).toLowerCase();
    return const ['sport', 'bein', 'ssc', 'football', 'match',
      'arena', 'رياض', 'الكأس'].any(s.contains);
  }
  List<YacineQualityGroup> shown(List<YacineQualityGroup> all) {
    final q = search.text.trim().toLowerCase();
    final result = all.where((g) {
      if (mode == 'sports' && !sports(g)) return false;
      if (mode == 'favorites' && !favorites.contains(keyFor(g))) return false;
      if (category.isNotEmpty && g.category != category) return false;
      return q.isEmpty || (g.title(ar) + ' ' + g.title(!ar) + ' ' + g.category)
          .toLowerCase().contains(q);
    }).toList();
    result.sort((a,b) {
      final x = favorites.contains(keyFor(a)), y = favorites.contains(keyFor(b));
      if (x != y) return x ? -1 : 1;
      return a.title(false).compareTo(b.title(false));
    });
    return result;
  }
  void open(LiveChannel ch, YacineQualityGroup group) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      DirectYacineChannelPlayer(
        channel: ch, qualityVariants: group.variants, api: api, ar: ar)));
  }
  void choose(YacineQualityGroup group) {
    if (group.variants.length == 1) {
      open(group.variants.single, group);
      return;
    }
    showModalBottomSheet<void>(
      context: context, backgroundColor: surface, showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * .75),
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(group.title(ar),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            subtitle: Text(t('اختر الجودة', 'Select quality'))),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: accent),
            title: Text(t('جودة تلقائية', 'Automatic quality')),
            onTap: () { Navigator.pop(sheet); open(group.preferred, group); }),
          for (final ch in group.variants)
            ListTile(
              leading: const Icon(Icons.hd_outlined),
              title: Text(yacineChannelQuality(ch) == null ? ch.title(ar)
                  : yacineChannelQuality(ch).toString() + 'p'),
              subtitle: Text(ch.group),
              onTap: () { Navigator.pop(sheet); open(ch, group); }),
        ]),
      )));
  }
  Widget chip(String id, IconData icon, String label) {
    final active = mode == id;
    return Padding(padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: active, showCheckmark: false,
        avatar: Icon(icon, size: 16, color: active ? Colors.black : accent),
        label: Text(label), selectedColor: accent, backgroundColor: surface,
        labelStyle: TextStyle(color: active ? Colors.black : Colors.white),
        onSelected: (_) => setState(() { mode = id; category = ''; })));
  }
  Widget tile(YacineQualityGroup g) {
    final ch = g.preferred, favorite = favorites.contains(keyFor(g));
    return Card(
      margin: EdgeInsets.zero, color: surface, clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF25354B))),
      child: InkWell(onTap: () => choose(g), child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.circle, color: accent, size: 7),
            const SizedBox(width: 5),
            const Expanded(child: Text('TV', style: TextStyle(
                color: accent, fontSize: 11, fontWeight: FontWeight.bold))),
            InkWell(onTap: () => unawaited(toggle(g)),
              child: Padding(padding: const EdgeInsets.all(4),
                child: Icon(favorite ? Icons.star : Icons.star_border,
                  color: favorite ? Colors.amber : muted, size: 22))),
          ]),
          Expanded(child: Padding(
            padding: const EdgeInsets.all(6),
            child: ch.logo.startsWith('https://') ||
                ch.logo.startsWith('http://')
              ? Image.network(ch.logo, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.live_tv, color: accent, size: 42))
              : const Icon(Icons.live_tv, color: accent, size: 42))),
          Text(g.title(ar), textAlign: TextAlign.center, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 3),
          Text(g.qualities.isEmpty ? g.category :
            g.qualities.map((q) => q.toString() + 'p').join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 10)),
          const SizedBox(height: 8),
          Container(width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.play_arrow_rounded, color: accent, size: 19),
              Text(t('مشاهدة', 'Watch'), style: const TextStyle(
                color: accent, fontWeight: FontWeight.w800)),
            ])),
        ]),
      )));
  }
  @override
  Widget build(BuildContext context) {
    final grouped = groupYacineChannels(channels);
    final results = shown(grouped);
    final cats = grouped.map((g) => g.category).where((v) => v.isNotEmpty)
        .toSet().toList()..sort();
    return Directionality(textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(children: [
            Icon(Icons.live_tv, color: accent), SizedBox(width: 10),
            Text('EGY TV PRO', style: TextStyle(fontWeight: FontWeight.w900)),
          ]),
          actions: [
            IconButton(
              tooltip: t('اللغة', 'Language'),
              onPressed: () => setState(() {
                ar = !ar;
                unawaited(prefs?.setBool(languageKey, ar) ??
                    Future<bool>.value(false));
              }),
              icon: const Icon(Icons.language)),
            IconButton(
              tooltip: t('تحديث القنوات', 'Refresh channels'),
              onPressed: refreshing ? null : () => unawaited(refresh()),
              icon: const Icon(Icons.refresh)),
          ]),
        body: RefreshIndicator(
          onRefresh: refresh, color: accent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 12),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFF075661), Color(0xFF122B40),
                      Color(0xFF121827)]),
                    borderRadius: BorderRadius.circular(23)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('قنوات التلفزيون', 'LIVE TELEVISION'),
                        style: const TextStyle(color: accent,
                          fontWeight: FontWeight.bold)),
                      const SizedBox(height: 9),
                      const Text('EGY TV PRO', style: TextStyle(
                        fontSize: 31, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(t('تطبيق مستقل ومشغل داخلي واحد لجميع القنوات',
                            'Dedicated channels app with one built-in player'),
                        style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      Text(grouped.length.toString() + ' ' + t('قناة', 'channels'),
                        style: const TextStyle(color: accent,
                            fontWeight: FontWeight.w800)),
                    ]),
                ))),
              if (error != null)
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Text(error!, style: const TextStyle(
                      color: Colors.orangeAccent)))),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: TextField(controller: search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t('بحث عن قناة أو باقة', 'Search channels or packages'),
                    suffixIcon: search.text.isEmpty ? null : IconButton(
                        onPressed: search.clear, icon: const Icon(Icons.close)),
                    filled: true, fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none))))),
              SliverToBoxAdapter(child: SizedBox(height: 60,
                child: ListView(scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(13, 7, 13, 7), children: [
                    chip('sports', Icons.sports_soccer, t('رياضة', 'Sports')),
                    chip('all', Icons.live_tv, t('جميع القنوات', 'All channels')),
                    chip('favorites', Icons.star, t('المفضلة', 'Favorites')),
                  ]))),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 6),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(category),
                  initialValue: cats.contains(category) ? category : '',
                  isExpanded: true, dropdownColor: surface,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.filter_list),
                    filled: true, fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none)),
                  items: [
                    DropdownMenuItem(value: '',
                        child: Text(t('جميع الباقات', 'All packages'))),
                    for (final cat in cats)
                      DropdownMenuItem(value: cat, child: Text(cat,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => category = v ?? ''),
                ))),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                child: Row(children: [
                  Expanded(child: Text(t('القنوات', 'Channels'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 19))),
                  Text(results.length.toString(), style: const TextStyle(
                    color: accent, fontWeight: FontWeight.bold)),
                ]))),
              if (busy && channels.isEmpty)
                const SliverFillRemaining(child: Center(
                  child: CircularProgressIndicator(color: accent)))
              else if (results.isEmpty)
                SliverFillRemaining(child: Center(child: Text(
                  t('لا توجد قنوات مطابقة؛ اسحب للتحديث.',
                    'No matching channels. Pull to refresh.'),
                  style: const TextStyle(color: muted))))
              else SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverLayoutBuilder(builder: (_, b) {
                  final w = b.crossAxisExtent;
                  final count = w >= 900 ? 6 : w >= 650 ? 5
                      : w >= 430 ? 3 : 2;
                  return SliverGrid.builder(
                    itemCount: results.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count, childAspectRatio: .82,
                      mainAxisSpacing: 10, crossAxisSpacing: 10),
                    itemBuilder: (_, i) => tile(results[i]));
                })),
            ],
          ),
        ),
      ));
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.removeListener(rebuild);
    search.dispose();
    api.dispose();
    super.dispose();
  }
}

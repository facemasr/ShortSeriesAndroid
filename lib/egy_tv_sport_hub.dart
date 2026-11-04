import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_api.dart';
import 'native_banner_ads.dart';

/// Native EGY TV Sport experience. Catalog metadata only; no signed stream URLs.
class EgyTvSportHub extends StatefulWidget {
  const EgyTvSportHub({super.key, required this.api, required this.ar,
    required this.channels, required this.loading, required this.onRefresh,
    required this.onOpen});
  final EgyApi api;
  final bool ar;
  final List<LiveChannel> channels;
  final bool loading;
  final Future<void> Function() onRefresh;
  final void Function(LiveChannel channel) onOpen;
  @override
  State<EgyTvSportHub> createState() => _EgyTvSportHubState();
}

class _EgyTvSportHubState extends State<EgyTvSportHub> {
  static const teal = Color(0xFF12D6C0);
  static const surface = Color(0xFF18202E);
  static const key = 'egy_tv_sport_favorites_v1';
  static const sports = ['sport','bein','ssc','رياض','الكأس','football','arena','goal','match'];
  final search = TextEditingController();
  Set<String> favorites = {};
  String mode = 'sports', package = '';
  bool refreshing = false;

  String t(String a, String e) => widget.ar ? a : e;
  String channelKey(LiveChannel c) =>
    c.providerId.isNotEmpty ? c.providerId : c.id.toString();
  bool isSport(LiveChannel c) {
    final terms = (c.title(true) + ' ' + c.title(false) + ' ' + c.group).toLowerCase();
    return sports.any(terms.contains);
  }

  @override
  void initState() {
    super.initState();
    search.addListener(_update);
    unawaited(_loadFavorites());
  }
  void _update() { if (mounted) setState(() {}); }
  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => favorites =
        (prefs.getStringList(key) ?? const <String>[]).toSet());
    } catch (_) {}
  }
  Future<void> _toggleFavorite(LiveChannel c) async {
    final id = channelKey(c);
    setState(() { if (!favorites.add(id)) favorites.remove(id); });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, favorites.toList()..sort());
    } catch (_) {}
  }
  Future<void> _refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try { await widget.onRefresh(); }
    finally { if (mounted) setState(() => refreshing = false); }
  }
  @override
  void dispose() { search.removeListener(_update); search.dispose(); super.dispose(); }

  Widget _chip(String id, IconData icon, String label) {
    final active = mode == id;
    return Padding(padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(showCheckmark: false,
        avatar: Icon(icon, size: 17, color: active ? Colors.black : teal),
        label: Text(label), selected: active, selectedColor: teal,
        backgroundColor: surface,
        labelStyle: TextStyle(
          color: active ? Colors.black : Colors.white,
          fontWeight: active ? FontWeight.w800 : FontWeight.normal),
        onSelected: (_) => setState(() { mode = id; package = ''; })));
  }

  Widget _card(LiveChannel c) {
    final liked = favorites.contains(channelKey(c));
    return Material(color: surface, borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias, child: InkWell(
        onTap: () => widget.onOpen(c),
        child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
          Row(children: [
            const Icon(Icons.circle, size: 7, color: teal),
            const SizedBox(width: 4),
            const Expanded(child: Text('LIVE', style: TextStyle(
              color: teal, fontSize: 10, fontWeight: FontWeight.bold))),
            GestureDetector(onTap: () => _toggleFavorite(c),
              child: Icon(liked ? Icons.star_rounded : Icons.star_border_rounded,
                size: 23, color: liked ? Colors.amber : Colors.white54)),
          ]),
          Expanded(child: Padding(padding: const EdgeInsets.all(5),
            child: c.logo.startsWith('https://')
              ? Image.network(c.logo, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.live_tv_outlined, color: Colors.white38, size: 42))
              : const Icon(Icons.live_tv_outlined, color: Colors.white38, size: 42))),
          Text(c.title(widget.ar), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(c.group.isEmpty ? t('قناة مباشرة','Live channel') : c.group,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 8),
          Container(width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: teal.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(7)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.play_arrow_rounded, color: teal, size: 17),
              Text(t('تشغيل','Watch'), style: const TextStyle(
                color: teal, fontWeight: FontWeight.w700, fontSize: 11)),
            ])),
        ]))));
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.channels.map((c) => c.group)
      .where((c) => c.isNotEmpty).toSet().toList()..sort();
    final q = search.text.trim().toLowerCase();
    final results = widget.channels.where((c) {
      if (mode == 'sports' && !isSport(c)) return false;
      if (mode == 'favorites' && !favorites.contains(channelKey(c))) return false;
      if (package.isNotEmpty && c.group != package) return false;
      return q.isEmpty ||
        (c.title(widget.ar) + ' ' + c.group).toLowerCase().contains(q);
    }).toList()..sort((a,b) {
      final fav = (favorites.contains(channelKey(b)) ? 1 : 0)
        .compareTo(favorites.contains(channelKey(a)) ? 1 : 0);
      return fav != 0 ? fav : a.title(widget.ar).compareTo(b.title(widget.ar));
    });

    return RefreshIndicator(color: teal, onRefresh: _refresh,
      child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 9),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  Color(0xFF075761), Color(0xFF142536), Color(0xFF131622)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                border: Border.all(color: const Color(0xFF21696D)),
                borderRadius: BorderRadius.circular(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Chip(backgroundColor: Color(0xFF12393F),
                    label: Text('● LIVE', style: TextStyle(color: teal,
                      fontWeight: FontWeight.bold, fontSize: 11))),
                  const Spacer(),
                  const Icon(Icons.sports_soccer_rounded, color: teal, size: 32),
                ]),
                const SizedBox(height: 10),
                const Text('EGY TV SPORT', style: TextStyle(
                  fontSize: 27, letterSpacing: 1.2, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(t('قنوات الرياضة وجميع البثوث داخل تطبيق EGYSHOW',
                  'Sports and all live TV inside EGYSHOW'),
                  style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 13),
                Row(children: [
                  Text(widget.channels.length.toString() + ' ' +
                      t('قناة في الفهرس','channels in catalog'),
                    style: const TextStyle(color: teal, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton.filledTonal(onPressed: refreshing ? null : _refresh,
                    tooltip: t('تحديث القائمة', 'Refresh catalog'),
                    icon: refreshing
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded)),
                ]),
              ]),
            ),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            child: TextField(controller: search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: t('البحث باسم القناة أو الباقة', 'Search channels or packages'),
                filled: true, fillColor: surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
                suffixIcon: q.isEmpty ? null : IconButton(
                  onPressed: search.clear, icon: const Icon(Icons.close)),
              )),
          )),
          SliverToBoxAdapter(child: SizedBox(height: 52,
            child: ListView(scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 13), children: [
                _chip('sports', Icons.sports_soccer, t('الرياضة','Sports')),
                _chip('all', Icons.live_tv, t('جميع القنوات','All channels')),
                _chip('favorites', Icons.star, t('المفضلة','Favorites')),
              ]))),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 6, 13, 9),
            child: DropdownButtonFormField<String>(
              key: ValueKey(package),
              initialValue: categories.contains(package) ? package : '',
              isExpanded: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.filter_list),
                filled: true, fillColor: surface, isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide.none)),
              items: [
                DropdownMenuItem(value: '', child: Text(t('جميع الباقات','All packages'))),
                ...categories.map((x) => DropdownMenuItem(
                  value: x, child: Text(x, maxLines: 1,
                    overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (next) => setState(() => package = next ?? ''),
            ),
          )),
          SliverToBoxAdapter(child: EgyshowBannerAd(api: widget.api,
            placement: 'banner', height: 90)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Expanded(child: Text(t('القنوات', 'Channels'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              Text(results.length.toString(),
                style: const TextStyle(color: teal, fontWeight: FontWeight.bold)),
            ]),
          )),
          if (widget.loading && widget.channels.isEmpty)
            const SliverFillRemaining(child: Center(
              child: CircularProgressIndicator(color: teal)))
          else if (results.isEmpty)
            SliverFillRemaining(child: Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t('لا توجد قنوات مطابقة. جرّب تحديث القائمة.',
                'No matching channels. Try refreshing the catalog.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60)))))
          else
            SliverPadding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 15),
              sliver: SliverLayoutBuilder(builder: (_, bounds) {
                final w = bounds.crossAxisExtent;
                final columns = w >= 900 ? 5 : w >= 650 ? 4 : w >= 430 ? 3 : 2;
                return SliverGrid.builder(
                  itemCount: results.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns, childAspectRatio: .85,
                    mainAxisSpacing: 10, crossAxisSpacing: 10),
                  itemBuilder: (_, i) => _card(results[i]));
              })),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
        ]));
  }
}

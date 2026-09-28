import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

part 'pro_home.dart';
part 'pro_detail.dart';
part 'pro_player.dart';
part 'pro_player_controls.dart';
part 'full_parity.dart';
part 'admin_studio_core.dart';
part 'admin_studio_import.dart';
part 'admin_studio_content.dart';
part 'pro_import_center.dart';
part 'import_bridge_ui.dart';

const apiUrl = 'https://shortseris.online/mobile-api/index.php';
const appDisplayName = 'SHORT SERIES TV';
final RouteObserver<PageRoute<dynamic>> appRouteObserver = RouteObserver<PageRoute<dynamic>>();

class AppPlaybackSession {
  static Player? _active;
  static void claim(Player player) {
    final previous = _active;
    if (previous != null && !identical(previous, player)) {
      unawaited(previous.stop());
    }
    _active = player;
  }
  static void release(Player player) {
    if (identical(_active, player)) _active = null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    await Api.I.loadConfig();
  } catch (_) {}
  runApp(const ShortSerisApp());
}

class Api {
  Api._();
  static final I = Api._();
  final dio = Dio(BaseOptions(
    baseUrl: apiUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final store = const FlutterSecureStorage();
  String locale = 'ar';
  Map<String, dynamic> config = {};

  bool get ar => locale == 'ar';

  String absoluteUrl(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) return raw;
    if (raw.startsWith('//')) return 'https:$raw';
    final clean = raw.replaceFirst(RegExp(r'^/+'), '');
    return 'https://shortseris.online/$clean';
  }

  Future<Map<String, dynamic>> call(
    String action, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? data,
    String method = 'GET',
  }) async {
    final token = await store.read(key: 'token');
    final response = await dio.request(
      '',
      queryParameters: {'action': action, 'locale': locale, ...?query},
      data: data,
      options: Options(
        method: method,
        headers: token == null ? null : {'Authorization': 'Bearer ' + token},
      ),
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    if (map['ok'] != true) throw Exception(map['error'] ?? 'Request failed');
    return map;
  }

  Future<Map<String, dynamic>> loadConfig() async {
    final result = await call('app_config');
    config = Map<String, dynamic>.from(result['data'] as Map);
    return config;
  }

  bool section(String key, [bool fallback = true]) {
    final sections = config['sections'];
    if (sections is Map && sections.containsKey(key)) {
      final v = sections[key];
      return v == true || v == 1 || v == '1';
    }
    return fallback;
  }

  List<Map<String, dynamic>> ads(String placement) {
    final ads = config['ads'];
    if (ads is Map && ads[placement] is List) {
      return (ads[placement] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const [];
  }

  Future<void> login(String email, String password) async {
    final result = await call(
      'login',
      method: 'POST',
      data: {
        'email': email.trim(),
        'password': password,
        'device_name': 'SHORT SERIES TV Android'
      },
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    await store.write(key: 'token', value: data['token'].toString());
  }

  Future<void> logout() async {
    try {
      await call('logout', method: 'POST');
    } catch (_) {}
    await store.delete(key: 'token');
  }

  Future<bool> hasToken() async => (await store.read(key: 'token'))?.isNotEmpty == true;

  Future<String> deviceId() async {
    var id = await store.read(key: 'device_id');
    if (id != null && id.isNotEmpty) return id;
    final rnd = Random.secure();
    id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${rnd.nextInt(1 << 32).toRadixString(36)}-${rnd.nextInt(1 << 32).toRadixString(36)}';
    await store.write(key: 'device_id', value: id);
    return id;
  }

  Future<int> localResume(String type, int id) async {
    final raw = await store.read(key: 'resume_${type}_$id');
    if (raw == null) return 0;
    final parts = raw.split('|');
    return int.tryParse(parts.first) ?? 0;
  }

  Future<void> saveLocalProgress(String type, int id, int position, int duration) async {
    if (type == 'tv' || id <= 0 || duration <= 0) return;
    if (position / duration >= .92) {
      await store.delete(key: 'resume_${type}_$id');
      return;
    }
    await store.write(key: 'resume_${type}_$id', value: '$position|$duration');
  }

  Future<void> recordView(String type, int id) async {
    if (type == 'tv' || id <= 0) return;
    try {
      await call(
        'view',
        method: 'POST',
        data: {'owner_type': type, 'owner_id': id, 'device_id': await deviceId()},
      );
    } catch (_) {}
  }
}

Color hexColor(String? value) {
  final raw = (value ?? '').replaceAll('#', '');
  final n = int.tryParse(raw.length == 6 ? 'FF' + raw : raw, radix: 16);
  return n == null ? const Color(0xFFE50914) : Color(n);
}

List<int> versionParts(String value) => value
    .split('.')
    .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
    .toList();

bool versionLess(String a, String b) {
  final x = versionParts(a), y = versionParts(b);
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final av = i < x.length ? x[i] : 0;
    final bv = i < y.length ? y[i] : 0;
    if (av < bv) return true;
    if (av > bv) return false;
  }
  return false;
}

class ShortSerisApp extends StatelessWidget {
  const ShortSerisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: hexColor(Api.I.config['primary_color']?.toString()),
          brightness: Brightness.dark,
          surface: const Color(0xFF111214),
        ),
        scaffoldBackgroundColor: const Color(0xFF050505),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF050505),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF111214),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xF20A0A0A),
          indicatorColor: Color(0x22E50914),
          elevation: 0,
          height: 68,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF151619),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE50914)),
          ),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: Api.I.ar ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const Bootstrap(),
    );
  }
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = Api.I.loadConfig();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return ErrorPage(
              error: snapshot.error,
              retry: () => setState(() => future = Api.I.loadConfig()),
            );
          }
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final cfg = snapshot.data!;
        if (cfg['enabled'] == false) {
          return RemoteMessage(
            icon: Icons.mobile_off,
            title: Api.I.ar ? 'التطبيق متوقف مؤقتًا' : 'App unavailable',
            text: Api.I.ar
                ? 'التطبيق غير متاح حاليًا.'
                : 'The app is currently unavailable.',
          );
        }
        if (cfg['maintenance'] == true) {
          return RemoteMessage(
            icon: Icons.construction,
            title: Api.I.ar ? 'صيانة' : 'Maintenance',
            text: (cfg['maintenance_message'] ?? '').toString(),
          );
        }
        return FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, version) {
            if (!version.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            final versions = cfg['versions'];
            final android = versions is Map ? versions['android'] : null;
            final min = android is Map ? (android['min'] ?? '').toString() : '';
            final url = android is Map ? (android['url'] ?? '').toString() : '';
            if (cfg['force_update'] == true &&
                min.isNotEmpty &&
                versionLess(version.data!.version, min)) {
              return UpdatePage(url: url);
            }
            return const Shell();
          },
        );
      },
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  List<_NavItem> items() {
    final a = Api.I;
    final out = <_NavItem>[
      _NavItem(Icons.home_outlined, Icons.home, a.ar ? 'الرئيسية' : 'Home',
          const ProHomePage()),
      _NavItem(Icons.video_library_outlined, Icons.video_library,
          a.ar ? 'المكتبة' : 'Browse', const ProBrowsePage()),
    ];
    if (a.section('tv')) {
      out.add(_NavItem(Icons.live_tv_outlined, Icons.live_tv,
          a.ar ? 'القنوات' : 'TV', const ProTvPage()));
    }
    if (a.section('search')) {
      out.add(_NavItem(Icons.search, Icons.search,
          a.ar ? 'بحث' : 'Search', const ProSearchPage()));
    }
    if (a.section('account')) {
      out.add(_NavItem(Icons.person_outline, Icons.person,
          a.ar ? 'حسابي' : 'Account', const ProAccountPage()));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nav = items();
    if (index >= nav.length) index = 0;
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: nav.map((e) => e.page).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: nav
            .map((e) => NavigationDestination(
                  icon: Icon(e.icon),
                  selectedIcon: Icon(e.selected),
                  label: e.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon, selected;
  final String label;
  final Widget page;
  _NavItem(this.icon, this.selected, this.label, this.page);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = Api.I.call('home');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await Api.I.loadConfig();
          setState(() => future = Api.I.call('home'));
          await future;
        },
        child: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return ErrorPage(
                  error: snapshot.error,
                  retry: () => setState(() => future = Api.I.call('home')),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }
            final data =
                Map<String, dynamic>.from(snapshot.data!['data'] as Map);
            final sections = data['sections'] as List? ?? const [];
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  title: Text(
                    (Api.I.config['name'] ?? appDisplayName).toString(),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  actions: [
                    IconButton(
                      onPressed: () async {
                        Api.I.locale = Api.I.ar ? 'en' : 'ar';
                        await Api.I.loadConfig();
                        setState(() => future = Api.I.call('home'));
                      },
                      icon: const Icon(Icons.language),
                    )
                  ],
                ),
                const SliverToBoxAdapter(child: AppAd('app_home_top')),
                ...sections.map(
                  (raw) => SliverToBoxAdapter(
                    child: MediaSection(
                      data: Map<String, dynamic>.from(raw as Map),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class MediaSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const MediaSection({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final items = data['items'] as List? ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              (data['title'] ?? '').toString(),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => MediaCard(
                item: Map<String, dynamic>.from(items[i] as Map),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MediaCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  const MediaCard({super.key, required this.item, this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ?? () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProDetailPage(id: (item['id'] as num).toInt()),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: Api.I.absoluteUrl(item['poster']),
                  width: 142,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Container(color: Colors.white10),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              (item['title'] ?? item['original_title'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});
  @override
  Widget build(BuildContext context) {
    final types = <String>[];
    if (Api.I.section('movies')) types.add('movie');
    if (Api.I.section('series')) types.add('series');
    if (Api.I.section('short_series')) types.add('short_series');
    if (types.isEmpty) {
      return Center(child: Text(Api.I.ar ? 'لا توجد أقسام' : 'No sections'));
    }
    return DefaultTabController(
      length: types.length,
      child: SafeArea(
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabs: types
                  .map((t) => Tab(
                      text: t == 'movie'
                          ? (Api.I.ar ? 'أفلام' : 'Movies')
                          : t == 'series'
                              ? (Api.I.ar ? 'مسلسلات' : 'Series')
                              : (Api.I.ar ? 'قصيرة' : 'Shorts')))
                  .toList(),
            ),
            Expanded(
              child: TabBarView(
                children: types.map((t) => MediaGrid(type: t)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MediaGrid extends StatefulWidget {
  final String type;
  const MediaGrid({super.key, required this.type});
  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = Api.I.call('media', query: {'type': widget.type, 'limit': 50});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (_, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!['data'] as List? ?? const [];
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: .58,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemCount: rows.length,
          itemBuilder: (_, i) =>
              MediaCard(item: Map<String, dynamic>.from(rows[i] as Map)),
        );
      },
    );
  }
}

class DetailPage extends StatefulWidget {
  final int id;
  const DetailPage({super.key, required this.id});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = Api.I.call('media_detail', query: {'id': widget.id});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final item =
              Map<String, dynamic>.from(snapshot.data!['data'] as Map);
          final seasons = item['seasons'] as List? ?? const [];
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 330,
                flexibleSpace: FlexibleSpaceBar(
                  background: CachedNetworkImage(
                    imageUrl:
                        (item['backdrop'] ?? item['poster'] ?? '').toString(),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.white10),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const AppAd('app_details'),
                    Text(
                      (item['title'] ?? item['original_title'] ?? '').toString(),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        if (item['type'] == 'movie') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProPlayerPage(
                                ownerType: 'media',
                                ownerId: widget.id,
                                title: (item['title'] ?? '').toString(),
                              ),
                            ),
                          );
                        } else if (seasons.isNotEmpty) {
                          final first =
                              Map<String, dynamic>.from(seasons.first as Map);
                          final episodes =
                              first['episodes'] as List? ?? const [];
                          if (episodes.isNotEmpty) {
                            final ep = Map<String, dynamic>.from(
                                episodes.first as Map);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProPlayerPage(
                                  ownerType: 'episode',
                                  ownerId: (ep['id'] as num).toInt(),
                                  title: (ep['title'] ?? '').toString(),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text(Api.I.ar ? 'تشغيل' : 'Play'),
                    ),
                    const SizedBox(height: 14),
                    Text((item['overview'] ?? item['story'] ?? '').toString()),
                    ...seasons.map((raw) {
                      final season =
                          Map<String, dynamic>.from(raw as Map);
                      final episodes =
                          season['episodes'] as List? ?? const [];
                      return ExpansionTile(
                        title: Text((Api.I.ar ? 'الموسم ' : 'Season ') +
                            season['season_number'].toString()),
                        children: episodes.map((rawEp) {
                          final ep =
                              Map<String, dynamic>.from(rawEp as Map);
                          return ListTile(
                            title: Text(
                              ep['episode_number'].toString() +
                                  '. ' +
                                  (ep['title'] ?? '').toString(),
                            ),
                            trailing: const Icon(Icons.play_arrow),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProPlayerPage(
                                  ownerType: 'episode',
                                  ownerId: (ep['id'] as num).toInt(),
                                  title: (ep['title'] ?? '').toString(),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LegacyPlayerPage extends StatefulWidget {
  final String ownerType;
  final int ownerId;
  final String title;
  const LegacyPlayerPage({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.title,
  });
  @override
  State<LegacyPlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<LegacyPlayerPage> {
  late final Player player;
  late final VideoController controller;
  List<Map<String, dynamic>> sources = [];
  bool loading = true;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) => saveProgress());
  }

  Future<void> load() async {
    try {
      final result = await Api.I.call(
        'playback',
        query: {'owner_type': widget.ownerType, 'owner_id': widget.ownerId},
      );
      final data = Map<String, dynamic>.from(result['data'] as Map);
      sources = (data['sources'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (sources.isEmpty) throw Exception('No playback source');
      await open(0);
      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString(); });
    }
  }

  Future<void> open(int index) async {
    final source = sources[index];
    await player.open(Media((source['url'] ?? '').toString()), play: true);
  }

  Future<void> saveProgress() async {
    if (widget.ownerType == 'tv') return;
    final d = player.state.duration.inSeconds;
    final p = player.state.position.inSeconds;
    if (d <= 0) return;
    try {
      await Api.I.call(
        'progress',
        method: 'POST',
        data: {
          'owner_type': widget.ownerType,
          'owner_id': widget.ownerId,
          'progress_seconds': p,
          'duration_seconds': d,
        },
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    saveProgress();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.title)),
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : error != null
                ? ErrorPage(error: error, retry: load)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AppAd('app_player_pre'),
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Video(
                          controller: controller,
                          controls: AdaptiveVideoControls,
                        ),
                      ),
                      if (sources.length > 1)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                            spacing: 8,
                            children: List.generate(
                              sources.length,
                              (i) => ActionChip(
                                label: Text(
                                    (sources[i]['label'] ?? 'Server').toString()),
                                onPressed: () => open(i),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class TvPage extends StatefulWidget {
  const TvPage({super.key});
  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = Api.I.call('channels', query: {'limit': 50});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!['data'] as List? ?? const [];
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              childAspectRatio: 1.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final channel =
                  Map<String, dynamic>.from(rows[i] as Map);
              return Card(
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProPlayerPage(
                        ownerType: 'tv',
                        ownerId: (channel['id'] as num).toInt(),
                        title: (channel['name'] ?? '').toString(),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: CachedNetworkImage(
                          imageUrl: (channel['logo'] ?? '').toString(),
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.live_tv, size: 48),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          (channel['name'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final q = TextEditingController();
  Future<Map<String, dynamic>>? future;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              controller: q,
              hintText: Api.I.ar ? 'بحث عربي أو إنجليزي' : 'Search',
              leading: const Icon(Icons.search),
              onSubmitted: (v) => setState(() =>
                  future = Api.I.call('media', query: {'q': v, 'limit': 50})),
            ),
          ),
          Expanded(
            child: future == null
                ? const Center(child: Icon(Icons.search, size: 60))
                : FutureBuilder<Map<String, dynamic>>(
                    future: future,
                    builder: (_, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rows = snapshot.data!['data'] as List? ?? const [];
                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: .58,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => MediaCard(
                          item: Map<String, dynamic>.from(rows[i] as Map),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: Api.I.call('me'),
        builder: (_, snapshot) {
          if (snapshot.hasError) return const LoginPage();
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user =
              Map<String, dynamic>.from(snapshot.data!['data'] as Map);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CircleAvatar(
                radius: 42,
                backgroundImage: (user['avatar'] ?? '').toString().isEmpty
                    ? null
                    : NetworkImage(user['avatar'].toString()),
                child: (user['avatar'] ?? '').toString().isEmpty
                    ? const Icon(Icons.person, size: 40)
                    : null,
              ),
              const SizedBox(height: 12),
              Center(
                  child: Text((user['name'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900))),
              if (Api.I.section('continue_watching'))
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(Api.I.ar ? 'متابعة المشاهدة' : 'Continue'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContinuePage()),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(Api.I.ar ? 'تسجيل الخروج' : 'Logout'),
                onTap: () async {
                  await Api.I.logout();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountPage()),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController();
  bool busy = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: email,
            decoration: InputDecoration(labelText: Api.I.ar ? 'البريد' : 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: pass,
            obscureText: true,
            decoration:
                InputDecoration(labelText: Api.I.ar ? 'كلمة المرور' : 'Password'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await Api.I.login(email.text, pass.text);
                      if (context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const AccountPage()),
                        );
                      }
                    } catch (e) {
                      setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(Api.I.ar ? 'دخول' : 'Sign in'),
          )
        ],
      ),
    );
  }
}

class ContinuePage extends StatelessWidget {
  const ContinuePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Api.I.ar ? 'متابعة المشاهدة' : 'Continue')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: Api.I.call('continue'),
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!['data'] as List? ?? const [];
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final row = Map<String, dynamic>.from(rows[i] as Map);
              final media =
                  Map<String, dynamic>.from(row['media'] as Map);
              return ListTile(
                title: Text((media['title'] ?? media['original_title'] ?? '')
                    .toString()),
              );
            },
          );
        },
      ),
    );
  }
}

class AppAd extends StatelessWidget {
  final String placement;
  const AppAd(this.placement, {super.key});
  @override
  Widget build(BuildContext context) {
    final rows = Api.I.ads(placement);
    if (rows.isEmpty) return const SizedBox.shrink();
    final ad = rows.first;
    final image = (ad['image'] ?? '').toString();
    final text = (ad['code'] ?? '').toString();
    final url = (ad['url'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: InkWell(
        onTap: url.isEmpty
            ? null
            : () => launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: image.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(14),
                  color: Colors.white10,
                  child: Text(text, textAlign: TextAlign.center),
                )
              : CachedNetworkImage(
                  imageUrl: image,
                  height: 92,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
        ),
      ),
    );
  }
}

class RemoteMessage extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const RemoteMessage(
      {super.key, required this.icon, required this.title, required this.text});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 66),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class UpdatePage extends StatelessWidget {
  final String url;
  const UpdatePage({super.key, required this.url});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton.icon(
          onPressed: url.isEmpty
              ? null
              : () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.system_update),
          label: Text(Api.I.ar ? 'تحديث التطبيق' : 'Update app'),
        ),
      ),
    );
  }
}

class ErrorPage extends StatelessWidget {
  final Object? error;
  final VoidCallback retry;
  const ErrorPage({super.key, required this.error, required this.retry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: retry,
        icon: const Icon(Icons.refresh),
        label: Text(Api.I.ar ? 'إعادة المحاولة' : 'Retry'),
      ),
    );
  }
}

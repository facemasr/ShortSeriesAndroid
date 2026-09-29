import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'offline_downloads.dart';
part 'page_cache.dart';
part 'admob_ads.dart';
part 'admin_web_portal.dart';
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

  static bool owns(Player player) => identical(_active, player);

  static void claim(Player player) {
    final previous = _active;
    if (previous != null && !identical(previous, player)) {
      // Keep the previous route resumable, but never let two players
      // produce audio/video at the same time.
      unawaited(previous.pause());
    }
    _active = player;
  }

  static void release(Player player) {
    if (identical(_active, player)) _active = null;
  }
}

class AppShellController {
  static final ValueNotifier<int> tab=ValueNotifier<int>(0);

  static List<_NavItem> items(){
    final a=Api.I;
    final out=<_NavItem>[
      _NavItem(Icons.home_outlined,Icons.home,a.ar?'الرئيسية':'Home',const ProHomePage()),
      _NavItem(Icons.video_library_outlined,Icons.video_library,a.ar?'المكتبة':'Browse',const ProBrowsePage()),
    ];
    if(a.section('tv')){
      out.add(_NavItem(Icons.live_tv_outlined,Icons.live_tv,a.ar?'القنوات':'TV',const ProTvPage()));
    }
    if(a.section('search')){
      out.add(_NavItem(Icons.search_rounded,Icons.search,a.ar?'بحث':'Search',const ProSearchPage()));
    }
    if(a.section('account')){
      out.add(_NavItem(Icons.person_outline_rounded,Icons.person,a.ar?'حسابي':'Account',const ProAccountPage()));
    }
    return out;
  }

  static int indexFor(String key){
    final nav=items();
    if(key=='home')return 0;
    for(var i=0;i<nav.length;i++){
      final page=nav[i].page;
      if(key=='browse'&&page is ProBrowsePage)return i;
      if(key=='tv'&&page is ProTvPage)return i;
      if(key=='search'&&page is ProSearchPage)return i;
      if(key=='account'&&page is ProAccountPage)return i;
    }
    return 0;
  }

  static void go(BuildContext context,int index){
    final nav=items();
    if(nav.isEmpty)return;
    final safe=index.clamp(0,nav.length-1);
    tab.value=safe;
    Navigator.of(context).popUntil((route)=>route.isFirst);
  }

  static void goKey(BuildContext context,String key){
    go(context,indexFor(key));
  }
}

class AppNavigator {
  static const _managedPrefix = '/shortseries/';

  static bool _isManaged(BuildContext context) {
    final name = ModalRoute.of(context)?.settings.name ?? '';
    return name.startsWith(_managedPrefix);
  }

  static void open(
    BuildContext context,
    Widget page, {
    required String key,
  }) {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      settings: RouteSettings(name: '$_managedPrefix$key'),
      builder: (_) => page,
    );

    // Keep the Shell as the only page underneath the active content page.
    // Moving between details/player/person/TV replaces the current content
    // route instead of stacking another page over it.
    if (_isManaged(context)) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // None of the optional startup services should be able to prevent the
  // application UI from opening. A failure in ads, MediaKit, or cache cleanup
  // is isolated and the app continues to the first frame.
  try {
    MediaKit.ensureInitialized();
  } catch (error, stackTrace) {
    debugPrint('MediaKit startup error: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await AdMobService.I
        .initialize()
        .timeout(const Duration(seconds: 8));
  } catch (error, stackTrace) {
    debugPrint('AdMob startup error: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await OfflineDownloads.I
        .cleanupPlaybackCache()
        .timeout(const Duration(seconds: 8));
  } catch (error, stackTrace) {
    debugPrint('Playback-cache startup error: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await AppPageCache.I
        .cleanup()
        .timeout(const Duration(seconds: 8));
  } catch (error, stackTrace) {
    debugPrint('Page-cache startup error: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const ShortSerisApp());
}

class Api {
  Api._();
  static final I = Api._();
  final dio = Dio(BaseOptions(
    baseUrl: apiUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
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

  String _extractResolvedPlaybackUrl(dynamic value) {
    if (value == null) return '';

    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return '';

      if ((text.startsWith('{') && text.endsWith('}')) ||
          (text.startsWith('[') && text.endsWith(']'))) {
        try {
          return _extractResolvedPlaybackUrl(jsonDecode(text));
        } catch (_) {}
      }

      final uri = Uri.tryParse(text);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return text;
      }
      return '';
    }

    if (value is Map) {
      const directKeys = <String>[
        'resolved_url',
        'playback_url',
        'video_url',
        'media_url',
        'stream_url',
        'stream',
        'file',
        'src',
        'url',
      ];
      for (final key in directKeys) {
        if (!value.containsKey(key)) continue;
        final found = _extractResolvedPlaybackUrl(value[key]);
        if (found.isNotEmpty) return found;
      }

      const nestedKeys = <String>['data', 'result', 'source', 'sources', 'media'];
      for (final key in nestedKeys) {
        if (!value.containsKey(key)) continue;
        final found = _extractResolvedPlaybackUrl(value[key]);
        if (found.isNotEmpty) return found;
      }
      return '';
    }

    if (value is List) {
      for (final item in value) {
        final found = _extractResolvedPlaybackUrl(item);
        if (found.isNotEmpty) return found;
      }
    }

    return '';
  }

  Future<String> resolvePlaybackUrl(String sourceUrl) async {
    final normalized = absoluteUrl(sourceUrl);
    if (normalized.isEmpty) return '';

    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 45),
        followRedirects: true,
      ),
    );

    final payload = <String, dynamic>{
      'url': normalized,
      'src': normalized,
      'source': normalized,
    };

    try {
      final response = await client.post(
        'https://shortseris.online/media-resolve.php',
        data: payload,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: const {'Accept': 'application/json'},
        ),
      );
      final resolved = _extractResolvedPlaybackUrl(response.data);
      if (resolved.isNotEmpty) return resolved;
    } catch (_) {}

    try {
      final response = await client.post(
        'https://shortseris.online/media-resolve.php',
        data: FormData.fromMap(payload),
        options: Options(headers: const {'Accept': 'application/json'}),
      );
      final resolved = _extractResolvedPlaybackUrl(response.data);
      if (resolved.isNotEmpty) return resolved;
    } catch (_) {}

    return '';
  }

  Future<Map<String, dynamic>> call(
    String action, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? data,
    String method = 'GET',
    bool forceRefresh = false,
  }) async {
    final normalizedMethod=method.toUpperCase();
    final cacheable=AppPageCache.I.canCache(action,normalizedMethod);

    if(cacheable&&!forceRefresh){
      final fresh=await AppPageCache.I.read(
        action,
        locale,
        query,
        maxAge:AppPageCache.I.freshFor(action),
      );
      if(fresh!=null){
        return AppPageCache.I.mark(fresh,offline:false);
      }
    }

    final token = await store.read(key: 'token');
    try{
      final response = await dio.request(
        '',
        queryParameters: {'action': action, 'locale': locale, ...?query},
        data: data,
        options: Options(
          method: normalizedMethod,
          receiveTimeout: Duration(
            seconds: action.startsWith('admin_import')
                ? 120
                : (action == 'playback' || action == 'playback_refresh' ? 90 : 45),
          ),
          headers: token == null ? null : {'Authorization': 'Bearer ' + token},
        ),
      );
      final map = Map<String, dynamic>.from(response.data as Map);
      if (map['ok'] != true) throw Exception(map['error'] ?? 'Request failed');

      if(cacheable){
        unawaited(AppPageCache.I.write(action,locale,query,map));
      }
      return map;
    }catch(e){
      if(cacheable){
        final stale=await AppPageCache.I.read(
          action,
          locale,
          query,
          maxAge:AppPageCache.offlineMaxAge,
        );
        if(stale!=null){
          return AppPageCache.I.mark(stale,offline:true);
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadConfig({bool forceRefresh=false}) async {
    final result = await call('app_config',forceRefresh:forceRefresh);
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

  List<Map<String,dynamic>> rowsFrom(
    dynamic value, {
    List<String> keys=const [
      'items','rows','data','results','media','people','genres','works','filmography',
    ],
  }){
    if(value is List){
      return value
        .whereType<Map>()
        .map((e)=>Map<String,dynamic>.from(e))
        .toList();
    }
    if(value is Map){
      final map=Map<String,dynamic>.from(value);
      for(final key in keys){
        if(!map.containsKey(key))continue;
        final nested=map[key];
        if(nested is List){
          return nested
            .whereType<Map>()
            .map((e)=>Map<String,dynamic>.from(e))
            .toList();
        }
        if(nested is Map){
          final found=rowsFrom(nested,keys:keys);
          if(found.isNotEmpty)return found;
        }
      }
    }
    return const <Map<String,dynamic>>[];
  }

  List<Map<String,dynamic>> responseRows(
    Map<String,dynamic> response, {
    List<String> keys=const [
      'items','rows','data','results','media','people','genres','works','filmography',
    ],
  }){
    return rowsFrom(response['data']??response,keys:keys);
  }

  Map<String,dynamic> mapFrom(dynamic value){
    if(value is Map)return Map<String,dynamic>.from(value);
    return <String,dynamic>{};
  }

  String localizedValue(dynamic value){
    if(value==null)return '';
    if(value is Map){
      final map=Map<String,dynamic>.from(value);
      return (map[locale]??map[ar?'ar':'en']??map['ar']??map['en']??'').toString();
    }
    final raw=value.toString().trim();
    if(raw.startsWith('{')&&raw.endsWith('}')){
      try{
        final decoded=jsonDecode(raw);
        if(decoded is Map)return localizedValue(decoded);
      }catch(_){}
    }
    return raw;
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
            return OfflineLibraryPage(
              onRetry: () => setState(() => future = Api.I.loadConfig()),
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
  @override
  Widget build(BuildContext context) {
    final nav=AppShellController.items();
    return ValueListenableBuilder<int>(
      valueListenable:AppShellController.tab,
      builder:(_,selected,__){
        final index=selected.clamp(0,nav.length-1);
        if(index!=selected){
          WidgetsBinding.instance.addPostFrameCallback((_){
            if(AppShellController.tab.value!=index)AppShellController.tab.value=index;
          });
        }
        return Scaffold(
          body:IndexedStack(
            index:index,
            children:nav.map((e)=>e.page).toList(),
          ),
          bottomNavigationBar:NavigationBar(
            selectedIndex:index,
            onDestinationSelected:(v)=>AppShellController.tab.value=v,
            destinations:nav.map((e)=>NavigationDestination(
              icon:Icon(e.icon),
              selectedIcon:Icon(e.selected),
              label:e.label,
            )).toList(),
          ),
        );
      },
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
                const SliverToBoxAdapter(child: AdMobBanner(placement:'home')),
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
    final items=Api.I.rowsFrom(
      data['items']??data['rows']??data['media']??const [],
      keys:const ['items','rows','media','data','results'],
    );
    if(items.isEmpty)return const SizedBox.shrink();
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
              itemBuilder:(_,i)=>MediaCard(item:items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class MediaCard extends StatelessWidget {
  final Map<String,dynamic> item;
  final VoidCallback? onTap;
  const MediaCard({super.key,required this.item,this.onTap});

  int get _id=>int.tryParse((item['id']??item['media_id']??'').toString())??0;

  String get _title=>(item['_title']??item['title']??item['name']??item['original_title']??item['original_name']??'').toString().trim();

  String get _image{
    final direct=(item['poster']??item['poster_url']??item['image']??'').toString().trim();
    if(direct.isNotEmpty)return Api.I.absoluteUrl(direct);
    final posterPath=(item['poster_path']??'').toString().trim();
    if(posterPath.isNotEmpty){
      return 'https://image.tmdb.org/t/p/w500${posterPath.startsWith('/')?posterPath:'/$posterPath'}';
    }
    return '';
  }

  String get _typeLabel{
    final type=(item['type']??item['media_type']??'').toString();
    if(type=='movie')return Api.I.ar?'فيلم':'Movie';
    if(type=='series'||type=='tv')return Api.I.ar?'مسلسل':'Series';
    if(type=='short_series')return Api.I.ar?'قصير':'Short';
    return '';
  }

  @override
  Widget build(BuildContext context){
    final year=(item['year']??'').toString().trim();
    final rating=(item['rating']??'').toString().trim();
    final image=_image;
    final id=_id;

    return SizedBox(
      width:148,
      child:Material(
        color:const Color(0xFF101114),
        borderRadius:BorderRadius.circular(15),
        clipBehavior:Clip.antiAlias,
        child:InkWell(
        onTap:onTap??(id<=0?null:(){
          AppNavigator.open(
            context,
            ProDetailPage(id:id),
            key:'media/$id',
          );
        }),
        child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Expanded(
              child:Stack(
                fit:StackFit.expand,
                children:[
                  if(image.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl:image,
                      fit:BoxFit.cover,
                      placeholder:(_,__)=>Container(color:const Color(0xFF17181C)),
                      errorWidget:(_,__,___)=>Container(
                        color:const Color(0xFF17181C),
                        child:const Icon(Icons.movie_creation_outlined,size:42,color:Colors.white24),
                      ),
                    )
                  else
                    Container(
                      color:const Color(0xFF17181C),
                      child:const Icon(Icons.movie_creation_outlined,size:42,color:Colors.white24),
                    ),
                  const Positioned.fill(
                    child:DecoratedBox(
                      decoration:BoxDecoration(
                        gradient:LinearGradient(
                          begin:Alignment.topCenter,
                          end:Alignment.bottomCenter,
                          colors:[Colors.transparent,Color(0x0A000000),Color(0xB8000000)],
                          stops:[0,.64,1],
                        ),
                      ),
                    ),
                  ),
                  if(_typeLabel.isNotEmpty)
                    PositionedDirectional(
                      start:7,
                      top:7,
                      child:Container(
                        padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),
                        decoration:BoxDecoration(
                          color:const Color(0xD9000000),
                          borderRadius:BorderRadius.circular(7),
                        ),
                        child:Text(
                          _typeLabel,
                          style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w900),
                        ),
                      ),
                    ),
                  if(rating.isNotEmpty&&rating!='0'&&rating!='0.0')
                    PositionedDirectional(
                      end:7,
                      top:7,
                      child:Container(
                        padding:const EdgeInsets.symmetric(horizontal:6,vertical:4),
                        decoration:BoxDecoration(
                          color:const Color(0xD9000000),
                          borderRadius:BorderRadius.circular(7),
                        ),
                        child:Text(
                          '★ $rating',
                          style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding:const EdgeInsets.fromLTRB(9,8,9,9),
              child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text(
                    _title.isEmpty?(Api.I.ar?'بدون عنوان':'Untitled'):_title,
                    maxLines:1,
                    overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontSize:12.5,fontWeight:FontWeight.w900),
                  ),
                  const SizedBox(height:3),
                  Text(
                    [if(year.isNotEmpty)year,if(_typeLabel.isNotEmpty)_typeLabel].join(' • '),
                    maxLines:1,
                    overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontSize:10.5,color:Colors.white54),
                  ),
                ],
              ),
            ),
          ],
          ),
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
                    const AdMobBanner(placement:'details'),
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
                          AppNavigator.open(
                            context,
                            ProPlayerPage(
                              ownerType: 'media',
                              ownerId: widget.id,
                              title: (item['title'] ?? '').toString(),
                            ),
                            key: 'player/media/${widget.id}',
                          );
                        } else if (seasons.isNotEmpty) {
                          final first =
                              Map<String, dynamic>.from(seasons.first as Map);
                          final episodes =
                              first['episodes'] as List? ?? const [];
                          if (episodes.isNotEmpty) {
                            final ep = Map<String, dynamic>.from(
                                episodes.first as Map);
                            final epId = (ep['id'] as num).toInt();
                            AppNavigator.open(
                              context,
                              ProPlayerPage(
                                ownerType: 'episode',
                                ownerId: epId,
                                title: (ep['title'] ?? '').toString(),
                              ),
                              key: 'player/episode/$epId',
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
                            onTap: () {
                              final epId = (ep['id'] as num).toInt();
                              AppNavigator.open(
                                context,
                                ProPlayerPage(
                                  ownerType: 'episode',
                                  ownerId: epId,
                                  title: (ep['title'] ?? '').toString(),
                                ),
                                key: 'player/episode/$epId',
                              );
                            },
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
                      const AdMobBanner(placement:'player',compact:true),
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
                  onTap: () {
                    final channelId = (channel['id'] as num).toInt();
                    AppNavigator.open(
                      context,
                      ProPlayerPage(
                        ownerType: 'tv',
                        ownerId: channelId,
                        title: (channel['name'] ?? '').toString(),
                      ),
                      key: 'player/tv/$channelId',
                    );
                  },
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
                  onTap: () => AppNavigator.open(
                    context,
                    const ContinuePage(),
                    key: 'account/continue',
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
  final VoidCallback? onAuthenticated;
  const LoginPage({super.key,this.onAuthenticated});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final formKey=GlobalKey<FormState>();
  final email=TextEditingController();
  final pass=TextEditingController();

  bool busy=false;
  bool showPassword=false;
  String? error;

  @override
  void dispose(){
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  String? _emailValidator(String? value){
    final v=(value??'').trim();
    if(v.isEmpty)return Api.I.ar?'أدخل البريد الإلكتروني':'Enter your email';
    if(!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)){
      return Api.I.ar?'البريد الإلكتروني غير صحيح':'Enter a valid email';
    }
    return null;
  }

  String? _passwordValidator(String? value){
    if((value??'').length<8){
      return Api.I.ar?'كلمة المرور يجب أن تكون 8 أحرف على الأقل':'Password must be at least 8 characters';
    }
    return null;
  }

  Future<void> _submit() async{
    FocusScope.of(context).unfocus();
    if(!(formKey.currentState?.validate()??false))return;

    setState((){busy=true;error=null;});
    try{
      await Api.I.login(email.text,pass.text);
      if(!mounted)return;
      if(widget.onAuthenticated!=null){
        widget.onAuthenticated!();
      }else{
        AppNavigator.open(
          context,
          const AccountPage(),
          key:'account/profile',
        );
      }
    }catch(e){
      if(!mounted)return;
      setState((){
        error=Api.I.ar
          ?'تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور.'
          :'Sign in failed. Check your email and password.';
      });
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  Future<void> _openRegister() async{
    final locale=Api.I.ar?'ar':'en';
    final uri=Uri.parse('https://shortseris.online/$locale/register');
    await launchUrl(uri,mode:LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context){
    return SafeArea(
      child:Center(
        child:SingleChildScrollView(
          padding:const EdgeInsets.fromLTRB(20,24,20,32),
          child:ConstrainedBox(
            constraints:const BoxConstraints(maxWidth:460),
            child:Card(
              elevation:0,
              clipBehavior:Clip.antiAlias,
              child:Padding(
                padding:const EdgeInsets.fromLTRB(22,26,22,24),
                child:Form(
                  key:formKey,
                  child:Column(
                    crossAxisAlignment:CrossAxisAlignment.stretch,
                    children:[
                      Center(
                        child:Container(
                          width:68,
                          height:68,
                          decoration:BoxDecoration(
                            color:const Color(0xFFE50914),
                            borderRadius:BorderRadius.circular(20),
                          ),
                          alignment:Alignment.center,
                          child:const Text(
                            'S',
                            style:TextStyle(
                              fontSize:34,
                              fontWeight:FontWeight.w900,
                              color:Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height:16),
                      Text(
                        'SHORT SERIES TV',
                        textAlign:TextAlign.center,
                        style:Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight:FontWeight.w900,
                          letterSpacing:.3,
                        ),
                      ),
                      const SizedBox(height:6),
                      Text(
                        Api.I.ar
                          ?'سجّل دخولك لمزامنة المشاهدة والمفضلة وقائمتك على جميع أجهزتك.'
                          :'Sign in to sync progress, favorites and your list across devices.',
                        textAlign:TextAlign.center,
                        style:const TextStyle(color:Colors.white60,height:1.5),
                      ),
                      const SizedBox(height:24),
                      TextFormField(
                        controller:email,
                        keyboardType:TextInputType.emailAddress,
                        autofillHints:const [AutofillHints.email],
                        textInputAction:TextInputAction.next,
                        validator:_emailValidator,
                        decoration:InputDecoration(
                          labelText:Api.I.ar?'البريد الإلكتروني':'Email',
                          hintText:'name@example.com',
                          prefixIcon:const Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height:14),
                      TextFormField(
                        controller:pass,
                        obscureText:!showPassword,
                        autofillHints:const [AutofillHints.password],
                        textInputAction:TextInputAction.done,
                        onFieldSubmitted:(_)=>_submit(),
                        validator:_passwordValidator,
                        decoration:InputDecoration(
                          labelText:Api.I.ar?'كلمة المرور':'Password',
                          prefixIcon:const Icon(Icons.lock_outline_rounded),
                          suffixIcon:IconButton(
                            onPressed:()=>setState(()=>showPassword=!showPassword),
                            icon:Icon(showPassword?Icons.visibility_off_rounded:Icons.visibility_rounded),
                          ),
                        ),
                      ),
                      if(error!=null)...[
                        const SizedBox(height:14),
                        Container(
                          padding:const EdgeInsets.all(12),
                          decoration:BoxDecoration(
                            color:Colors.red.withValues(alpha:.10),
                            borderRadius:BorderRadius.circular(12),
                            border:Border.all(color:Colors.red.withValues(alpha:.35)),
                          ),
                          child:Row(
                            children:[
                              const Icon(Icons.error_outline_rounded,color:Colors.redAccent),
                              const SizedBox(width:10),
                              Expanded(child:Text(error!,style:const TextStyle(color:Colors.redAccent))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height:18),
                      FilledButton.icon(
                        onPressed:busy?null:_submit,
                        icon:busy
                          ?const SizedBox(
                              width:18,
                              height:18,
                              child:CircularProgressIndicator(strokeWidth:2),
                            )
                          :const Icon(Icons.login_rounded),
                        label:Text(Api.I.ar?'تسجيل الدخول':'Sign in'),
                      ),
                      const SizedBox(height:12),
                      Row(
                        children:[
                          const Expanded(child:Divider()),
                          Padding(
                            padding:const EdgeInsets.symmetric(horizontal:12),
                            child:Text(
                              Api.I.ar?'أو':'OR',
                              style:const TextStyle(color:Colors.white38,fontWeight:FontWeight.w700),
                            ),
                          ),
                          const Expanded(child:Divider()),
                        ],
                      ),
                      const SizedBox(height:12),
                      OutlinedButton.icon(
                        onPressed:_openRegister,
                        icon:const Icon(Icons.person_add_alt_1_rounded),
                        label:Text(Api.I.ar?'إنشاء حساب جديد':'Create account'),
                      ),
                      const SizedBox(height:12),
                      Text(
                        Api.I.ar
                          ?'يتم إنشاء الحساب عبر موقع SHORT SERIES ثم يمكنك استخدام نفس الحساب داخل التطبيق.'
                          :'Create your account on SHORT SERIES, then use the same account in the app.',
                        textAlign:TextAlign.center,
                        style:const TextStyle(fontSize:12,color:Colors.white38,height:1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
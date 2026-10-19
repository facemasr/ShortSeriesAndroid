import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF101013),
    systemNavigationBarColor: Color(0xFF101013),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const EgyshowApp());
}

class EgyshowApp extends StatelessWidget {
  const EgyshowApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EGYSHOW',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0B0D),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE50914), brightness: Brightness.dark),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF101013),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        home: const EgyshowHome(),
      );
}

class EgyshowHome extends StatefulWidget {
  const EgyshowHome({super.key});
  @override
  State<EgyshowHome> createState() => _EgyshowHomeState();
}

class _EgyshowHomeState extends State<EgyshowHome> {
  static const root = 'https://egyshow.com';
  late final WebViewController controller;
  String lang = 'ar';
  bool loading = true;
  bool failed = false;
  int active = 0;
  int progress = 0;

  final List<String> routes = ['', 'movies', 'series', 'short-series', 'channels'];
  final List<IconData> icons = [
    Icons.home_rounded, Icons.movie_outlined, Icons.tv_rounded,
    Icons.smart_display_outlined, Icons.live_tv_rounded,
  ];

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0B0D))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { loading = true; failed = false; });
        },
        onProgress: (v) {
          if (mounted) setState(() => progress = v);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => loading = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() { loading = false; failed = true; });
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme == 'about' || uri.scheme == 'data' ||
              uri.scheme == 'blob') {
            return NavigationDecision.navigate;
          }
          if (uri.scheme == 'https' &&
              (uri.host == 'egyshow.com' ||
               uri.host == 'www.egyshow.com')) {
            return NavigationDecision.navigate;
          }
          if (!request.isMainFrame && (uri.scheme == 'https' ||
              uri.scheme == 'http')) {
            return NavigationDecision.navigate;
          }
          if (request.isMainFrame) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse('$root/ar'));
  }

  void open(int i) {
    setState(() { active = i; failed = false; });
    final route = routes[i];
    controller.loadRequest(Uri.parse('$root/$lang${route.isEmpty ? '' : '/$route'}'));
  }

  void openSpecial(String path) {
    setState(() => failed = false);
    controller.loadRequest(Uri.parse('$root/$lang/$path'));
  }

  void switchLang() {
    setState(() => lang = lang == 'ar' ? 'en' : 'ar');
    open(active);
  }

  Future<void> back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else if (active != 0) {
      open(0);
    }
  }

  String label(int i) {
    const ar = ['الرئيسية', 'أفلام', 'مسلسلات', 'قصيرة', 'مباشر'];
    const en = ['Home', 'Movies', 'Series', 'Shorts', 'Live'];
    return (lang == 'ar' ? ar : en)[i];
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) back();
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 14,
            title: const Text('EGYSHOW',
                style: TextStyle(color: Color(0xFFE50914),
                    fontSize: 23, fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
            actions: [
              IconButton(
                tooltip: lang == 'ar' ? 'بحث' : 'Search',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => controller.loadRequest(Uri.parse('$root/?search=1')),
              ),
              IconButton(
                tooltip: lang == 'ar' ? 'الحساب' : 'Account',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => controller.loadRequest(Uri.parse('$root/?account=1')),
              ),
              TextButton(
                onPressed: switchLang,
                child: Text(lang == 'ar' ? 'EN' : 'عربي',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          body: Stack(children: [
            WebViewWidget(controller: controller),
            if (loading)
              LinearProgressIndicator(
                value: progress > 0 && progress < 100 ? progress / 100 : null,
                minHeight: 2, color: const Color(0xFFE50914),
              ),
            if (failed)
              Container(
                color: const Color(0xFF0B0B0D),
                child: Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 50,
                        color: Colors.white60),
                    const SizedBox(height: 16),
                    Text(lang == 'ar' ? 'تعذر فتح الموقع' : 'Unable to open website'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: Text(lang == 'ar' ? 'إعادة المحاولة' : 'Retry'),
                      onPressed: () { setState(() => failed = false); controller.reload(); },
                    ),
                  ],
                )),
              ),
          ]),
          bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF101013),
            indicatorColor: const Color(0xFF5E1116),
            selectedIndex: active,
            height: 66,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: open,
            destinations: List.generate(routes.length,
              (i) => NavigationDestination(
                icon: Icon(icons[i], size: 23),
                label: label(i))),
          ),
        ),
      );
}

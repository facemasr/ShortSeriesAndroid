import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// EGY TV Sport sponsor placements, isolated from media playback.
/// WebView main-frame redirects and scripted popup windows are not permitted.
const _adHost = 'astrayentireillegimateillegimate.com';
const _sponsorUri = 'https://' + _adHost +
    '/qb38ute8?key=4ea2e7f9933440d5d1130955eff103c3';

class EgyTvSportAd extends StatefulWidget {
  const EgyTvSportAd({super.key, this.large = false});
  final bool large;
  @override
  State<EgyTvSportAd> createState() => _EgyTvSportAdState();
}

class _EgyTvSportAdState extends State<EgyTvSportAd> {
  late final WebViewController controller;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF101827))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          if (uri?.scheme == 'about' || uri?.host == 'egyshow.com') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ));
    controller.loadHtmlString(widget.large ? _nativeHtml : _bannerHtml,
        baseUrl: 'https://egyshow.com/');
  }

  static const _head = '''
<!DOCTYPE html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<style>html,body{margin:0;padding:0;overflow:hidden;background:#101827;color:#93a1b8;
font:11px Arial,sans-serif;}#ad{margin:0 auto;position:relative;overflow:hidden}</style>
</head><body>
''';

  static const _bannerHtml = _head + '''
<div id="ad" style="width:728px;height:90px;transform-origin:top left">
<script>
atOptions = {
  'key':'37ea6330594f94801f2ba1eb50c762a0',
  'format':'iframe','height':90,'width':728,'params':{}
};
</script>
<script src="https://astrayentireillegimateillegimate.com/37ea6330594f94801f2ba1eb50c762a0/invoke.js"></script>
</div>
<script>function scaleAd(){var s=Math.min(1,document.documentElement.clientWidth/728);
document.getElementById('ad').style.transform='scale('+s+')';}
scaleAd();window.addEventListener('resize',scaleAd);</script>
</body></html>
''';

  static const _nativeHtml = _head + '''
<div style="padding:5px;text-align:center;font-size:11px">Sponsored</div>
<script src="https://astrayentireillegimateillegimate.com/d2/43/03/d24303fd885d9222450141c5f7ec81e9.js"></script>
<div id="container-f2d83af2e65a70897bc7682d2a8aa66e"></div>
<script async="async" data-cfasync="false"
src="https://astrayentireillegimateillegimate.com/f2d83af2e65a70897bc7682d2a8aa66e/invoke.js"></script>
</body></html>
''';

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 24;
    final width = available < 728 ? available : 728.0;
    final height = widget.large ? 255.0 : 90 * (width / 728) + 7;
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: width, height: height,
          child: WebViewWidget(controller: controller)),
      ),
    ));
  }
}

/// A sponsored URL opens only after the viewer taps the clearly labeled link.
class EgyTvSportSponsorLink extends StatelessWidget {
  const EgyTvSportSponsorLink({super.key, required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: OutlinedButton.icon(
      onPressed: () async {
        await launchUrl(Uri.parse(_sponsorUri),
            mode: LaunchMode.externalApplication);
      },
      icon: const Icon(Icons.open_in_new_rounded, size: 17),
      label: Text(ar ? 'إعلان ممول' : 'Sponsored link'),
    ),
  );
}

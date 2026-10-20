import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'native_api.dart';

/// Display only banner campaigns already configured in the EGYSHOW ads manager.
/// It deliberately does not invent ads, hard-code networks, or alter player ads.
class EgyshowBannerAd extends StatefulWidget {
  const EgyshowBannerAd({super.key, required this.api, this.placement = 'home',
    this.height = 92});
  final EgyApi api;
  final String placement;
  final double height;
  @override
  State<EgyshowBannerAd> createState() => _EgyshowBannerAdState();
}

class _EgyshowBannerAdState extends State<EgyshowBannerAd> {
  WebViewController? browser;
  Map<String, dynamic>? banner;
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      // The public playback context exposes the current active ad campaigns.
      // Do not use video pre-roll, pause, or click-pop advertisements as banners.
      final ctx = await widget.api.playerContext('movie', 26926);
      final ads = asList(ctx['ads']).map(asMap).where((ad) {
        final placement = txt(ad['placement']).toLowerCase();
        final format = txt(ad['format']).toLowerCase();
        final active = ad['is_active'] == true || ad['is_active'] == 1;
        final bannerPlacement = placement.contains('banner') ||
            placement == widget.placement || placement == 'global';
        return active && bannerPlacement &&
          (format == 'image' || format == 'html' || format == 'script' ||
           txt(ad['code_html']).isNotEmpty);
      }).toList();
      if (ads.isEmpty || !mounted) return;
      ads.sort((a,b) => numId(b['priority']).compareTo(numId(a['priority'])));
      final selected = ads.first;
      final html = txt(selected['code_html']);
      if (html.isNotEmpty) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.transparent);
        await controller.loadHtmlString(
          '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>'
          '<body style="margin:0;display:flex;align-items:center;justify-content:center;background:transparent;overflow:hidden">'
          + html + '</body></html>',
          baseUrl: 'https://egyshow.com/',
        );
        browser = controller;
      }
      if (mounted) setState(() => banner = selected);
    } catch (_) {
      // Never block catalog navigation if a banner cannot load.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = banner;
    if (ad == null) return const SizedBox.shrink();
    final image = txt(ad['media_url']).isNotEmpty
      ? txt(ad['media_url']) : txt(ad['creative_url']);
    if (browser == null && !image.startsWith('https://')) {
      return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: SizedBox(height: widget.height, child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: browser != null
          ? WebViewWidget(controller: browser!)
          : Image.network(image, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      )));
  }
}

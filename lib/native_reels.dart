import 'package:flutter/material.dart';
import 'native_api.dart';
import 'native_player.dart';

/// TikTok-style vertical episode browsing, while each playable page embeds
/// the *same* EGYSHOW player and its website-managed adverts.
class EpisodeReels extends StatefulWidget {
  const EpisodeReels({
    super.key,
    required this.media,
    required this.episodes,
    required this.ar,
    this.initialIndex = 0,
    this.token,
  });
  final Media media;
  final List<Episode> episodes;
  final bool ar;
  final int initialIndex;
  final String? token;

  @override
  State<EpisodeReels> createState() => _EpisodeReelsState();
}

class _EpisodeReelsState extends State<EpisodeReels> {
  late final PageController pages;
  late int current;
  @override
  void initState() {
    super.initState();
    current = widget.initialIndex.clamp(0, widget.episodes.length - 1);
    pages = PageController(initialPage: current);
  }
  void move(int delta) {
    final next = current + delta;
    if (next < 0 || next >= widget.episodes.length) return;
    pages.animateToPage(next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic);
  }
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) {
      return Scaffold(appBar: AppBar(), body:
        const Center(child: Text('لا توجد حلقات')));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Stack(children: [
        PageView.builder(
          controller: pages,
          scrollDirection: Axis.vertical,
          onPageChanged: (v) => setState(() => current = v),
          itemCount: widget.episodes.length,
          itemBuilder: (ctx, index) {
            final ep = widget.episodes[index];
            if (index != current) {
              return ColoredBox(color: Colors.black,
                child: Center(child: Text(ep.title(widget.ar),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22))));
            }
            return EgyshowSitePlayer(
              key: ValueKey('egyshow-episode-' + ep.id.toString()),
              type: 'episode', id: ep.id,
              mediaId: widget.media.id,
              token: widget.token,
              title: ep.title(widget.ar),
              reelMode: true,
            );
          },
        ),
        Positioned(top: 6, left: 6, right: 65,
          child: Row(children: [
            Material(color: const Color(0xBB000000), shape: const CircleBorder(),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white))),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.media.title(widget.ar),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold))),
            Text((current + 1).toString() + '/' +
              widget.episodes.length.toString()),
          ])),
        // This edge rail guarantees episode navigation if Android WebView
        // captures the touch gestures over the website's player.
        Positioned(right: 0, top: 66, bottom: 62, width: 52,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -90) move(1);
              if (v > 90) move(-1);
            },
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                onPressed: current > 0 ? () => move(-1) : null,
                icon: const Icon(Icons.keyboard_arrow_up)),
              const SizedBox(height: 18),
              const Icon(Icons.swipe_vertical, size: 22, color: Colors.white70),
              const SizedBox(height: 18),
              IconButton.filledTonal(
                onPressed: current < widget.episodes.length - 1
                  ? () => move(1) : null,
                icon: const Icon(Icons.keyboard_arrow_down)),
            ]),
          )),
      ])),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'native_api.dart';

/// A single active native player that changes episode when swiping vertically.
class EpisodeReels extends StatefulWidget {
  const EpisodeReels({super.key, required this.api, required this.media,
    required this.episodes, required this.ar, this.initialIndex = 0,
    this.onProgress});
  final EgyApi api;
  final Media media;
  final List<Episode> episodes;
  final bool ar;
  final int initialIndex;
  final void Function(int, int)? onProgress;
  @override
  State<EpisodeReels> createState() => _ReelsState();
}

class _ReelsState extends State<EpisodeReels> with WidgetsBindingObserver {
  late final PageController pager;
  VideoPlayerController? player;
  Timer? ticker;
  int current = 0, generation = 0, server = 0;
  bool loading = true, stopped = false, muted = false, playing = false;
  String error = '';
  List<Map<String, dynamic>> sources = [];
  Map<String, dynamic> lease = {};

  @override
  void initState() {
    super.initState();
    current = widget.initialIndex.clamp(0, widget.episodes.length - 1);
    pager = PageController(initialPage: current);
    WidgetsBinding.instance.addObserver(this);
    _load(current);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  Future<void> _load(int index) async {
    final request = ++generation;
    ticker?.cancel();
    final old = player;
    player = null;
    await old?.dispose();
    if (!mounted || stopped || generation != request) return;
    setState(() {
      current = index; loading = true; playing = false; error = '';
      sources = []; lease = {}; server = 0;
    });
    try {
      final data = await widget.api.playerContext('episode', widget.episodes[index].id);
      if (!mounted || stopped || generation != request) return;
      sources = asList(data['sources']).map(asMap).where(
        (s) => numId(s['id']) > 0 && s['is_active'] != 0).toList();
      if (sources.isEmpty) throw const ApiException('لا يوجد سيرفر مشاهدة لهذه الحلقة');
      await _select(0, request);
    } catch (e) {
      if (mounted && generation == request) {
        setState(() { error = e.toString(); loading = false; });
      }
    }
  }

  Future<void> _select(int from, int request) async {
    if (!mounted || generation != request) return;
    String lastError = '';
    for (var i = from; i < sources.length; i++) {
      if (stopped || !mounted || generation != request) return;
      final old = player;
      player = null;
      await old?.dispose();
      setState(() { loading = true; server = i; error = ''; playing = false; });
      for (final relay in [false, true]) {
        VideoPlayerController? candidate;
        try {
          final data = await widget.api.lease(sources[i],
            forceRelay: relay, bypassCache: relay);
          if (!mounted || stopped || generation != request) return;
          final url = txt(data['playUrl']);
          final format = txt(data['type']).toLowerCase();
          if (!(url.startsWith('https://') || url.startsWith('http://'))) {
            throw const ApiException('رابط غير صالح');
          }
          if (['embed', 'iframe', 'youtube'].contains(format)) {
            throw const ApiException('السيرفر لا يقدم فيديو مباشر');
          }
          final headers = <String, String>{};
          for (final e in asMap(data['headers']).entries) {
            if (e.value is String) headers[e.key] = e.value as String;
          }
          candidate = VideoPlayerController.networkUrl(Uri.parse(url),
            httpHeaders: headers,
            formatHint: format.contains('hls') || url.contains('.m3u8')
              ? VideoFormat.hls : format.contains('dash') || url.contains('.mpd')
                ? VideoFormat.dash : null);
          await candidate.initialize().timeout(const Duration(seconds: 25));
          if (!mounted || stopped || generation != request) {
            await candidate.dispose();
            return;
          }
          player = candidate;
          lease = data;
          await candidate.setVolume(muted ? 0 : 1);
          await candidate.play();
          candidate.addListener(_listen);
          ticker?.cancel();
          ticker = Timer.periodic(const Duration(seconds: 20), (_) => _renew(request));
          setState(() { loading = false; playing = true; error = ''; });
          return;
        } catch (e) {
          lastError = e.toString();
          if (candidate != null && !identical(candidate, player)) {
            await candidate.dispose();
          }
        }
      }
    }
    if (mounted && generation == request) {
      setState(() {
        loading = false;
        error = 'تعذر تشغيل السيرفرات. قد يكون البث من المصدر متوقفًا. ' + lastError;
      });
    }
  }

  void _listen() {
    final p = player;
    if (p == null || !mounted) return;
    if (p.value.hasError && !loading) {
      setState(() { error = p.value.errorDescription ?? 'خطأ أثناء التشغيل'; });
    }
    final sec = p.value.position.inSeconds;
    if (sec > 0 && sec % 20 == 0) {
      widget.onProgress?.call(widget.episodes[current].id, sec);
    }
  }

  Future<void> _renew(int request) async {
    if (!mounted || stopped || generation != request || loading) return;
    final expiry = numId(lease['expiresAt']);
    if (expiry == 0) return;
    final ms = expiry > 1000000000000 ? expiry : expiry * 1000;
    if (ms - DateTime.now().millisecondsSinceEpoch > 45000) return;
    try {
      final leaseId = txt(lease['leaseId']);
      if (leaseId.isEmpty) return;
      final response = await widget.api.refreshLease(leaseId);
      if (!mounted || generation != request) return;
      if (txt(response['playUrl']) != txt(lease['playUrl'])) {
        final time = player?.value.position ?? Duration.zero;
        await _select(server, request);
        await player?.seekTo(time);
      } else {
        lease = response;
      }
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final p = player;
    if (p == null || !p.value.isInitialized) return;
    if (p.value.isPlaying) { await p.pause(); } else { await p.play(); }
    if (mounted) setState(() => playing = p.value.isPlaying);
  }

  void _servers() {
    if (sources.isEmpty) return;
    showModalBottomSheet<void>(context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(14),
            child: Text('اختيار السيرفر', style: TextStyle(fontSize: 18))),
          ...List.generate(sources.length, (i) => ListTile(
            title: Text(txt(sources[i]['server_name'])),
            leading: Icon(i == server ? Icons.play_circle : Icons.dns_outlined),
            onTap: () { Navigator.pop(ctx); _select(i, generation); },
          )),
        ])));
  }

  @override
  void dispose() {
    stopped = true;
    ++generation;
    ticker?.cancel();
    pager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    super.dispose();
  }

  String _clock(Duration d) => d.inMinutes.toString().padLeft(2, '0') +
      ':' + (d.inSeconds % 60).toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final p = player;
    final ready = p != null && p.value.isInitialized;
    final ep = widget.episodes[current];
    return Scaffold(backgroundColor: Colors.black,
      body: SafeArea(child: Stack(children: [
        PageView.builder(
          controller: pager,
          scrollDirection: Axis.vertical,
          itemCount: widget.episodes.length,
          onPageChanged: _load,
          itemBuilder: (ctx, index) {
            final item = widget.episodes[index];
            return Stack(fit: StackFit.expand, children: [
              if (index == current && ready)
                FittedBox(fit: BoxFit.cover,
                  child: SizedBox(
                    width: p.value.size.width, height: p.value.size.height,
                    child: VideoPlayer(p)))
              else Image.network(
                item.image.isNotEmpty ? item.image : widget.media.poster,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Colors.black)),
              const DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xB9000000), Colors.transparent, Color(0xD8000000)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter))),
              if (index == current) Positioned(left: 18, right: 70, bottom: 90,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.media.title(widget.ar), maxLines: 2,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(ep.title(widget.ar),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('الموسم ' + ep.season.toString() + ' • الحلقة ' + ep.number.toString()),
                  ])),
              if (index == current && ready) Positioned(
                left: 16, right: 16, bottom: 15,
                child: Column(children: [
                  VideoProgressIndicator(p, allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFFE50914),
                      backgroundColor: Colors.white24,
                      bufferedColor: Colors.white54)),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(_clock(p.value.position)),
                      Text(_clock(p.value.duration))]),
                ])),
            ]);
          },
        ),
        Positioned(top: 6, left: 5, right: 12, child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new)),
          Expanded(child: Text(widget.media.title(widget.ar),
            maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
          Text((current + 1).toString() + '/' + widget.episodes.length.toString()),
        ])),
        Positioned(right: 8, bottom: 130, child: Column(children: [
          IconButton.filledTonal(onPressed: _toggle,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow, size: 30)),
          IconButton.filledTonal(onPressed: _servers,
            icon: const Icon(Icons.dns_outlined)),
          IconButton.filledTonal(onPressed: () async {
            muted = !muted;
            await player?.setVolume(muted ? 0 : 1);
            if (mounted) setState(() {});
          }, icon: Icon(muted ? Icons.volume_off : Icons.volume_up)),
          const Icon(Icons.swap_vert, color: Colors.white70),
        ])),
        if (loading) const Center(child: CircularProgressIndicator(
          color: Color(0xFFE50914))),
        if (error.isNotEmpty && !loading)
          Center(child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xEE18181C),
              borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 35, color: Colors.orange),
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => _load(current),
                icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ]))),
      ])));
  }
}

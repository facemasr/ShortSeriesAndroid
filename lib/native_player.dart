import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'native_api.dart';

class NativePlayer extends StatefulWidget {
  const NativePlayer({super.key, required this.api, required this.type,
    required this.id, required this.title, this.resume = Duration.zero,
    this.onProgress});
  final EgyApi api;
  final String type;
  final int id;
  final String title;
  final Duration resume;
  final void Function(int seconds)? onProgress;
  @override
  State<NativePlayer> createState() => _NativePlayerState();
}

class _NativePlayerState extends State<NativePlayer> {
  VideoPlayerController? video;
  Map<String, dynamic> contextData = {};
  List<Map<String, dynamic>> sources = [];
  Map<String, dynamic> leaseData = {};
  Timer? refreshTimer;
  bool busy = true, paused = false, controls = true;
  String message = '', currentTitle = '';
  int active = -1;
  Duration lastStored = Duration.zero;
  bool disposed = false;
  bool recovering = false, currentRelay = false;
  int generation = 0;
  Duration? pendingSeek;
  double playbackSpeed = 1;

  @override
  void initState() {
    super.initState();
    currentTitle = widget.title;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final ctx = await widget.api.playerContext(widget.type, widget.id);
      if (!mounted) return;
      contextData = ctx;
      sources = asList(ctx['sources']).map(asMap)
          .where((s) => numId(s['id']) > 0 && s['is_active'] != 0).toList();
      final episode = asMap(ctx['episode']);
      if (episode.isNotEmpty) {
        currentTitle = txt(episode['title_ar']).isNotEmpty
            ? txt(episode['title_ar']) : widget.title;
      }
      if (sources.isEmpty) {
        setState(() { busy = false; message = 'لا توجد مصادر مشاهدة متاحة'; });
        return;
      }
      await _choose(0);
    } catch (e) {
      if (mounted) setState(() { busy = false; message = e.toString(); });
    }
  }

  // Try both direct and server-relayed transports before changing sources.
  // The Android decoder needs the headers returned with the lease, not just its URL.
  Future<void> _choose(int index, {bool retry = false, bool relayFirst = false}) async {
    if (index < 0 || index >= sources.length || disposed) return;
    final attempt = ++generation;
    refreshTimer?.cancel();
    if (mounted) setState(() {
      busy = true; message = ''; active = index;
    });
    final previous = video;
    video = null;
    await previous?.dispose();
    final source = sources[index];
    String lastFailure = '';
    final relayModes = relayFirst ? <bool>[true, false] : <bool>[false, true];
    for (final relay in relayModes) {
      VideoPlayerController? candidate;
      try {
        final result = await widget.api.lease(source,
          bypassCache: retry || relay, forceRelay: relay);
        if (disposed || !mounted || attempt != generation) return;
        final url = txt(result['playUrl']);
        final type = txt(result['type']).toLowerCase();
        if (!(url.startsWith('https://') || url.startsWith('http://'))) {
          throw const ApiException('رابط المشاهدة غير صالح');
        }
        if (type == 'embed' || type == 'iframe' || type == 'youtube') {
          throw const ApiException('هذا السيرفر يحتاج رابط فيديو مباشر');
        }
        final headers = <String, String>{};
        for (final entry in asMap(result['headers']).entries) {
          if (entry.value is String) headers[entry.key] = entry.value as String;
        }
        // Match the browser playback's first-party context for servers
        // which require a valid site referrer.
        headers.putIfAbsent('Referer', () => origin + '/');
        headers.putIfAbsent('User-Agent', () =>
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36');
        final low = url.toLowerCase();
        candidate = VideoPlayerController.networkUrl(
          Uri.parse(url), httpHeaders: headers,
          formatHint: type.contains('hls') || low.contains('.m3u8')
            ? VideoFormat.hls : type.contains('dash') || low.contains('.mpd')
              ? VideoFormat.dash : null,
        );
        await candidate.initialize().timeout(const Duration(seconds: 30));
        if (disposed || !mounted || attempt != generation) {
          await candidate.dispose();
          return;
        }
        video = candidate;
        leaseData = result;
        currentRelay = relay;
        candidate.addListener(_onVideo);
        await candidate.setLooping(false);
        await candidate.setPlaybackSpeed(playbackSpeed);
        final restore = pendingSeek ?? widget.resume;
        if (restore > Duration.zero &&
            (candidate.value.duration == Duration.zero ||
             restore < candidate.value.duration)) {
          await candidate.seekTo(restore);
        }
        pendingSeek = null;
        await candidate.play();
        refreshTimer?.cancel();
        refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _keepAlive());
        if (mounted) setState(() {
          busy = false; paused = false; message = '';
        });
        return;
      } catch (e) {
        lastFailure = e.toString();
        if (candidate != null && identical(candidate, video)) video = null;
        await candidate?.dispose();
        if (disposed || !mounted || attempt != generation) return;
      }
    }
    if (index + 1 < sources.length) {
      await _choose(index + 1, retry: true);
      return;
    }
    if (mounted) setState(() {
      busy = false;
      message = 'تعذر تشغيل جميع السيرفرات. راجع اتصال التطبيق أو مصدر الفيديو. ' + lastFailure;
    });
  }

  void _onVideo() {
    if (disposed || !mounted) return;
    final c = video;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.hasError && !busy) {
      if (recovering) return;
      recovering = true;
      pendingSeek = c.value.position;
      final failed = active;
      final next = !currentRelay ? failed : failed + 1;
      Future<void>(() async {
        try {
          if (next >= sources.length) {
            if (mounted) setState(() =>
              message = c.value.errorDescription ?? 'تعذر تشغيل الفيديو');
          } else {
            await _choose(next, retry: true, relayFirst: !currentRelay);
          }
        } finally {
          recovering = false;
        }
      });
      return;
    }
    if (c.value.position - lastStored > const Duration(seconds: 12)) {
      lastStored = c.value.position;
      widget.onProgress?.call(lastStored.inSeconds);
    }
    if (c.value.position >= c.value.duration &&
        c.value.duration > Duration.zero && widget.type == 'episode') {
      // Next episode is available using the button below, not by guessing URLs.
    }
  }

  Future<void> _keepAlive() async {
    if (disposed || busy || recovering || active < 0) return;
    final expiry = numId(leaseData['expiresAt']);
    if (expiry <= 0) return;
    final when = expiry > 1000000000000 ? expiry : expiry * 1000;
    if (when - DateTime.now().millisecondsSinceEpoch > 45000) return;
    final old = video;
    final position = old?.value.position ?? Duration.zero;
    final wasPlaying = old?.value.isPlaying ?? false;
    try {
      final id = txt(leaseData['leaseId']);
      final renewed = id.isNotEmpty
          ? await widget.api.refreshLease(id)
          : await widget.api.lease(sources[active],
              bypassCache: true, forceRelay: currentRelay);
      if (disposed || !mounted) return;
      final renewedUrl = txt(renewed['playUrl']);
      if (renewedUrl.isEmpty) return;
      if (renewedUrl == txt(leaseData['playUrl'])) {
        leaseData = renewed;
        return;
      }
      pendingSeek = position;
      await _choose(active, retry: true, relayFirst: currentRelay);
      if (!wasPlaying) await video?.pause();
    } catch (_) {
      // A user can select another source when the lease expires.
    }
  }

  Future<void> _toggle() async {
    final c = video;
    if (c == null) return;
    c.value.isPlaying ? await c.pause() : await c.play();
    if (mounted) setState(() => paused = !c.value.isPlaying);
  }

  Future<void> _seek(int delta) async {
    final c = video;
    if (c == null || !c.value.isInitialized) return;
    final next = c.value.position + Duration(seconds: delta);
    await c.seekTo(next < Duration.zero ? Duration.zero :
        next > c.value.duration ? c.value.duration : next);
    if (mounted) setState(() {});
  }

  String _time(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? d.inHours.toString() + ':' + m + ':' + s : m + ':' + s;
  }

  Future<void> _nextEpisode() async {
    final id = numId(asMap(contextData['navigation'])['nextEpisodeId']);
    if (id <= 0) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) =>
        NativePlayer(api: widget.api, type: 'episode', id: id, title: widget.title)));
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    refreshTimer?.cancel();
    widget.onProgress?.call(video?.value.position.inSeconds ?? 0);
    video?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = video;
    final ready = c != null && c.value.isInitialized;
    final next = numId(asMap(this.contextData['navigation'])['nextEpisodeId']);
    return Scaffold(
      appBar: AppBar(title: Text(currentTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      backgroundColor: Colors.black,
      body: SafeArea(child: Column(children: [
        Center(child: AspectRatio(aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            if (ready) VideoPlayer(c),
            if (busy) const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
            if (ready && controls && !busy) Center(child: Row(
              mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: () => _seek(-10),
                    icon: const Icon(Icons.replay_10, size: 35), color: Colors.white),
                const SizedBox(width: 25),
                IconButton(onPressed: _toggle,
                    icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                        size: 54), color: Colors.white),
                const SizedBox(width: 25),
                IconButton(onPressed: () => _seek(10),
                    icon: const Icon(Icons.forward_10, size: 35), color: Colors.white),
              ])),
            if (ready) Positioned.fill(child: Align(alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => setState(() => controls = !controls),
                icon: Icon(controls ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.white70),
              ))),
            if (ready && controls) Positioned(left: 8, right: 8, bottom: 0,
              child: VideoProgressIndicator(c, allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFFE50914), bufferedColor: Colors.white38,
                    backgroundColor: Colors.white10))),
          ]))),
        if (ready) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Text(_time(c.value.position) + ' / ' + _time(c.value.duration),
                style: const TextStyle(fontSize: 12)),
            const Spacer(),
            PopupMenuButton<double>(tooltip: 'Speed',
              initialValue: playbackSpeed,
              onSelected: (v) async {
                playbackSpeed = v;
                await c.setPlaybackSpeed(v);
                if (mounted) setState(() {});
              },
              itemBuilder: (ctx) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                  .map((v) => PopupMenuItem(value: v, child: Text(v.toString() + 'x')))
                  .toList(),
              child: Text(playbackSpeed.toString() + 'x')),
          ])),
        if (message.isNotEmpty) Padding(padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.orange),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: sources.isEmpty ? _initialize :
                  () => _choose(0, retry: true),
                  icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ])),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(children: [
            const Icon(Icons.dns_outlined, color: Colors.white60),
            const SizedBox(width: 8),
            const Expanded(child: Text('سيرفرات المشاهدة', style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.bold))),
            if (next > 0)
              TextButton.icon(onPressed: _nextEpisode,
                icon: const Icon(Icons.skip_next), label: const Text('الحلقة التالية')),
          ])),
        Expanded(child: ListView.builder(
          itemCount: sources.length,
          itemBuilder: (ctx, i) {
            final s = sources[i];
            return ListTile(
              selected: i == active,
              selectedColor: const Color(0xFFE50914),
              leading: Icon(i == active ? Icons.play_circle_filled : Icons.smart_display_outlined),
              title: Text(txt(s['server_name']).isNotEmpty
                  ? txt(s['server_name']) : 'Server ' + (i + 1).toString()),
              subtitle: Text(i == active ? 'السيرفر الحالي' : 'اضغط للتشغيل'),
              onTap: () => _choose(i, retry: true),
            );
          },
        )),
      ])),
    );
  }
}

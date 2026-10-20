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

  Future<void> _choose(int index, {bool retry = false}) async {
    if (index < 0 || index >= sources.length || disposed) return;
    if (mounted) setState(() { busy = true; message = ''; active = index; });
    final previous = video;
    video = null;
    await previous?.dispose();
    try {
      final result = await widget.api.lease(sources[index], bypassCache: retry);
      if (disposed || !mounted) return;
      final url = txt(result['playUrl']);
      final type = txt(result['type']).toLowerCase();
      if (!url.startsWith('https://') && !url.startsWith('http://')) {
        throw const ApiException('رابط المشاهدة غير صالح');
      }
      if (type == 'embed' || type == 'iframe' || type == 'youtube') {
        throw const ApiException('هذا السيرفر يحتاج مصدر فيديو مباشر لتشغيله داخل التطبيق');
      }
      final candidate = VideoPlayerController.networkUrl(
        Uri.parse(url),
        formatHint: type.contains('hls') || url.contains('.m3u8')
            ? VideoFormat.hls : type.contains('dash') || url.contains('.mpd')
                ? VideoFormat.dash : VideoFormat.other,
      );
      video = candidate;
      await candidate.initialize().timeout(const Duration(seconds: 28));
      if (disposed || !mounted) { await candidate.dispose(); return; }
      leaseData = result;
      candidate.addListener(_onVideo);
      await candidate.setLooping(false);
      await candidate.setPlaybackSpeed(playbackSpeed);
      if (widget.resume > Duration.zero && widget.resume < candidate.value.duration) {
        await candidate.seekTo(widget.resume);
      }
      await candidate.play();
      refreshTimer?.cancel();
      refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _keepAlive());
      setState(() { busy = false; paused = false; message = ''; });
    } catch (e) {
      if (disposed || !mounted) return;
      if (index + 1 < sources.length) {
        await _choose(index + 1, retry: true);
      } else {
        setState(() { busy = false; message = 'تعذر تشغيل المصادر المتاحة. ' + e.toString(); });
      }
    }
  }

  void _onVideo() {
    if (disposed || !mounted) return;
    final c = video;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.hasError && !busy) {
      setState(() { message = txt(c.value.errorDescription); });
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
    if (disposed || busy) return;
    final expires = leaseData['expiresAt'];
    if (expires == null) return;
    final expiry = numId(expires);
    if (expiry == 0) return;
    final expiryMs = expiry > 1000000000000 ? expiry : expiry * 1000;
    final remaining = expiryMs - DateTime.now().millisecondsSinceEpoch;
    if (remaining > 45000) return;
    final old = video;
    final position = old?.value.position ?? Duration.zero;
    final playing = old?.value.isPlaying ?? false;
    try {
      final id = txt(leaseData['leaseId']);
      final fresh = id.isNotEmpty
          ? await widget.api.refreshLease(id)
          : await widget.api.lease(sources[active], bypassCache: true);
      if (disposed || !mounted) return;
      final url = txt(fresh['playUrl']);
      if (url.isEmpty) return;
      final type = txt(fresh['type']);
      final next = VideoPlayerController.networkUrl(Uri.parse(url),
        formatHint: type == 'hls' ? VideoFormat.hls : VideoFormat.other);
      await next.initialize();
      await next.seekTo(position);
      if (playing) await next.play();
      next.addListener(_onVideo);
      video = next;
      leaseData = fresh;
      await old?.dispose();
      if (mounted) setState(() {});
    } catch (_) {
      // The next explicit server selection will request a fresh lease.
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

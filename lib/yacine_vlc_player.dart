import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;

import 'native_api.dart';
import 'native_banner_ads.dart';
import 'yacine_channel_resolver.dart';
import 'yacine_direct_player.dart';
import 'yacine_stream_renewal.dart';
import 'yacine_vlc_m3u.dart';
import 'yacine_vlc_options.dart';

/// Device-local VLC player for the same per-channel API and original HTTP
/// media headers used by EGY TV Sport on Windows. No VPS proxy, DRM bypass,
/// invented Referer, permanent signed link or server-side channel fanout.
class YacineVlcChannelPlayer extends StatefulWidget {
  const YacineVlcChannelPlayer({
    super.key, required this.channel, required this.api, required this.ar,
  });
  final LiveChannel channel;
  final EgyApi api;
  final bool ar;

  @override
  State<YacineVlcChannelPlayer> createState() => _YacineVlcChannelPlayerState();
}

class _YacineVlcChannelPlayerState extends State<YacineVlcChannelPlayer>
    with WidgetsBindingObserver {
  static const _teal = Color(0xFF21D9C6);
  final http.Client _http = http.Client();

  VlcPlayerController? _controller;
  List<YacinePlaybackSource> _sources = const [];
  Uri? _activeUri;
  Map<String, String>? _activeHeaders;
  DateTime? _activeSince;
  DateTime _lastSwitch = DateTime.now();
  DateTime _lastFrame = DateTime.now();
  DateTime? _lastApiFetch;
  Timer? _poll;
  Timer? _watchdog;
  Timer? _retry;
  Timer? _controlsTimer;
  int _server = 0;
  int _failures = 0;
  bool _loading = true;
  bool _fetching = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _userPaused = false;
  bool _fullscreen = false;
  bool _showControls = true;
  bool _hadPlayback = false;
  double _volume = 1.0;
  BoxFit _fit = BoxFit.cover;
  String? _notice;
  String? _lastError;

  String t(String a, String b) => widget.ar ? a : b;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 20),
        (_) => unawaited(_refreshActiveChannel()));
    _watchdog = Timer.periodic(const Duration(seconds: 7),
        (_) => _checkPlayback());
    unawaited(_resolveAndPlay(force: true));
  }

  int? _expiry(Uri? uri) {
    if (uri == null) return null;
    final value = uri.queryParameters['e'] ??
        uri.queryParameters['expires'] ?? uri.queryParameters['exp'];
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < 1700000000) return null;
    return parsed > 9999999999 ? parsed ~/ 1000 : parsed;
  }

  Future<void> _resolveAndPlay({
    bool force = false,
    int? preferred,
    List<YacinePlaybackSource>? readySources,
  }) async {
    if (_disposed || _fetching) return;
    _fetching = true;
    _retry?.cancel();
    _retry = null;
    if (mounted) setState(() {
      if (_controller == null) _loading = true;
      _notice = t('جارٍ طلب رابط القناة...', 'Resolving channel stream...');
    });
    try {
      final sources = readySources ??
          await YacineChannelResolver(_http).resolve(widget.channel.providerId);
      if (_disposed || !mounted || sources.isEmpty) return;
      _sources = sources;
      _lastApiFetch = DateTime.now();
      final choice = preferred ?? _server;
      final index = choice >= 0 && choice < sources.length ? choice : 0;
      _startMedia(sources[index], index, force: force);
    } catch (_) {
      if (mounted && !_disposed) {
        setState(() {
          _loading = false;
          _notice = t(
            'تعذر جلب رابط قابل للتشغيل من API للقناة المحددة.',
            'No playable provider URL was returned for this channel.',
          );
        });
        _scheduleRetry();
      }
    } finally {
      _fetching = false;
    }
  }

  void _startMedia(YacinePlaybackSource source, int index,
      {bool force = false}) {
    if (_disposed || !mounted) return;
    if (!force && source.uri == _activeUri && _controller != null) return;
    final fresh = VlcPlayerController.network(
      source.uri.toString(),
      hwAcc: HwAcc.auto,
      autoPlay: true,
      options: yacineVlcOptions(source.headers),
    );
    final previous = _controller;
    previous?.removeListener(_onPlayerChanged);
    fresh.addListener(_onPlayerChanged);
    setState(() {
      _controller = fresh;
      _activeUri = source.uri;
      _activeHeaders = source.headers;
      _activeSince = DateTime.now();
      _server = index;
      _lastSwitch = DateTime.now();
      _lastFrame = DateTime.now();
      _loading = true;
      _hadPlayback = false;
      _lastError = null;
      _notice = t('جاري بدء البث داخل VLC...', 'Opening stream in VLC...');
    });
    if (previous != null && !identical(previous, fresh)) {
      unawaited(previous.dispose());
    }
    _revealControls();
  }

  /// Update only the currently viewed channel. A new API token is cached in
  /// memory but not forced into a player that is still streaming well.
  Future<void> _refreshActiveChannel() async {
    if (_disposed || !_foreground || _fetching || _userPaused) return;
    if (_controller == null) return;
    _fetching = true;
    try {
      final sources = await YacineChannelResolver(_http)
          .resolve(widget.channel.providerId);
      if (_disposed || !mounted || !_foreground || sources.isEmpty) return;
      _lastApiFetch = DateTime.now();
      final label = _server >= 0 && _server < _sources.length
          ? _sources[_server].label : null;
      final match = label == null
          ? -1 : sources.indexWhere((s) => s.label == label);
      final index = match >= 0 ? match
          : _server < sources.length ? _server : 0;
      final updated = sources[index];
      _sources = sources;
      final value = _controller?.value;
      final healthy = value != null && value.isPlaying &&
          !value.hasError && !value.isBuffering;
      if (yacineHotSwapNeeded(
        activeUri: _activeUri, activeHeaders: _activeHeaders,
        updatedUri: updated.uri, updatedHeaders: updated.headers,
        activeSince: _activeSince,
        now: DateTime.now(), healthy: healthy,
      ) && updated.uri != _activeUri) {
        _startMedia(updated, index, force: true);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // A temporary API outage never interrupts a video that's playing.
    } finally {
      _fetching = false;
    }
  }

  void _onPlayerChanged() {
    if (_disposed || !mounted) return;
    final value = _controller?.value;
    if (value == null) return;
    if (value.isPlaying) {
      _lastFrame = DateTime.now();
      _failures = 0;
      if (!_hadPlayback || _loading || _notice != null) {
        setState(() {
          _hadPlayback = true;
          _loading = false;
          _notice = null;
          _lastError = null;
        });
      }
      return;
    }
    if (value.hasError || value.isEnded) {
      if (_lastError == null) {
        setState(() {
          _loading = false;
          _lastError = t(
            'تعذر بدء البث أو انقطع المصدر. جاري محاولة رابط جديد...',
            'Stream failed. Requesting a fresh source...',
          );
        });
      }
      _scheduleRetry();
    }
  }

  void _checkPlayback() {
    if (_disposed || !_foreground || _userPaused || _fetching) return;
    final value = _controller?.value;
    if (value == null) {
      if (_retry == null) _scheduleRetry();
      return;
    }
    if (value.hasError || value.isEnded) {
      _scheduleRetry();
      return;
    }
    final elapsed = DateTime.now().difference(_lastSwitch);
    // Only treat sustained inactivity as failure. No restart on API polling.
    if (!value.isPlaying && elapsed.inSeconds > 23 && _retry == null) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retry != null || _fetching || _userPaused) return;
    _failures++;
    final delays = <int>[3, 6, 12, 20, 30, 60];
    final seconds = delays[_failures > delays.length
        ? delays.length - 1 : _failures - 1];
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      if (_disposed || !mounted || !_foreground) return;
      final next = _sources.length > 1
          ? (_server + 1) % _sources.length : _server;
      unawaited(_resolveAndPlay(force: true, preferred: next));
    });
  }

  Future<void> _restartCurrent() async {
    _failures = 0;
    await _resolveAndPlay(force: true, preferred: _server);
  }

  void _revealControls() {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _showControls = true);
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_disposed && _controller?.value.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePause() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      _userPaused = true;
      unawaited(c.pause());
    } else {
      _userPaused = false;
      final expires = _expiry(_activeUri);
      if (expires != null &&
          expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120) {
        unawaited(_restartCurrent());
      } else {
        unawaited(c.play());
      }
    }
    _revealControls();
  }

  void _changeVolume(double value) {
    _volume = value;
    unawaited(_controller?.setVolume((value * 100).round()) ??
        Future<void>.value());
    _revealControls();
    if (mounted) setState(() {});
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (_disposed || !mounted || _fullscreen == enabled) return;
    setState(() => _fullscreen = enabled);
    if (enabled) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Widget _serversMenu() => PopupMenuButton<int>(
    tooltip: t('السيرفر والجودة', 'Server / quality'),
    enabled: !_fetching && _sources.isNotEmpty,
    icon: const Icon(Icons.tune_rounded, color: Colors.white),
    initialValue: _server,
    onSelected: (index) {
      _revealControls();
      unawaited(_resolveAndPlay(force: true, preferred: index));
    },
    itemBuilder: (_) => [
      for (var i = 0; i < _sources.length; i++)
        PopupMenuItem<int>(
          value: i,
          child: Text(_sources[i].label +
              (i == _server ? '  ✓' : '')),
        ),
    ],
  );

  Widget _ratioMenu() => PopupMenuButton<BoxFit>(
    tooltip: t('نسبة العرض', 'Video scaling'),
    icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
    initialValue: _fit,
    onSelected: (mode) {
      setState(() => _fit = mode);
      _revealControls();
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: BoxFit.cover,
        child: Text(t('ملء الشاشة — قص الحواف', 'Fill and crop')),
      ),
      PopupMenuItem(
        value: BoxFit.contain,
        child: Text(t('الصورة كاملة — دون قص', 'Original aspect')),
      ),
      PopupMenuItem(
        value: BoxFit.fill,
        child: Text(t('تمديد الصورة', 'Stretch image')),
      ),
    ],
  );

  Future<void> _copyM3u() async {
    try {
      final sources = await YacineChannelResolver(_http)
          .resolve(widget.channel.providerId);
      if (!mounted || _disposed || sources.isEmpty) return;
      final source = sources[_server < sources.length ? _server : 0];
      final text = yacineVlcM3u(
        stream: source.uri,
        channelName: widget.channel.title(widget.ar),
        tvgId: widget.channel.providerId,
        groupTitle: widget.channel.group,
        headers: source.headers,
      );
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تم نسخ M3U الحالي — الرابط مؤقت.',
            'Current M3U copied. The URL expires.'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تعذر جلب رابط جديد.', 'Fresh link unavailable.'))));
    }
  }

  Widget _videoSurface() {
    final c = _controller;
    if (c == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: _teal),
        const SizedBox(height: 15),
        Text(_notice ?? t('جاري جلب رابط البث...', 'Fetching stream URL...')),
      ]));
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _revealControls,
      onDoubleTap: () => unawaited(_setFullscreen(!_fullscreen)),
      child: Stack(fit: StackFit.expand, children: [
        ClipRect(child: FittedBox(
          fit: _fit, alignment: Alignment.center,
          child: SizedBox(
            width: 1280, height: 720,
            child: VlcPlayer(
              key: ValueKey<VlcPlayerController>(c),
              controller: c,
              aspectRatio: 16 / 9,
              placeholder: const Center(
                child: CircularProgressIndicator(color: _teal)),
            ),
          ),
        )),
        PositionedDirectional(
          top: 12, start: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xD9111B2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _teal.withValues(alpha: .5)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: _teal, size: 8),
                SizedBox(width: 8),
                Text('LIVE · VLC',
                    style: TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ),
        if (_loading || c.value.isBuffering)
          const Center(child: CircularProgressIndicator(color: _teal)),
        if (_lastError != null)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_lastError!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _fetching ? null : () => unawaited(_restartCurrent()),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t('إعادة الاتصال', 'Reconnect')),
              ),
            ]),
          )),
        IgnorePointer(
          ignoring: !_showControls,
          child: AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Column(children: [
              if (_fullscreen)
                Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: IconButton.filledTonal(
                    onPressed: () => unawaited(_setFullscreen(false)),
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xF408101D)],
                  ),
                ),
                child: Row(children: [
                  IconButton.filledTonal(
                    tooltip: t('تشغيل/إيقاف', 'Play/Pause'),
                    icon: Icon(c.value.isPlaying
                        ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: _togglePause,
                  ),
                  IconButton(
                    tooltip: t('تحديث القناة', 'Refresh channel'),
                    onPressed: _fetching ? null
                        : () => unawaited(_restartCurrent()),
                    icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white),
                  ),
                  IconButton(
                    tooltip: t('الصوت', 'Mute'),
                    onPressed: () => _changeVolume(_volume == 0 ? 1 : 0),
                    icon: Icon(_volume == 0
                      ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white),
                  ),
                  Expanded(child: Slider(
                    value: _volume, min: 0, max: 1,
                    activeColor: _teal,
                    onChanged: _changeVolume,
                  )),
                  _serversMenu(),
                  _ratioMenu(),
                  IconButton(
                    tooltip: t('ملء الشاشة', 'Fullscreen'),
                    icon: Icon(_fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                      color: Colors.white),
                    onPressed: () => unawaited(_setFullscreen(!_fullscreen)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      if (!_userPaused) unawaited(_controller?.pause() ?? Future<void>.value());
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (!_userPaused) {
        final expiry = _expiry(_activeUri);
        if (expiry != null &&
            expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120) {
          unawaited(_restartCurrent());
        } else {
          unawaited(_controller?.play() ?? Future<void>.value());
          unawaited(_refreshActiveChannel());
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _watchdog?.cancel();
    _retry?.cancel();
    _controlsTimer?.cancel();
    final c = _controller;
    c?.removeListener(_onPlayerChanged);
    if (c != null) unawaited(c.dispose());
    _http.close();
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _fullscreen) {
          unawaited(_setFullscreen(false));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF060A12),
        appBar: _fullscreen ? null : AppBar(
          backgroundColor: const Color(0xFF101826),
          title: Text(widget.channel.title(widget.ar),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: t('نسخ ملف M3U', 'Copy M3U'),
              onPressed: _copyM3u,
              icon: const Icon(Icons.playlist_add_check_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: t('المشغل', 'Player engine'),
              onSelected: (mode) {
                if (mode != 'exo') return;
                Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                  builder: (_) => DirectYacineChannelPlayer(
                    channel: widget.channel, api: widget.api, ar: widget.ar,
                  ),
                ));
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'exo',
                  child: Text(t('جرّب المشغل البديل ExoPlayer',
                      'Try ExoPlayer alternative')),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: !_fullscreen, bottom: !_fullscreen,
          child: Column(children: [
            Expanded(child: _videoSurface()),
            if (!_fullscreen) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 9, 16, 6),
                child: Row(children: [
                  const Icon(Icons.circle, color: _teal, size: 8),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    t('EGY TV SPORT · رابط مباشر من API للقناة الحالية · VLC',
                      'EGY TV SPORT · Current-channel direct API stream · VLC'),
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 12,
                    ),
                  )),
                ]),
              ),
              EgyshowBannerAd(
                api: widget.api, placement: 'player_bottom', height: 84,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

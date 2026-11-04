import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'native_api.dart';
import 'native_banner_ads.dart';

/// Direct, device-side playback for provider-authorized HLS channels.
/// No EGYSHOW VPS media relay, DRM circumvention, stored signed URLs or
/// changes to the existing movie/series WebView player.
class DirectYacineChannelPlayer extends StatefulWidget {
  const DirectYacineChannelPlayer({
    super.key, required this.channel, required this.api, required this.ar,
  });

  final LiveChannel channel;
  final EgyApi api;
  final bool ar;

  @override
  State<DirectYacineChannelPlayer> createState() =>
      _DirectYacineChannelPlayerState();
}

class _YacineMediaSource {
  const _YacineMediaSource(this.uri, this.headers, this.label);
  final Uri uri;
  final Map<String, String> headers;
  final String label;
}

class _ProviderMediaResolver {
  const _ProviderMediaResolver(this.client);
  final http.Client client;

  static const String _apiUrl = 'https://def001.ycnapi.com/api/channel/';
  static const String _apiAgent = 'okhttp/4.12.0';
  static const String _keyPrefix = 'c!xZj+N9&G@Ev@vw';

  static Map<String, dynamic> _decode(Uint8List bytes, String? stamp) {
    final input = utf8.decode(bytes).trim();
    if (input.startsWith('{')) return asMap(jsonDecode(input));
    if (stamp == null || !RegExp(r'^[0-9]{1,16}$').hasMatch(stamp)) {
      throw const ApiException('provider_data_invalid');
    }
    final encrypted = base64Decode(input);
    if (encrypted.length > 4000000) {
      throw const ApiException('provider_data_too_large');
    }
    final key = utf8.encode(_keyPrefix + stamp);
    final decoded = Uint8List(encrypted.length);
    for (var i = 0; i < encrypted.length; i++) {
      decoded[i] = encrypted[i] ^ key[i % key.length];
    }
    return asMap(jsonDecode(utf8.decode(decoded)));
  }

  static String? _safeHeader(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString();
    if (value.isEmpty || value.length > 700 ||
        RegExp(r'[\r\n\x00-\x1f\x7f]').hasMatch(value)) return null;
    return value;
  }

  static String? _header(Map<String, dynamic> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) {
        return _safeHeader(entry.value);
      }
    }
    return null;
  }

  Future<List<_YacineMediaSource>> resolve(String providerId) async {
    if (!RegExp(r'^\d{1,24}$').hasMatch(providerId)) {
      throw const ApiException('provider_channel_invalid');
    }
    final response = await client.get(
      Uri.parse(_apiUrl + providerId),
      headers: const {
        'User-Agent': _apiAgent,
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    ).timeout(const Duration(seconds: 14));

    if (response.statusCode != 200) {
      throw const ApiException('provider_api_unavailable');
    }
    final raw = _decode(response.bodyBytes, response.headers['t']);
    final rows = asList(raw['data']);
    final found = <_YacineMediaSource>[];
    for (final item in rows.take(15)) {
      final source = asMap(item);
      if (source.isEmpty) continue;
      if (!['1', '3'].contains(txt(source['url_type']).isEmpty
          ? '1' : txt(source['url_type']))) continue;
      final drm = source['drm'];
      if (drm != null && drm != false && drm.toString() != '' &&
          drm.toString().toLowerCase() != 'null') continue;

      final url = Uri.tryParse(txt(source['url']));
      if (url == null || !url.hasAuthority ||
          url.userInfo.isNotEmpty ||
          (url.scheme != 'https' && url.scheme != 'http')) continue;
      if (url.path.toLowerCase().endsWith('.mpd')) continue; // No DRM/DASH fallback.
      if (!url.path.toLowerCase().endsWith('.m3u8')) continue;
      final expires = int.tryParse(url.queryParameters['e'] ??
          url.queryParameters['expires'] ?? '');
      if (expires != null &&
          expires > 1700000000 &&
          expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 20) {
        continue;
      }

      final supplied = asMap(source['headers']);
      final agent = _safeHeader(source['user_agent']) ??
          _header(supplied, 'User-Agent');
      final referer = _safeHeader(source['referer']) ??
          _header(supplied, 'Referer');
      final origin = _header(supplied, 'Origin');
      final accept = _header(supplied, 'Accept');
      final headers = <String, String>{
        if (agent != null) 'User-Agent': agent,
        if (referer != null) 'Referer': referer,
        if (origin != null) 'Origin': origin,
        if (accept != null) 'Accept': accept,
      };
      final quality = txt(source['name']).isNotEmpty ? txt(source['name'])
          : txt(source['quality']).isNotEmpty ? txt(source['quality'])
          : 'Server ' + (found.length + 1).toString();
      found.add(_YacineMediaSource(url, headers, quality));
    }
    if (found.isEmpty) throw const ApiException('provider_stream_unavailable');
    return found;
  }
}

class _DirectYacineChannelPlayerState
    extends State<DirectYacineChannelPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  Timer? _renewal;
  Timer? _retry;
  Timer? _watchdog;
  Timer? _sourceRefresh;
  Timer? _controlsTimer;
  bool _showControls = true;
  double _volume = 1.0;
  bool _refreshingSources = false;
  bool _foreground = true;
  Uri? _activeUri;
  String? _activeLabel;
  DateTime? _lastSourceCheck;
  bool _lastBuffering = false;
  bool _lastPlaying = false;
  List<_YacineMediaSource> _sources = const [];
  int _selectedSource = 0;
  bool _busy = true;
  bool _connecting = false;
  bool _fullScreen = false;
  bool _userPaused = false;
  String? _failure;
  int _failures = 0;
  bool _disposed = false;
  Duration? _lastPosition;
  DateTime _lastAdvance = DateTime.now();

  String label(String ar, String en) => widget.ar ? ar : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchdog = Timer.periodic(const Duration(seconds: 6), (_) => _checkPlayback());
    // Refresh only the actively viewed channel; polling 675 channels would
    // overload the provider and invalidate good streams unnecessarily.
    _sourceRefresh = Timer.periodic(const Duration(seconds: 60),
        (_) => unawaited(_refreshSources()));
    unawaited(_connect());
  }

  /// Resolve updated server metadata without interrupting a healthy stream.
  /// Only switch players when an expiring token has an actual replacement.
  Future<void> _refreshSources() async {
    if (_refreshingSources || _connecting || _disposed || !_foreground ||
        _userPaused) return;
    final playing = _video;
    if (playing == null || !playing.value.isInitialized) return;
    _refreshingSources = true;
    try {
      final fresh = await _ProviderMediaResolver(widget.api.client)
          .resolve(widget.channel.providerId);
      if (!mounted || _disposed || !_foreground || _userPaused) return;
      _lastSourceCheck = DateTime.now();
      final sameLabel = fresh.indexWhere((s) => s.label == _activeLabel);
      final preferred = sameLabel >= 0 ? sameLabel
          : _selectedSource < fresh.length ? _selectedSource : 0;
      final replacement = fresh[preferred];
      _sources = fresh;
      // Metadata can change without a player restart. In particular, short
      // lived signed HLS URLs must not be kept as the permanent source.
      final activeExpiry = _expirySeconds(_activeUri);
      final secondsLeft = activeExpiry == null ? null
          : activeExpiry - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (secondsLeft != null && secondsLeft <= 90) {
        if (replacement.uri != _activeUri) {
          // Start the new player first; retain the current visible video until
          // initialization succeeds (seamless renewal when the provider allows).
          await _connect(preferredSource: preferred, preloadedSources: fresh);
        } else {
          // Provider returned the same short-lived token; do not break a
          // healthy video just to try it again. Ask for a fresh one soon.
          _renewal?.cancel();
          _renewal = Timer(const Duration(seconds: 15),
              () => unawaited(_refreshSources()));
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // A transient provider API error must not stop a playable channel.
      if (_expirySeconds(_activeUri) != null) {
        _renewal?.cancel();
        _renewal = Timer(const Duration(seconds: 15),
            () => unawaited(_refreshSources()));
      }
    } finally {
      _refreshingSources = false;
    }
  }

  int? _expirySeconds(Uri? uri) {
    if (uri == null) return null;
    final raw = uri.queryParameters['e'] ??
        uri.queryParameters['expires'] ?? uri.queryParameters['exp'];
    final n = int.tryParse(raw ?? '');
    if (n == null || n < 1700000000) return null;
    // Some providers use milliseconds rather than seconds.
    return n > 9999999999 ? n ~/ 1000 : n;
  }

  /// Open and retry paths always re-resolve the provider channel endpoint.
  /// Only a just-fetched in-memory response may be passed during a renewal.
  /// Signed playback URLs must never be persisted with the channel catalog.
  Future<void> _connect({bool userRetry = false, int preferredSource = 0,
      List<_YacineMediaSource>? preloadedSources}) async {
    if (_connecting || _disposed) return;
    _connecting = true;
    _retry?.cancel();
    _retry = null;
    _renewal?.cancel();
    if (userRetry) _failures = 0;
    // Keep a healthy stream visible while a renewed source initializes.
    // Avoid a black screen at every signed-URL refresh.
    final previous = _video;
    final retainCurrent = previous != null &&
        previous.value.isInitialized && previous.value.isPlaying &&
        !previous.value.hasError;
    if (!retainCurrent) {
      _video = null;
      if (previous != null) {
        previous.removeListener(_onMediaChanged);
        await previous.dispose();
      }
    }
    if (mounted) setState(() { _busy = !retainCurrent; _failure = null; });
    var connected = false;
    try {
      final sources = preloadedSources ??
          await _ProviderMediaResolver(widget.api.client)
              .resolve(widget.channel.providerId);
      if (_disposed || !mounted) return;
      _lastSourceCheck = DateTime.now();
      _sources = sources;
      final indices = [
        if (preferredSource >= 0 && preferredSource < sources.length) preferredSource,
        for (var i = 0; i < sources.length; i++)
          if (i != preferredSource) i,
      ];
      for (final index in indices) {
        final source = sources[index];
        // Even a freshly fetched signed URL may expire while another server
        // is being initialized: skip it rather than opening a stale token.
        final expiry = _expirySeconds(source.uri);
        if (expiry != null &&
            expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 15) {
          continue;
        }
        VideoPlayerController? candidate;
        try {
          candidate = VideoPlayerController.networkUrl(
            source.uri,
            httpHeaders: source.headers,
            formatHint: VideoFormat.hls,
          );
          await candidate.initialize().timeout(const Duration(seconds: 16));
          if (_disposed || !mounted) {
            await candidate.dispose();
            return;
          }
          await candidate.play();
          if (_disposed || !mounted) {
            await candidate.dispose();
            return;
          }
          final oldActive = _video;
          _video = candidate;
          _selectedSource = index;
          _activeUri = source.uri;
          _activeLabel = source.label;
          _lastBuffering = candidate.value.isBuffering;
          _lastPlaying = candidate.value.isPlaying;
          candidate.addListener(_onMediaChanged);
          await candidate.setVolume(_volume);
          _revealControls();
          if (oldActive != null && !identical(oldActive, candidate)) {
            oldActive.removeListener(_onMediaChanged);
            unawaited(oldActive.dispose());
          }
          _lastPosition = null;
          _lastAdvance = DateTime.now();
          _userPaused = false;
          _scheduleRenewal(source.uri);
          connected = true;
          if (mounted) setState(() { _busy = false; _failure = null; });
          return;
        } catch (_) {
          candidate?.removeListener(_onMediaChanged);
          if (identical(_video, candidate)) _video = null;
          await candidate?.dispose();
        }
      }
      throw const ApiException('all_sources_unavailable');
    } catch (_) {
      if (mounted && !_disposed) {
        setState(() {
          _busy = false;
          _failure = retainCurrent ? null : label(
            'هذه القناة لا توفر حاليًا بثًا مباشرًا متوافقًا. ستتم إعادة المحاولة.',
            'No compatible live stream is currently available. Retrying.',
          );
        });
      }
    } finally {
      _connecting = false;
      if (!connected && mounted && !_disposed) _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retry != null || _connecting) return;
    _failures++;
    final seconds = [3, 6, 12, 20, 30, 60][_failures > 6 ? 5 : _failures - 1];
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      if (mounted && !_disposed) unawaited(_connect());
    });
  }

  void _onMediaChanged() {
    final video = _video;
    if (video == null || _connecting || _disposed) return;
    if (video.value.hasError) {
      if (_retry == null && mounted) {
        setState(() => _failure = label(
          'حدث انقطاع في البث؛ جاري تحديث الرابط...',
          'Stream interrupted; refreshing the channel...'));
        _scheduleRetry();
      }
    } else if (mounted &&
        (video.value.isBuffering != _lastBuffering ||
         video.value.isPlaying != _lastPlaying)) {
      // VideoPlayer emits frequent position notifications; avoid rebuilding
      // the screen for every video frame.
      _lastBuffering = video.value.isBuffering;
      _lastPlaying = video.value.isPlaying;
      setState(() {});
    }
  }

  void _checkPlayback() {
    final player = _video;
    if (_disposed || _connecting || player == null ||
        !player.value.isInitialized || !player.value.isPlaying || _userPaused) return;
    final position = player.value.position;
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastAdvance = DateTime.now();
      if (_failures > 0) _failures = 0;
    } else if (DateTime.now().difference(_lastAdvance).inSeconds > 23) {
      _lastAdvance = DateTime.now();
      _scheduleRetry();
    }
  }

  void _scheduleRenewal(Uri url) {
    _renewal?.cancel();
    final expiry = _expirySeconds(url);
    if (expiry == null) return;
    final remaining = expiry - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Refresh the provider metadata up to 90 seconds before token expiry.
    // Do not restart the player solely because its URL has a deadline.
    final delay = remaining > 100 ? remaining - 90
        : remaining > 30 ? remaining - 25 : 5;
    _renewal = Timer(Duration(seconds: delay), () {
      if (mounted && !_disposed) unawaited(_refreshSources());
    });
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (_fullScreen == enabled || !mounted) return;
    setState(() => _fullScreen = enabled);
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

  void _revealControls() {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _showControls = true);
    _controlsTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_disposed && _video?.value.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _changeVolume(double volume) {
    setState(() => _volume = volume);
    unawaited(_video?.setVolume(volume) ?? Future<void>.value());
    _revealControls();
  }

  void _togglePause() {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (video.value.isPlaying) {
      _userPaused = true;
      unawaited(video.pause());
    } else {
      _userPaused = false;
      _lastAdvance = DateTime.now();
      unawaited(video.play());
    }
    _revealControls();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _foreground = false;
      _video?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _lastAdvance = DateTime.now();
      if (!_userPaused) {
        final expiry = _expirySeconds(_activeUri);
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (expiry != null && expiry <= now + 45) {
          // A backgrounded player can hold an expired HLS token. Resolve a
          // fresh one on resume rather than reusing the old media URL.
          unawaited(_connect());
        } else {
          _video?.play();
          unawaited(_refreshSources());
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _renewal?.cancel();
    _retry?.cancel();
    _watchdog?.cancel();
    _sourceRefresh?.cancel();
    _controlsTimer?.cancel();
    if (_fullScreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
    final video = _video;
    video?.removeListener(_onMediaChanged);
    unawaited(video?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Widget _qualityMenu() {
    return PopupMenuButton<int>(
      tooltip: label('اختيار السيرفر والجودة', 'Choose server and quality'),
      initialValue: _selectedSource,
      enabled: !_connecting && _sources.isNotEmpty,
      icon: const Icon(Icons.tune_rounded, color: Colors.white),
      onSelected: (index) {
        _revealControls();
        unawaited(_connect(userRetry: true, preferredSource: index));
      },
      itemBuilder: (_) => [
        for (var i = 0; i < _sources.length; i++)
          PopupMenuItem<int>(value: i,
            child: Row(children: [
              Icon(i == _selectedSource ? Icons.check_circle_rounded
                  : Icons.hd_outlined,
                color: i == _selectedSource
                    ? const Color(0xFF12D6C0) : Colors.white70),
              const SizedBox(width: 9),
              Flexible(child: Text(_sources[i].label,
                overflow: TextOverflow.ellipsis)),
            ])),
      ],
    );
  }

  Widget _playerContent() {
    final player = _video;
    const teal = Color(0xFF12D6C0);
    if (_busy && player == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: teal),
        const SizedBox(height: 18),
        Text(label('جارٍ جلب سيرفر القناة وبدء البث...',
            'Resolving channel server and opening stream...'),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]));
    }
    if (player == null || !player.value.isInitialized) {
      return Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.live_tv_rounded, size: 54, color: Colors.white54),
          const SizedBox(height: 15),
          Text(_failure ?? label('البث غير متاح حاليًا', 'Stream unavailable'),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _connecting ? null : () => _connect(userRetry: true),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(label('تحديث رابط القناة', 'Refresh channel URL')),
          ),
        ])));
    }
    return Center(child: AspectRatio(
      aspectRatio: player.value.aspectRatio > 0
          ? player.value.aspectRatio : 16 / 9,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _revealControls,
        onDoubleTap: () => _setFullscreen(!_fullScreen),
        child: Stack(fit: StackFit.expand, children: [
          VideoPlayer(player),
          // Transparent status layer; live playback is not time-seekable.
          PositionedDirectional(top: 11, start: 11,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xD9101827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: teal.withValues(alpha: .45))),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: teal),
                  SizedBox(width: 7),
                  Text('LIVE', style: TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.white,
                    letterSpacing: 1.1, fontSize: 11)),
                ]),
              ),
            )),
          if (player.value.isBuffering)
            const Center(child: CircularProgressIndicator(
              color: teal, strokeWidth: 3)),
          IgnorePointer(
            ignoring: !_showControls,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: Column(children: [
                if (_fullScreen)
                  Align(alignment: AlignmentDirectional.topEnd,
                    child: Padding(padding: const EdgeInsets.all(6),
                      child: IconButton.filledTonal(
                        tooltip: label('الخروج من ملء الشاشة', 'Exit fullscreen'),
                        icon: const Icon(Icons.fullscreen_exit_rounded),
                        onPressed: () => _setFullscreen(false)))),
                const Spacer(),
                DecoratedBox(
                  decoration: const BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xED050A14)])),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 7),
                    child: Row(children: [
                      IconButton.filledTonal(
                        tooltip: label('تشغيل / إيقاف مؤقت', 'Play / Pause'),
                        icon: Icon(player.value.isPlaying
                          ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        onPressed: _togglePause),
                      IconButton(
                        tooltip: label('تحديث سيرفر القناة', 'Refresh channel server'),
                        onPressed: _connecting
                          ? null : () => unawaited(_connect(userRetry: true)),
                        icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white)),
                      IconButton(
                        tooltip: label('كتم / تشغيل الصوت', 'Mute / Unmute'),
                        onPressed: () => _changeVolume(_volume == 0 ? 1.0 : 0.0),
                        icon: Icon(_volume <= 0
                          ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: Colors.white)),
                      Expanded(child: Slider(
                        value: _volume, min: 0, max: 1,
                        activeColor: teal, inactiveColor: Colors.white38,
                        onChanged: _changeVolume)),
                      _qualityMenu(),
                      IconButton(
                        tooltip: label('ملء الشاشة', 'Fullscreen'),
                        onPressed: () => _setFullscreen(!_fullScreen),
                        icon: Icon(_fullScreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                          color: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullScreen) unawaited(_setFullscreen(false));
      },
      child: Scaffold(backgroundColor: const Color(0xFF060A10),
        appBar: _fullScreen ? null : AppBar(
          backgroundColor: const Color(0xFF101827),
          title: Text(widget.channel.title(widget.ar),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_sources.length > 1)
              PopupMenuButton<int>(
                tooltip: label('السيرفر والجودة', 'Server and quality'),
                icon: const Icon(Icons.high_quality_rounded),
                initialValue: _selectedSource,
                onSelected: (index) => _connect(
                  userRetry: true, preferredSource: index),
                itemBuilder: (_) => [
                  for (var i = 0; i < _sources.length; i++)
                    PopupMenuItem(value: i,
                      child: Text(_sources[i].label +
                        (i == _selectedSource ? ' ✓' : ''))),
                ]),
            IconButton(
              tooltip: label('تحديث رابط القناة', 'Refresh stream'),
              onPressed: _connecting ? null : () => _connect(userRetry: true),
              icon: const Icon(Icons.refresh_rounded)),
            IconButton(
              tooltip: label('ملء الشاشة', 'Fullscreen'),
              onPressed: () => _setFullscreen(true),
              icon: const Icon(Icons.fullscreen_rounded)),
          ],
        ),
        body: SafeArea(
          top: !_fullScreen, bottom: !_fullScreen,
          child: Column(children: [
            Expanded(child: _playerContent()),
            if (!_fullScreen) ...[
              Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 5),
                child: Row(children: [
                  const Icon(Icons.circle, color: Color(0xFF12D6C0), size: 8),
                  const SizedBox(width: 7),
                  Expanded(child: Text(label(
                    'EGY TV SPORT · فحص السيرفر كل دقيقة وتجديد الرابط قبل انتهائه',
                    'EGY TV SPORT · Check server every minute; refresh expiring URLs') +
                    (_lastSourceCheck == null ? '' :
                      ' · ' + _lastSourceCheck!.hour.toString().padLeft(2, '0') +
                      ':' + _lastSourceCheck!.minute.toString().padLeft(2, '0')),
                    style: const TextStyle(color: Colors.white70, fontSize: 12))),
                ])),
              // Reuse EGYSHOW's approved ad manager placements.
              EgyshowBannerAd(api: widget.api, placement: 'player_bottom',
                height: 84),
            ],
          ]),
        ),
      ),
    );
  }
}

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
      headers: const {'User-Agent': _apiAgent, 'Accept': 'application/json'},
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
    unawaited(_connect());
  }

  Future<void> _connect({bool userRetry = false, int preferredSource = 0}) async {
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
      final sources = await _ProviderMediaResolver(widget.api.client)
          .resolve(widget.channel.providerId);
      if (_disposed || !mounted) return;
      _sources = sources;
      final indices = [
        if (preferredSource >= 0 && preferredSource < sources.length) preferredSource,
        for (var i = 0; i < sources.length; i++)
          if (i != preferredSource) i,
      ];
      for (final index in indices) {
        final source = sources[index];
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
          candidate.addListener(_onMediaChanged);
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
      if (mounted) setState(() => _failure = label(
        'حدث انقطاع في البث؛ جاري تحديث الرابط...',
        'Stream interrupted; refreshing the channel...'));
      _scheduleRetry();
    } else if (mounted) {
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
    final expiry = int.tryParse(
      url.queryParameters['e'] ?? url.queryParameters['expires'] ?? '',
    );
    if (expiry == null || expiry < 1700000000) return;
    final remaining = expiry - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (remaining <= 25) return;
    _renewal = Timer(Duration(seconds: remaining - 20), () {
      if (mounted && !_disposed) unawaited(_connect());
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
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _video?.pause();
    } else if (state == AppLifecycleState.resumed && !_userPaused) {
      _lastAdvance = DateTime.now();
      _video?.play();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _renewal?.cancel();
    _retry?.cancel();
    _watchdog?.cancel();
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

  Widget _playerContent() {
    final player = _video;
    if (_busy) return const Center(child: CircularProgressIndicator(
      color: Color(0xFF12D6C0)));
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
            label: Text(label('إعادة المحاولة', 'Retry')),
          ),
        ])));
    }
    return Center(child: AspectRatio(
      aspectRatio: player.value.aspectRatio > 0
          ? player.value.aspectRatio : 16 / 9,
      child: Stack(fit: StackFit.expand, children: [
        VideoPlayer(player),
        PositionedDirectional(start: 8, bottom: 7,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton.filledTonal(
              tooltip: label('تشغيل / إيقاف', 'Play / Pause'),
              icon: Icon(player.value.isPlaying ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
              onPressed: _togglePause),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: label('ملء الشاشة', 'Fullscreen'),
              icon: Icon(_fullScreen ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded),
              onPressed: () => _setFullscreen(!_fullScreen)),
          ])),
        if (_fullScreen)
          PositionedDirectional(top: 6, end: 6,
            child: IconButton.filledTonal(
              onPressed: () => _setFullscreen(false),
              icon: const Icon(Icons.close_rounded))),
        if (player.value.isBuffering)
          const Positioned(top: 15, left: 0, right: 0,
            child: LinearProgressIndicator(
              color: Color(0xFF12D6C0), minHeight: 2)),
      ]),
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
                    'EGY TV SPORT · تحديث تلقائي لرابط القناة عند الحاجة',
                    'EGY TV SPORT · Automatic channel URL refresh'),
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

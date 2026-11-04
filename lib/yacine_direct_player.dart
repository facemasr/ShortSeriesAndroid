import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  const _YacineMediaSource(this.uri, this.headers);
  final Uri uri;
  final Map<String, String> headers;
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
      found.add(_YacineMediaSource(url, headers));
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
  bool _busy = true;
  bool _connecting = false;
  String? _failure;
  int _failures = 0;
  bool _disposed = false;

  String label(String ar, String en) => widget.ar ? ar : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_connect());
  }

  Future<void> _connect({bool userRetry = false}) async {
    if (_connecting || _disposed) return;
    _connecting = true;
    _retry?.cancel();
    _renewal?.cancel();
    if (userRetry) _failures = 0;
    if (mounted) setState(() { _busy = true; _failure = null; });
    final previous = _video;
    _video = null;
    if (previous != null) {
      previous.removeListener(_onMediaChanged);
      await previous.dispose();
    }
    try {
      final sources = await _ProviderMediaResolver(widget.api.client)
          .resolve(widget.channel.providerId);
      for (final source in sources) {
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
          _video = candidate;
          candidate.addListener(_onMediaChanged);
          await candidate.play();
          // Retain the limited automatic-retry count for this session.
          _scheduleRenewal(source.uri);
          setState(() { _busy = false; _failure = null; });
          return;
        } catch (_) {
          candidate?.removeListener(_onMediaChanged);
          await candidate?.dispose();
        }
      }
      throw const ApiException('all_sources_unavailable');
    } catch (_) {
      if (mounted && !_disposed) {
        setState(() {
          _busy = false;
          _failure = label(
            'مصدر القناة لا يسمح بالتشغيل على هذا الجهاز أو أنه غير متاح حاليًا.',
            'This channel is unavailable or not authorized on this device.',
          );
        });
      }
    } finally {
      _connecting = false;
    }
  }

  void _onMediaChanged() {
    final video = _video;
    if (video == null || !video.value.hasError ||
        _connecting || _disposed || _retry != null) return;
    if (_failures >= 2) {
      if (mounted) {
        setState(() => _failure = label(
          'انقطع المصدر. يمكنك إعادة المحاولة.',
          'The source stopped. You can retry.',
        ));
      }
      return;
    }
    _failures++;
    _retry = Timer(Duration(seconds: 3 * _failures), () {
      _retry = null;
      if (mounted && !_disposed) unawaited(_connect());
    });
  }

  void _scheduleRenewal(Uri url) {
    final expiry = int.tryParse(
      url.queryParameters['e'] ?? url.queryParameters['expires'] ?? '',
    );
    if (expiry == null || expiry < 1700000000) return;
    final remaining = expiry - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (remaining <= 25) return;
    final delay = Duration(seconds: remaining - 20);
    _renewal = Timer(delay, () {
      if (mounted && !_disposed) unawaited(_connect());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _video?.pause();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _renewal?.cancel();
    _retry?.cancel();
    final video = _video;
    video?.removeListener(_onMediaChanged);
    unawaited(video?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.channel.title(widget.ar), maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _connecting ? null : () => _connect(userRetry: true),
            tooltip: label('تحديث رابط القناة', 'Refresh channel'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: Column(children: [
        Expanded(child: Center(child: _busy
          ? const CircularProgressIndicator()
          : _failure != null
            ? Padding(padding: const EdgeInsets.all(22),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.live_tv, size: 42, color: Colors.white54),
                  const SizedBox(height: 12),
                  Text(_failure!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _connect(userRetry: true),
                    icon: const Icon(Icons.refresh),
                    label: Text(label('إعادة المحاولة', 'Try again')),
                  ),
                ]))
            : (player != null && player.value.isInitialized)
              ? AspectRatio(
                  aspectRatio: player.value.aspectRatio > 0
                      ? player.value.aspectRatio : 16 / 9,
                  child: Stack(children: [
                    Positioned.fill(child: VideoPlayer(player)),
                    Positioned(left: 8, bottom: 8, child: IconButton.filledTonal(
                      icon: Icon(player.value.isPlaying
                          ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        if (player.value.isPlaying) {
                          player.pause();
                        } else {
                          player.play();
                        }
                        setState(() {});
                      },
                    )),
                  ]))
              : const SizedBox.shrink())),
        // Reuse existing native banner inventory without modifying movie ads.
        EgyshowBannerAd(api: widget.api, placement: 'player_bottom', height: 84),
      ])),
    );
  }
}

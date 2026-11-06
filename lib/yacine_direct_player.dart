import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'native_api.dart';
import 'native_banner_ads.dart';
import 'yacine_media_format.dart';
import 'yacine_channel_resolver.dart';
import 'yacine_vlc_m3u.dart';
import 'yacine_stream_probe.dart';
import 'yacine_stream_renewal.dart';
import 'yacine_android_channel_service.dart';
import 'yacine_vlc_player.dart';
import 'yacine_channel_groups.dart';
import 'yacine_external_player.dart';
import 'yacine_playback_settings.dart';

/// Direct, device-side playback for provider-authorized HLS channels.
/// No EGYSHOW VPS media relay, DRM circumvention, stored signed URLs or
/// changes to the existing movie/series WebView player.
class DirectYacineChannelPlayer extends StatefulWidget {
  const DirectYacineChannelPlayer({
    super.key, required this.channel, required this.api, required this.ar,
    this.qualityVariants = const [], this.attemptedVariants = const [],
  });

  final LiveChannel channel;
  /// Every original provider ID in the quality group, as on EGY TV Sport.
  final List<LiveChannel> qualityVariants;
  final List<String> attemptedVariants;
  final EgyApi api;
  final bool ar;

  @override
  State<DirectYacineChannelPlayer> createState() =>
      _DirectYacineChannelPlayerState();
}

class _DirectYacineChannelPlayerState
    extends State<DirectYacineChannelPlayer> with WidgetsBindingObserver {
  // Stream-resolution requests never use the EGYSHOW website API client.
  final http.Client _channelClient = http.Client();
  VideoPlayerController? _video;
  Timer? _renewal;
  Timer? _retry;
  Timer? _watchdog;
  Timer? _sourceRefresh;
  Timer? _controlsTimer;
  bool _showControls = true;
  double _volume = 1.0;
  double _speed = 1.0;
  bool _externalOpening = false;
  BoxFit _videoFit = BoxFit.contain;
  bool _landscapeLeft = true;
  bool _refreshingSources = false;
  bool _foreground = true;
  Uri? _activeUri;
  Map<String, String>? _activeHeaders;
  DateTime? _activeSince;
  String? _activeLabel;
  DateTime? _lastSourceCheck;
  bool _lastBuffering = false;
  bool _lastPlaying = false;
  List<YacinePlaybackSource> _sources = const [];
  int _selectedSource = 0;
  bool _busy = true;
  bool _connecting = false;
  bool _fullScreen = false;
  bool _userPaused = false;
  String? _failure;
  String? _lastProbeFailure;
  int _failures = 0;
  bool _disposed = false;
  bool _switchingVariant = false;
  late String _currentProviderId;
  Duration? _lastPosition;
  DateTime _lastAdvance = DateTime.now();

  String label(String ar, String en) => widget.ar ? ar : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentProviderId = widget.channel.providerId;
    _watchdog = Timer.periodic(const Duration(seconds: 6), (_) => _checkPlayback());
    // Refresh only the actively viewed channel; polling 675 channels would
    // overload the provider and invalidate good streams unnecessarily.
    _sourceRefresh = Timer.periodic(const Duration(seconds: 60),
        (_) => unawaited(_refreshSources()));
    unawaited(_connect());
  }

  /// A 404 means this provider station ID may have rotated; re-discover
  /// the exact station in the matching quality package and retry once.
  Future<T> _withCurrentChannel<T>(
      Future<T> Function(String id) operation) async {
    try {
      return await operation(_currentProviderId);
    } on YacineResolveException catch (error) {
      if (error.reason != 'provider_api_http_404') rethrow;
      final updated = await widget.api.refreshProviderChannel(widget.channel);
      if (updated == null || updated.providerId == _currentProviderId) rethrow;
      _currentProviderId = updated.providerId;
      return operation(_currentProviderId);
    }
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
      final refreshed = await _withCurrentChannel((id) =>
          EgyTvAndroidChannelService(_channelClient).refresh(id,
              currentLabel: _activeLabel, currentIndex: _selectedSource));
      final fresh = refreshed.sources;
      if (!mounted || _disposed || !_foreground || _userPaused) return;
      _lastSourceCheck = DateTime.now();
      final sameLabel = fresh.indexWhere((s) => s.label == _activeLabel);
      final preferred = sameLabel >= 0 ? sameLabel
          : _selectedSource < fresh.length ? _selectedSource : 0;
      final replacement = fresh[preferred];
      _sources = fresh;
      // Metadata can change without a player restart. In particular, short
      // lived signed HLS URLs must not be kept as the permanent source.
      final healthy = playing.value.isPlaying && !playing.value.hasError &&
          !playing.value.isBuffering;
      if (yacineHotSwapNeeded(
          activeUri: _activeUri,
          activeHeaders: _activeHeaders,
          updatedUri: replacement.uri,
          updatedHeaders: replacement.headers,
          activeSince: _activeSince,
          now: DateTime.now(),
          healthy: healthy)) {
        // Pre-initialize an updated player. The old video stays visible until
        // the new session starts successfully. No player restart per poll.
        await _connect(preferredSource: preferred, preloadedSources: fresh);
      } else if (_activeUri != null && _expirySeconds(_activeUri) != null) {
        _scheduleRenewal(_activeUri!);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // A transient provider API error must not stop a playable channel.
      _renewal?.cancel();
      _renewal = Timer(const Duration(seconds: 15),
          () => unawaited(_refreshSources()));
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
      List<YacinePlaybackSource>? preloadedSources}) async {
    if (_connecting || _disposed) return;
    _connecting = true;
    _retry?.cancel();
    _retry = null;
    // Keep the existing renewal deadline during replacement preparation.
    if (userRetry) _failures = 0;
    _lastProbeFailure = null;
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
      final choice = preloadedSources == null
          ? await _withCurrentChannel((id) =>
              EgyTvAndroidChannelService(_channelClient).choose(
                  id, preferredIndex: preferredSource,
                  quickCheck: previous == null))
          : null;
      final sources = preloadedSources ?? choice!.sources;
      // Start with the best reachable server just as Windows' choose()
      // does, then try the remaining provider sources if the native
      // Android decoder rejects the initial source.
      if (choice != null && previous == null) {
        preferredSource = choice.index;
      }
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
        // The native Android video engine is the actual playback authority.
        // A separate Dart HTTP probe may be rejected while ExoPlayer works,
        // so probing must never block the first playback attempt.
        VideoPlayerController? candidate;
        try {
          candidate = VideoPlayerController.networkUrl(
            source.uri,
            httpHeaders: source.headers,
            formatHint: yacineMediaFormat(source.uri, providerMode: source.providerMode),
          );
          await candidate.initialize().timeout(const Duration(seconds: 16));
          if (_disposed || !mounted) {
            await candidate.dispose();
            return;
          }
          await candidate.play();
          if (_speed != 1.0) {
            try {
              await candidate.setPlaybackSpeed(_speed);
            } catch (_) {
              // A live stream may not permit playback-rate changes.
            }
          }
          if (_disposed || !mounted) {
            await candidate.dispose();
            return;
          }
          final oldActive = _video;
          _video = candidate;
          _selectedSource = index;
          _activeUri = source.uri;
          _activeHeaders = source.headers;
          _activeSince = DateTime.now();
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
          _lastProbeFailure = null;
          if (mounted) setState(() { _busy = false; _failure = null; });
          return;
        } catch (_) {
          // Diagnose only the first native playback failure, on the device.
          // A reachable manifest/segment is not proof that ExoPlayer can decode
          // it, and a 403 here reflects the upstream provider response.
          if (_lastProbeFailure == null && !_disposed) {
            try {
              if (yacineMediaFormat(source.uri, providerMode: source.providerMode) == VideoFormat.hls) {
                final result = await YacineMediaProbe(_channelClient)
                    .verifyHls(source.uri, source.headers);
                _lastProbeFailure = result == YacineMediaStatus.manifestOnly
                    ? 'manifest_only' : 'native_player_failed';
              } else {
                _lastProbeFailure = 'native_player_failed';
              }
            } on YacineProbeFailure catch (e) {
              _lastProbeFailure = e.code;
            } catch (_) {
              _lastProbeFailure = 'playback_diagnostic_failed';
            }
          }
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
            _lastProbeFailure == 'source_http_403'
                ? 'مصدر البث يرفض تشغيل هذه القناة (403). سيتم طلب رابط جديد.'
                : 'لم يتم التحقق من بث متاح لهذه القناة. ستتم إعادة المحاولة.',
            _lastProbeFailure == 'source_http_403'
                ? 'The stream provider rejected this channel (403). Retrying with a fresh URL.'
                : 'No verified live stream is available. Retrying.',
          );
        });
      }
    } finally {
      _connecting = false;
      if (!connected && mounted && !_disposed) {
        final stillPlaying = _video?.value.isInitialized == true &&
            _video?.value.isPlaying == true &&
            _video?.value.hasError == false &&
            _video?.value.isBuffering == false;
        if (stillPlaying) {
          // An unsuccessful replacement must not interrupt good playback.
          _renewal?.cancel();
          _renewal = Timer(const Duration(seconds: 15),
              () => unawaited(_refreshSources()));
        } else if (!_tryNextQualityVariant()) {
          _scheduleRetry();
        }
      }
    }
  }

  /// EGY TV Sport's fall-through to another quality source when the
  /// currently chosen provider channel has no playable server.
  /// Each original provider channel is attempted once: never loop forever.
  bool _tryNextQualityVariant() {
    if (_switchingVariant || widget.qualityVariants.length < 2) return false;
    final tried = {...widget.attemptedVariants, widget.channel.providerId};
    final ordered = widget.qualityVariants.toList()
      ..sort((a, b) => (yacineChannelQuality(a) ?? 0)
          .compareTo(yacineChannelQuality(b) ?? 0));
    final currentQuality = yacineChannelQuality(widget.channel) ?? 1080;
    LiveChannel? target;
    for (final item in ordered.reversed) {
      if (tried.contains(item.providerId)) continue;
      final quality = yacineChannelQuality(item) ?? 0;
      if (quality <= currentQuality) {
        target = item;
        break;
      }
    }
    target ??= ordered.where((item) =>
        !tried.contains(item.providerId)).firstOrNull;
    if (target == null) return false;
    _switchingVariant = true;
    final candidate = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => DirectYacineChannelPlayer(
          channel: candidate,
          qualityVariants: widget.qualityVariants,
          attemptedVariants: tried.toList(),
          api: widget.api,
          ar: widget.ar,
        ),
      ));
    });
    return true;
  }

  void _scheduleRetry() {
    if (_disposed || _retry != null || _connecting || _switchingVariant) return;
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
    if (_disposed || _connecting || !_foreground || player == null ||
        !player.value.isInitialized || _userPaused) return;
    if (player.value.hasError) {
      _scheduleRetry();
      return;
    }
    final position = player.value.position;
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastAdvance = DateTime.now();
      if (_failures > 0) _failures = 0;
    } else if (player.value.isBuffering &&
        DateTime.now().difference(_lastAdvance).inSeconds > 25) {
      // Some live HLS broadcasts do not advance their exposed play position.
      // Only restart after sustained buffering, not a healthy live picture.
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
    final delay = remaining > 135 ? remaining - 120 : 15;
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

  /// YTV-style manual screen rotation while keeping the player embedded.
  /// Android's native orientation is restored when leaving fullscreen.
  Future<void> _rotateVideo() async {
    if (_disposed || !mounted) return;
    if (!_fullScreen) await _setFullscreen(true);
    _landscapeLeft = !_landscapeLeft;
    await SystemChrome.setPreferredOrientations([
      _landscapeLeft ? DeviceOrientation.landscapeLeft
          : DeviceOrientation.landscapeRight,
    ]);
    _revealControls();
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
      final expiry = _expirySeconds(_activeUri);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiry != null && expiry <= now + 120) {
        unawaited(_connect(userRetry: true));
      } else {
        unawaited(video.play());
        unawaited(_refreshSources());
      }
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
        if (expiry != null && expiry <= now + 120) {
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
    _channelClient.close();
    super.dispose();
  }

()=>methods+anchor
  /// Never save signed tokens or long-lived media links to the catalog.
  Future<void> _copyCurrentChannelM3u() async {
    if (_connecting || _disposed) return;
    try {
      final fresh = await _withCurrentChannel(
          (id) => YacineChannelResolver(_channelClient).resolve(id));
      if (_disposed || !mounted || fresh.isEmpty) return;
      final preferred = fresh.indexWhere((s) => s.label == _activeLabel);
      final source = fresh[preferred >= 0 ? preferred : 0];
      final playlist = yacineVlcM3u(
        stream: source.uri,
        channelName: widget.channel.title(widget.ar),
        tvgId: _currentProviderId,
        groupTitle: widget.channel.group,
        headers: source.headers,
      );
      await Clipboard.setData(ClipboardData(text: playlist));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label(
          'تم نسخ ملف M3U الحالي. الروابط المؤقتة تنتهي صلاحيتها.',
          'Current M3U copied. Temporary stream links expire.'))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label(
          'تعذر جلب رابط جديد للقناة الآن.',
          'Could not retrieve a fresh channel link.'))));
    }
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

  Widget _aspectMenu() {
    return PopupMenuButton<BoxFit>(
      tooltip: label('نسبة عرض الفيديو', 'Video aspect ratio'),
      initialValue: _videoFit,
      icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
      onSelected: (fit) { setState(() => _videoFit = fit); _revealControls(); },
      itemBuilder: (_) => [
        PopupMenuItem(value: BoxFit.contain,
          child: Text(label('ملاءمة الشاشة', 'Fit screen'))),
        PopupMenuItem(value: BoxFit.cover,
          child: Text(label('ملء الشاشة دون تشويه', 'Fill and crop'))),
        PopupMenuItem(value: BoxFit.fill,
          child: Text(label('تمديد الصورة', 'Stretch video'))),
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
    final videoSize = player.value.size;
    return SizedBox.expand(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _revealControls,
        onDoubleTap: () => _setFullscreen(!_fullScreen),
        child: Stack(fit: StackFit.expand, children: [
          ClipRect(child: FittedBox(
            fit: _videoFit, alignment: Alignment.center,
            child: SizedBox(
              width: videoSize.width > 0 ? videoSize.width : 1280,
              height: videoSize.height > 0 ? videoSize.height : 720,
              child: VideoPlayer(player),
            ),
          )),
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
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton.filledTonal(
                          tooltip: label('تدوير الشاشة', 'Rotate screen'),
                          icon: const Icon(Icons.screen_rotation_rounded),
                          onPressed: _rotateVideo),
                        const SizedBox(width: 5),
                        IconButton.filledTonal(
                          tooltip: label('الخروج من ملء الشاشة', 'Exit fullscreen'),
                          icon: const Icon(Icons.fullscreen_exit_rounded),
                          onPressed: () => _setFullscreen(false)),
                      ]))),
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
                      _aspectMenu(),
                      IconButton(
                        tooltip: label('إعدادات المشغّل', 'Player settings'),
                        onPressed: _showPlaybackSettings,
                        icon: const Icon(Icons.settings_rounded,
                          color: Colors.white)),
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
            if (widget.qualityVariants.length > 1)
              PopupMenuButton<String>(
                tooltip: label('جودة القناة', 'Channel quality'),
                icon: const Icon(Icons.hd_rounded),
                onSelected: (providerId) {
                  final matches = widget.qualityVariants.where((variant) =>
                      variant.providerId == providerId);
                  if (matches.isEmpty ||
                      providerId == widget.channel.providerId) return;
                  Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                    builder: (_) => DirectYacineChannelPlayer(
                      channel: matches.first,
                      qualityVariants: widget.qualityVariants,
                      api: widget.api, ar: widget.ar,
                    ),
                  ));
                },
                itemBuilder: (_) => [
                  for (final variant in widget.qualityVariants)
                    PopupMenuItem<String>(
                      value: variant.providerId,
                      child: Text(
                        variant.title(widget.ar) + ' · ' +
                        (yacineChannelQuality(variant)?.toString() ?? '-') +
                        'p' + (variant.providerId ==
                            widget.channel.providerId ? ' ✓' : ''),
                      ),
                    ),
                ],
              ),
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
            PopupMenuButton<String>(
              tooltip: label('محرك التشغيل', 'Playback engine'),
              icon: const Icon(Icons.settings_input_component_rounded),
              onSelected: (mode) {
                if (mode != 'vlc') return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => YacineVlcChannelPlayer(
                      channel: widget.channel,
                      qualityVariants: widget.qualityVariants,
                      api: widget.api, ar: widget.ar),
                  ));
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(value: 'vlc',
                  child: Text(label('جرّب VLC الداخلي',
                      'Try native VLC instead'))),
              ],
            ),
            IconButton(
              tooltip: label('تشغيل في مشغّل خارجي', 'Open external player'),
              onPressed: () =>
                  unawaited(_openExternal(YacineExternalTarget.choose)),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
            IconButton(
              tooltip: label('إعدادات المشغّل', 'Player settings'),
              onPressed: _showPlaybackSettings,
              icon: const Icon(Icons.settings_rounded),
            ),
            IconButton(
              tooltip: label('نسخ رابط القناة بصيغة M3U', 'Copy current channel M3U'),
              onPressed: _connecting ? null : _copyCurrentChannelM3u,
              icon: const Icon(Icons.playlist_add_check_rounded)),
            IconButton(
              tooltip: label('تحديث رابط القناة', 'Refresh stream'),
              onPressed: _connecting ? null : () => _connect(userRetry: true),
              icon: const Icon(Icons.refresh_rounded)),
            IconButton(
              tooltip: label('تدوير الشاشة', 'Rotate screen'),
              onPressed: _rotateVideo,
              icon: const Icon(Icons.screen_rotation_rounded)),
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

part of 'main.dart';

class ProPlayerPage extends StatefulWidget {
  final String ownerType;
  final int ownerId;
  final String title;

  const ProPlayerPage({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.title,
  });

  @override
  State<ProPlayerPage> createState() => _ProPlayerPageState();
}

class _ProPlayerPageState extends State<ProPlayerPage> {
  late final Player player;
  late final VideoController controller;

  late String ownerType;
  late int ownerId;
  late String title;

  List<Map<String, dynamic>> sources = [];
  List<Map<String, dynamic>> subtitles = [];
  Map<String, dynamic> contextData = {};
  Map<String, dynamic> playerSettings = {};
  int currentSource = 0;
  int currentSubtitle = -1;
  double playbackRate = 1.0;
  final Set<int> failedSources = <int>{};
  bool fallbackBusy = false;
  StreamSubscription<String>? playerErrorSub;

  bool loading = true;
  bool transitioning = false;
  bool viewSent = false;
  bool showSkipIntro = false;
  bool nextPromptDismissed = false;
  bool autoplayNext = true;
  String? error;
  int playedSeconds = 0;
  int nextCountdown = 0;

  Timer? timer;

  @override
  void initState() {
    super.initState();
    ownerType = widget.ownerType;
    ownerId = widget.ownerId;
    title = widget.title;

    player = Player();
    controller = VideoController(player);
    playerErrorSub = player.stream.error.listen((message) {
      if (!loading && !transitioning && !fallbackBusy) {
        unawaited(_fallbackSource(message));
      }
    });
    _loadTarget(ownerType, ownerId, title);

    timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Map<String, dynamic>? _mapValue(String key) {
    final value = contextData[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  int get _countdownSeconds {
    final raw = playerSettings['next_countdown'];
    return (raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? ''))?.clamp(3, 30) ?? 8;
  }

  bool _boolSetting(String key, [bool fallback = true]) {
    final value = playerSettings[key];
    if (value == null) return fallback;
    return value == true || value == 1 || value == '1';
  }

  Future<void> _loadTarget(String type, int id, String fallbackTitle) async {
    if (transitioning) return;

    setState(() {
      loading = true;
      error = null;
      transitioning = true;
      nextPromptDismissed = false;
      showSkipIntro = false;
      nextCountdown = 0;
      playedSeconds = 0;
      viewSent = false;
    });

    try {
      final result = await Api.I.call(
        'playback',
        query: {'owner_type': type, 'owner_id': id},
      );
      final data = Map<String, dynamic>.from(result['data'] as Map);

      final nextSources = (data['sources'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (nextSources.isEmpty) {
        throw Exception(Api.I.ar ? 'لا يوجد مصدر تشغيل' : 'No playback source');
      }

      ownerType = type;
      ownerId = id;
      sources = nextSources;
      subtitles = (data['subtitles'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      failedSources.clear();
      currentSubtitle = -1;
      playbackRate = 1.0;
      contextData = data['context'] is Map
          ? Map<String, dynamic>.from(data['context'] as Map)
          : <String, dynamic>{};
      playerSettings = data['player'] is Map
          ? Map<String, dynamic>.from(data['player'] as Map)
          : <String, dynamic>{};
      autoplayNext = _boolSetting('autoplay_next', true);
      currentSource = 0;

      final current = _mapValue('current');
      final media = _mapValue('media');
      if (type == 'episode' && current != null) {
        final episodeTitle = (current['title'] ?? '').toString();
        final season = (current['season_number'] ?? '').toString();
        final episode = (current['episode_number'] ?? '').toString();
        title = episodeTitle.isNotEmpty
            ? episodeTitle
            : ((media?['title'] ?? media?['original_title'] ?? fallbackTitle).toString());
        if (title.isEmpty) {
          title = (Api.I.ar ? 'الموسم ' : 'Season ') + season +
              ' • ' + (Api.I.ar ? 'الحلقة ' : 'Episode ') + episode;
        }
      } else {
        title = (media?['title'] ?? media?['original_title'] ?? fallbackTitle).toString();
      }

      var resumeAt = 0;
      if (_boolSetting('resume_enabled', true) && type != 'tv') {
        final resume = data['resume'];
        if (resume is Map) {
          resumeAt = (resume['progress_seconds'] as num? ?? 0).toInt();
        }
        final local = await Api.I.localResume(type, id);
        if (local > resumeAt) resumeAt = local;
      }

      await _openSource(0, resumeAt: resumeAt);

      if (mounted) {
        setState(() {
          loading = false;
          transitioning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          transitioning = false;
          error = e.toString();
        });
      }
    }
  }

  Map<String, String> _sourceHeaders(Map<String, dynamic> source) {
    final raw = source['headers_json'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
        }
      } catch (_) {}
    }
    return const <String, String>{};
  }

  Future<void> _openSource(int index, {int? resumeAt}) async {
    if (index < 0 || index >= sources.length) return;
    final oldPosition = player.state.position;
    final source = sources[index];
    final url = (source['url'] ?? '').toString();
    if (url.isEmpty) return;

    currentSource = index;
    error = null;
    final headers = _sourceHeaders(source);
    try {
      await player.open(
        Media(url, httpHeaders: headers.isEmpty ? null : headers),
        play: true,
      );

      final seekSeconds = resumeAt ?? oldPosition.inSeconds;
      if (seekSeconds > 8) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await player.seek(Duration(seconds: seekSeconds));
      }
      if (playbackRate != 1.0) {
        await player.setRate(playbackRate);
      }
      if (mounted) setState(() {});
    } catch (e) {
      failedSources.add(index);
      await _fallbackSource(e.toString(), resumeAt: resumeAt ?? oldPosition.inSeconds);
    }
  }

  Future<void> _fallbackSource(String reason, {int? resumeAt}) async {
    if (fallbackBusy || sources.length < 2) return;
    fallbackBusy = true;
    failedSources.add(currentSource);
    int next = -1;
    for (var i = 0; i < sources.length; i++) {
      if (!failedSources.contains(i)) {
        next = i;
        break;
      }
    }
    if (next < 0) {
      fallbackBusy = false;
      if (mounted) {
        setState(() {
          error = Api.I.ar
              ? 'تعذر تشغيل جميع السيرفرات المتاحة.'
              : 'All available playback servers failed.';
        });
      }
      return;
    }
    final position = resumeAt ?? player.state.position.inSeconds;
    fallbackBusy = false;
    await _openSource(next, resumeAt: position);
  }

  Future<void> _selectSubtitle(int index) async {
    if (index < 0) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      if (mounted) setState(() => currentSubtitle = -1);
      return;
    }
    if (index >= subtitles.length) return;
    final track = subtitles[index];
    final url = (track['url'] ?? '').toString();
    if (url.isEmpty) return;
    await player.setSubtitleTrack(
      SubtitleTrack.uri(
        url,
        title: (track['label'] ?? track['language'] ?? 'Subtitle').toString(),
        language: (track['language'] ?? '').toString(),
      ),
    );
    if (mounted) setState(() => currentSubtitle = index);
  }

  Future<void> _setSpeed(double value) async {
    await player.setRate(value);
    if (mounted) setState(() => playbackRate = value);
  }

  Future<void> _tick() async {
    if (!mounted || loading || transitioning || error != null) return;

    final position = player.state.position.inSeconds;
    final duration = player.state.duration.inSeconds;

    if (player.state.playing) {
      playedSeconds += 1;
    }

    if (!viewSent &&
        _boolSetting('view_tracking', true) &&
        playedSeconds >= 20 &&
        ownerType != 'tv') {
      viewSent = true;
      unawaited(Api.I.recordView(ownerType, ownerId));
    }

    if (playedSeconds > 0 && playedSeconds % 15 == 0) {
      unawaited(_saveProgress());
    }

    if (ownerType == 'episode') {
      final current = _mapValue('current');
      final next = _mapValue('next');

      var introVisible = false;
      if (_boolSetting('skip_intro', true) && current != null) {
        final start = (current['intro_start'] as num? ?? 0).toInt();
        final end = (current['intro_end'] as num? ?? 0).toInt();
        introVisible = end > start && position >= start && position < end;
      }

      var countdown = 0;
      if (autoplayNext &&
          next != null &&
          !nextPromptDismissed &&
          duration > 0) {
        final remaining = duration - position;
        if (remaining <= _countdownSeconds && remaining >= 0) {
          countdown = remaining.clamp(0, _countdownSeconds);
        }
      }

      if (introVisible != showSkipIntro || countdown != nextCountdown) {
        setState(() {
          showSkipIntro = introVisible;
          nextCountdown = countdown;
        });
      }

      if (next != null &&
          autoplayNext &&
          !nextPromptDismissed &&
          duration > 0 &&
          position >= duration - 1 &&
          !transitioning) {
        await _playEpisode(next);
      }
    }
  }

  Future<void> _saveProgress() async {
    if (ownerType == 'tv') return;
    final position = player.state.position.inSeconds;
    final duration = player.state.duration.inSeconds;
    if (duration <= 0) return;

    await Api.I.saveLocalProgress(ownerType, ownerId, position, duration);

    try {
      await Api.I.call(
        'progress',
        method: 'POST',
        data: {
          'owner_type': ownerType,
          'owner_id': ownerId,
          'progress_seconds': position,
          'duration_seconds': duration,
        },
      );
    } catch (_) {}
  }

  Future<void> _skipIntro() async {
    final current = _mapValue('current');
    if (current == null) return;
    final end = (current['intro_end'] as num? ?? 0).toInt();
    if (end > 0) {
      await player.seek(Duration(seconds: end));
      if (mounted) setState(() => showSkipIntro = false);
    }
  }

  Future<void> _playEpisode(Map<String, dynamic> episode) async {
    if (transitioning) return;
    await _saveProgress();
    final id = (episode['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    final episodeTitle = (episode['title'] ?? title).toString();
    await _loadTarget('episode', id, episodeTitle);
  }

  Future<void> _playNext() async {
    final next = _mapValue('next');
    if (next != null) await _playEpisode(next);
  }

  Future<void> _playPrevious() async {
    final prev = _mapValue('previous');
    if (prev != null) await _playEpisode(prev);
  }

  void _showSources() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14161D),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          itemCount: sources.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = sources[i];
            final label = (s['label'] ?? 'Server ' + (i + 1).toString()).toString();
            final quality = (s['quality'] ?? '').toString();
            final language = (s['language'] ?? '').toString();
            final meta = [quality, language].where((e) => e.isNotEmpty).join(' • ');
            return ListTile(
              leading: CircleAvatar(
                child: Text((i + 1).toString()),
              ),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: meta.isEmpty ? null : Text(meta),
              trailing: i == currentSource
                  ? const Icon(Icons.check_circle_rounded)
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _openSource(i);
              },
            );
          },
        ),
      ),
    );
  }

  void _showSubtitles() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14161D),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            ListTile(
              leading: const Icon(Icons.subtitles_off_outlined),
              title: Text(Api.I.ar ? 'إيقاف الترجمة' : 'Subtitles off'),
              trailing: currentSubtitle < 0 ? const Icon(Icons.check_circle_rounded) : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await _selectSubtitle(-1);
              },
            ),
            ...List.generate(subtitles.length, (i) {
              final track = subtitles[i];
              final label = (track['label'] ?? track['language'] ?? 'Subtitle').toString();
              final language = (track['language'] ?? '').toString();
              return ListTile(
                leading: const Icon(Icons.subtitles_rounded),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: language.isEmpty ? null : Text(language),
                trailing: currentSubtitle == i ? const Icon(Icons.check_circle_rounded) : null,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _selectSubtitle(i);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSpeed() {
    const values = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14161D),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                Api.I.ar ? 'سرعة التشغيل' : 'Playback speed',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            ...values.map((value) => ListTile(
                  title: Text(value == 1.0 ? (Api.I.ar ? 'عادي' : 'Normal') : value.toString() + '×'),
                  trailing: playbackRate == value ? const Icon(Icons.check_circle_rounded) : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _setSpeed(value);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showEpisodes() {
    final episodesRaw = contextData['episodes'];
    if (episodesRaw is! List || episodesRaw.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14161D),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        minChildSize: .35,
        initialChildSize: .68,
        maxChildSize: .9,
        builder: (_, scrollController) {
          final episodes = episodesRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: episodes.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final ep = episodes[i];
              final id = (ep['id'] as num?)?.toInt() ?? 0;
              final active = id == ownerId;
              return ListTile(
                selected: active,
                leading: SizedBox(
                  width: 82,
                  height: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: (ep['still'] ?? '').toString(),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.white10,
                        child: const Icon(Icons.movie_outlined),
                      ),
                    ),
                  ),
                ),
                title: Text(
                  ep['episode_number'].toString() + '. ' + (ep['title'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w700),
                ),
                subtitle: Text(
                  (ep['duration'] ?? 0).toString() + ' ' + (Api.I.ar ? 'دقيقة' : 'min'),
                ),
                trailing: active
                    ? const Icon(Icons.graphic_eq_rounded)
                    : const Icon(Icons.play_arrow_rounded),
                onTap: active
                    ? null
                    : () async {
                        Navigator.pop(sheetContext);
                        await _playEpisode(ep);
                      },
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    playerErrorSub?.cancel();
    unawaited(_saveProgress());
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _mapValue('current');
    final previous = _mapValue('previous');
    final next = _mapValue('next');
    final media = _mapValue('media');

    final episodeMeta = current == null
        ? ''
        : (Api.I.ar ? 'الموسم ' : 'S') + (current['season_number'] ?? '').toString() +
            ' • ' + (Api.I.ar ? 'الحلقة ' : 'E') + (current['episode_number'] ?? '').toString();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            if (episodeMeta.isNotEmpty)
              Text(
                episodeMeta,
                style: const TextStyle(fontSize: 11.5, color: Colors.white60),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: Api.I.ar ? 'السرعة' : 'Speed',
            onPressed: _showSpeed,
            icon: const Icon(Icons.speed_rounded),
          ),
          if (subtitles.isNotEmpty)
            IconButton(
              tooltip: Api.I.ar ? 'الترجمة' : 'Subtitles',
              onPressed: _showSubtitles,
              icon: const Icon(Icons.subtitles_rounded),
            ),
          if (sources.length > 1)
            IconButton(
              tooltip: Api.I.ar ? 'السيرفرات' : 'Servers',
              onPressed: _showSources,
              icon: const Icon(Icons.dns_outlined),
            ),
          if (ownerType == 'episode' &&
              _boolSetting('show_episode_list', true) &&
              contextData['episodes'] is List)
            IconButton(
              tooltip: Api.I.ar ? 'الحلقات' : 'Episodes',
              onPressed: _showEpisodes,
              icon: const Icon(Icons.format_list_numbered_rounded),
            ),
        ],
      ),
      body: error != null
          ? ErrorPage(
              error: error,
              retry: () => _loadTarget(ownerType, ownerId, title),
            )
          : Column(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(
                        controller: controller,
                        controls: AdaptiveVideoControls,
                      ),
                      if (loading)
                        const ColoredBox(
                          color: Color(0x44000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (showSkipIntro)
                        PositionedDirectional(
                          end: 14,
                          bottom: 62,
                          child: FilledButton.icon(
                            onPressed: _skipIntro,
                            icon: const Icon(Icons.fast_forward_rounded),
                            label: Text(Api.I.ar ? 'تخطي المقدمة' : 'Skip intro'),
                          ),
                        ),
                      if (next != null &&
                          nextCountdown > 0 &&
                          !nextPromptDismissed)
                        PositionedDirectional(
                          start: 12,
                          end: 12,
                          bottom: 12,
                          child: Material(
                            color: const Color(0xEE14161D),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 82,
                                    height: 50,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: CachedNetworkImage(
                                        imageUrl: (next['still'] ?? '').toString(),
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Container(color: Colors.white10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          Api.I.ar
                                              ? 'الحلقة التالية خلال ' + nextCountdown.toString() + ' ث'
                                              : 'Next episode in ' + nextCountdown.toString() + 's',
                                          style: const TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                        Text(
                                          (next['title'] ?? '').toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _playNext,
                                    icon: const Icon(Icons.play_arrow_rounded),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() => nextPromptDismissed = true),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const AppAd('app_player_pre'),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: const Color(0xFF08090C),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      children: [
                        if ((media?['title'] ?? media?['original_title'] ?? '').toString().isNotEmpty)
                          Text(
                            (media?['title'] ?? media?['original_title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        if (episodeMeta.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(episodeMeta, style: const TextStyle(color: Colors.white60)),
                        ],
                        if (ownerType == 'episode') ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: previous == null ? null : _playPrevious,
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  label: Text(Api.I.ar ? 'السابقة' : 'Previous'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_boolSetting('show_episode_list', true))
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: contextData['episodes'] is List ? _showEpisodes : null,
                                    icon: const Icon(Icons.format_list_numbered_rounded),
                                    label: Text(Api.I.ar ? 'الحلقات' : 'Episodes'),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: next == null ? null : _playNext,
                                  icon: const Icon(Icons.skip_next_rounded),
                                  label: Text(Api.I.ar ? 'التالية' : 'Next'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: autoplayNext,
                            onChanged: (v) => setState(() {
                              autoplayNext = v;
                              nextPromptDismissed = false;
                            }),
                            title: Text(
                              Api.I.ar
                                  ? 'تشغيل الحلقة التالية تلقائيًا'
                                  : 'Autoplay next episode',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              Api.I.ar
                                  ? 'انتقال تلقائي وسلس عند انتهاء الحلقة'
                                  : 'Seamless transition when the episode ends',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ),
                        ],
                        if (sources.length > 1) ...[
                          const SizedBox(height: 10),
                          Text(
                            Api.I.ar ? 'سيرفر التشغيل' : 'Playback server',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 42,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: sources.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final source = sources[i];
                                return ChoiceChip(
                                  selected: i == currentSource,
                                  label: Text(
                                    (source['label'] ?? 'Server ' + (i + 1).toString()).toString(),
                                  ),
                                  onSelected: (_) => _openSource(i),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

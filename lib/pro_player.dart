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

class _ProPlayerPageState extends State<ProPlayerPage> with RouteAware, WidgetsBindingObserver {
  late final Player player;
  late final VideoController controller;

  late String ownerType;
  late int ownerId;
  late String title;

  List<Map<String, dynamic>> sources = [];
  List<Map<String, dynamic>> subtitles = [];
  List<Map<String, dynamic>> recommendations = [];
  Map<String, dynamic> contextData = {};
  Map<String, dynamic> playerSettings = {};
  int currentSource = 0;
  int currentSubtitle = -1;
  double playbackRate = 1.0;
  final Set<int> failedSources = <int>{};
  final Set<int> refreshAttemptedSources = <int>{};
  bool fallbackBusy = false;
  bool refreshingSource = false;
  StreamSubscription<String>? playerErrorSub;
  PageRoute<dynamic>? _pageRoute;
  bool _resumeAfterCovered = false;
  bool _routeCovered = false;
  String? _offlinePlaybackPath;
  bool offlineAvailable = false;
  bool downloadingOffline = false;
  double offlineDownloadProgress = 0;

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

    WidgetsBinding.instance.addObserver(this);
    player = Player();
    AppPlaybackSession.claim(player);
    controller = VideoController(player);
    playerErrorSub = player.stream.error.listen((message) {
      if (!loading &&
          !transitioning &&
          !fallbackBusy &&
          !refreshingSource &&
          !_routeCovered &&
          AppPlaybackSession.owns(player)) {
        unawaited(_handlePlaybackFailure(message));
      }
    });
    _loadTarget(ownerType, ownerId, title);

    timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _pageRoute) {
      if (_pageRoute != null) appRouteObserver.unsubscribe(this);
      _pageRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeCovered = true;
    _resumeAfterCovered =
        AppPlaybackSession.owns(player) && player.state.playing;
    unawaited(player.pause());
  }

  @override
  void didPopNext() {
    _routeCovered = false;
    if (_resumeAfterCovered && mounted) {
      AppPlaybackSession.claim(player);
      unawaited(player.play());
    }
    _resumeAfterCovered = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(player.pause());
    }
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

  int _sourceId(Map<String,dynamic> source){
    final raw=source['id'];
    if(raw is num)return raw.toInt();
    return int.tryParse((raw??'').toString())??0;
  }

  String _normalizeQuality(String raw){
    final value=raw.trim();
    if(value.isEmpty)return '';
    final lower=value.toLowerCase();

    if(lower=='auto'||lower=='adaptive'||lower=='original'){
      return Api.I.ar?'تلقائي':'Auto';
    }
    if(lower.contains('4k')||lower.contains('uhd'))return '2160p';
    if(lower.contains('qhd'))return '1440p';
    if(lower.contains('fhd')||lower.contains('full hd'))return '1080p';

    final m=RegExp(
      r'(2160|1440|1080|900|720|576|540|480|360|240)\s*p?',
      caseSensitive:false,
    ).firstMatch(lower);
    if(m!=null)return '${m.group(1)}p';

    if(lower=='hd')return 'HD';
    if(lower=='sd')return 'SD';

    return value.length<=18?value:'';
  }

  String _sourceQuality(Map<String,dynamic> source){
    for(final key in const ['quality','resolution','height']){
      final value=(source[key]??'').toString().trim();
      final normalized=_normalizeQuality(value);
      if(normalized.isNotEmpty)return normalized;
    }

    final label=(source['label']??'').toString();
    final fromLabel=_normalizeQuality(label);
    if(fromLabel.isNotEmpty&&fromLabel!=label)return fromLabel;

    final url=Api.I.absoluteUrl(source['url']);
    final path=Uri.tryParse(url)?.path??url;
    final fromUrl=_normalizeQuality(path);
    if(fromUrl.isNotEmpty&&fromUrl!=path)return fromUrl;

    return '';
  }

  int _qualityRank(String quality){
    final q=quality.toLowerCase();
    if(q.contains('2160')||q.contains('4k'))return 2160;
    if(q.contains('1440'))return 1440;
    if(q.contains('1080')||q.contains('fhd'))return 1080;
    if(q.contains('900'))return 900;
    if(q.contains('720')||q=='hd')return 720;
    if(q.contains('576'))return 576;
    if(q.contains('540'))return 540;
    if(q.contains('480')||q=='sd')return 480;
    if(q.contains('360'))return 360;
    if(q.contains('240'))return 240;
    if(q.toLowerCase()==(Api.I.ar?'تلقائي':'auto').toLowerCase())return -1;
    return 0;
  }

  List<int> get _qualitySourceIndices{
    final byQuality=<String,int>{};
    for(var i=0;i<sources.length;i++){
      final quality=_sourceQuality(sources[i]);
      if(quality.isEmpty)continue;
      byQuality.putIfAbsent(quality,()=>i);
    }
    final entries=byQuality.entries.toList()
      ..sort((a,b)=>_qualityRank(b.key).compareTo(_qualityRank(a.key)));
    return entries.map((e)=>e.value).toList();
  }

  bool get _hasQualityOptions=>_qualitySourceIndices.isNotEmpty;

  String get _currentQualityLabel{
    if(currentSource<0||currentSource>=sources.length)return '';
    return _sourceQuality(sources[currentSource]);
  }

  Future<bool> _tryOfflineTarget(String type,int id,String fallbackTitle) async {
    final record=await OfflineDownloads.I.record(type,id);
    if(record==null)return false;

    await OfflineDownloads.I.releasePlayback(_offlinePlaybackPath);
    _offlinePlaybackPath=null;

    final path=await OfflineDownloads.I.preparePlayback(type,id);
    if(path==null||path.isEmpty)return false;
    if(!mounted){
      await OfflineDownloads.I.releasePlayback(path);
      return false;
    }

    _offlinePlaybackPath=path;
    ownerType=type;
    ownerId=id;
    title=record.title.isNotEmpty?record.title:fallbackTitle;
    sources=<Map<String,dynamic>>[
      <String,dynamic>{
        'id':-1,
        'label':Api.I.ar?'بدون إنترنت':'Offline',
        'source_type':'offline',
        'url':Uri.file(path).toString(),
      },
    ];
    subtitles=<Map<String,dynamic>>[];
    recommendations=<Map<String,dynamic>>[];
    currentSource=0;
    currentSubtitle=-1;
    failedSources.clear();
    refreshAttemptedSources.clear();
    contextData=<String,dynamic>{
      'media':<String,dynamic>{'title':title,'original_title':title},
      if(type=='episode')'current':<String,dynamic>{'title':title},
    };
    playerSettings=<String,dynamic>{
      'resume_enabled':true,
      'autoplay_next':false,
      'show_episode_list':false,
    };
    autoplayNext=false;
    offlineAvailable=true;

    final resumeAt=await Api.I.localResume(type,id);
    await _openSource(0,resumeAt:resumeAt);
    return true;
  }

  Future<void> _downloadCurrent() async {
    if(ownerType=='tv'||downloadingOffline)return;
    if(await OfflineDownloads.I.has(ownerType,ownerId)){
      if(mounted)setState(()=>offlineAvailable=true);
      return;
    }

    setState((){
      downloadingOffline=true;
      offlineDownloadProgress=0;
    });

    try{
      await OfflineDownloads.I.downloadOwner(
        ownerType,
        ownerId,
        title,
        onProgress:(value){
          if(mounted)setState(()=>offlineDownloadProgress=value);
        },
      );
      if(!mounted)return;
      setState((){
        offlineAvailable=true;
        offlineDownloadProgress=1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:Text(
            Api.I.ar
              ?'تم حفظ المحتوى مشفّرًا للمشاهدة بدون إنترنت.'
              :'Encrypted offline download completed.',
          ),
        ),
      );
    }catch(e){
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))),
      );
    }finally{
      if(mounted)setState(()=>downloadingOffline=false);
    }
  }

  Future<void> _loadTarget(String type, int id, String fallbackTitle) async {
    if (transitioning) return;

    AppPlaybackSession.claim(player);
    await player.stop();
    if (!mounted) return;

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
      await OfflineDownloads.I.releasePlayback(_offlinePlaybackPath);
      _offlinePlaybackPath=null;
      offlineAvailable=await OfflineDownloads.I.has(type,id);

      if(offlineAvailable){
        final loadedOffline=await _tryOfflineTarget(type,id,fallbackTitle);
        if(loadedOffline){
          if(mounted){
            setState((){
              loading=false;
              transitioning=false;
            });
          }
          return;
        }
      }

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
      recommendations = (data['recommendations'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      failedSources.clear();
      refreshAttemptedSources.clear();
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
    dynamic raw = source['headers'];
    raw ??= source['headers_json'];

    Map<dynamic, dynamic>? decoded;
    if (raw is Map) {
      decoded = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is Map) decoded = value;
      } catch (_) {}
    }
    if (decoded == null) return const <String, String>{};

    const allowed = <String>{
      'referer',
      'origin',
      'user-agent',
      'authorization',
      'cookie',
      'accept',
      'accept-language',
      'range',
    };

    final out = <String, String>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toString().trim();
      final value = entry.value?.toString().trim() ?? '';
      if (key.isEmpty || value.isEmpty) continue;
      if (!allowed.contains(key.toLowerCase())) continue;
      out[key] = value;
    }
    return out;
  }

  Future<void> _openSource(int index, {int? resumeAt}) async {
    if (index < 0 || index >= sources.length) return;
    if (!mounted || _routeCovered || !AppPlaybackSession.owns(player)) return;

    final oldPosition = player.state.position;
    final source = sources[index];
    final url = Api.I.absoluteUrl(source['url']);
    if (url.isEmpty) return;

    currentSource = index;
    error = null;
    final headers = _sourceHeaders(source);
    try {
      // Explicitly stop the current item before opening another one. This
      // avoids the previous movie/episode continuing underneath the new one.
      await player.stop();
      if (!mounted || _routeCovered || !AppPlaybackSession.owns(player)) return;

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
      await _handlePlaybackFailure(
        e.toString(),
        resumeAt: resumeAt ?? oldPosition.inSeconds,
      );
    }
  }

  Future<bool> _refreshCurrentSource({int? resumeAt, bool manual = false}) async {
    if (sources.isEmpty || currentSource < 0 || currentSource >= sources.length) {
      return false;
    }
    final source = sources[currentSource];
    final sourceId = (source['id'] as num?)?.toInt() ?? 0;
    if (!manual && sourceId > 0 && refreshAttemptedSources.contains(sourceId)) {
      return false;
    }
    if (sourceId > 0) refreshAttemptedSources.add(sourceId);

    final position = resumeAt ?? player.state.position.inSeconds;
    if (mounted) setState(() => refreshingSource = true);
    try {
      final result = await Api.I.call(
        'playback_refresh',
        method: 'POST',
        data: {
          'owner_type': ownerType,
          'owner_id': ownerId,
          'source_id': sourceId,
        },
      );
      final data = Map<String, dynamic>.from(result['data'] as Map);
      final fresh = (data['sources'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (fresh.isEmpty) return false;

      final oldId = sourceId;
      sources = fresh;
      var nextIndex = 0;
      if (oldId > 0) {
        final match = fresh.indexWhere(
          (row) => (row['id'] as num?)?.toInt() == oldId,
        );
        if (match >= 0) nextIndex = match;
      }
      currentSource = nextIndex;
      failedSources.remove(nextIndex);
      if (mounted) setState(() => refreshingSource = false);
      await _openSource(nextIndex, resumeAt: position);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => refreshingSource = false);
    }
  }

  Future<bool> _resolveCurrentSourceViaBridge({int? resumeAt}) async {
    if (sources.isEmpty || currentSource < 0 || currentSource >= sources.length) {
      return false;
    }
    if (_routeCovered || !AppPlaybackSession.owns(player)) return false;

    final source = sources[currentSource];
    final headers = _sourceHeaders(source);
    String? referer;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'referer') {
        referer = entry.value;
        break;
      }
    }

    final candidates = <dynamic>[
      source['source_url'],
      source['origin_url'],
      source['page_url'],
      source['referrer_url'],
      referer,
      source['url'],
    ];

    String origin = '';
    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isEmpty) continue;

      // Importers such as egy-ak-movie-importer may save a local
      // /embed4/?url=<origin> wrapper. The native app needs the real
      // source page so the resolver can generate a fresh signed URL.
      final absolute = Api.I.absoluteUrl(value);
      final uri = Uri.tryParse(absolute);
      if (uri != null && uri.path.contains('/embed4/')) {
        final wrapped = uri.queryParameters['url']?.trim() ?? '';
        if (wrapped.isNotEmpty) {
          origin = wrapped;
          break;
        }
      }

      origin = value;
      break;
    }
    if (origin.isEmpty) return false;

    final resolved = await Api.I.resolvePlaybackUrl(origin);
    if (resolved.isEmpty) return false;

    final currentUrl = Api.I.absoluteUrl(source['url']);
    final nextUrl = Api.I.absoluteUrl(resolved);
    if (nextUrl.isEmpty || nextUrl == currentUrl) return false;

    final updated = Map<String, dynamic>.from(source);
    updated['url'] = nextUrl;
    sources[currentSource] = updated;

    final position = resumeAt ?? player.state.position.inSeconds;
    await _openSource(currentSource, resumeAt: position);
    return true;
  }

  Future<void> _handlePlaybackFailure(String reason, {int? resumeAt}) async {
    if (fallbackBusy || refreshingSource) return;
    if (_routeCovered || !AppPlaybackSession.owns(player)) return;

    if(sources.isNotEmpty &&
       (sources[currentSource]['source_type']??'').toString()=='offline'){
      if(mounted){
        setState((){
          error=Api.I.ar
            ?'تعذر تشغيل النسخة المحفوظة. احذف التنزيل وحمّله من جديد.'
            :'The offline copy could not be played. Delete it and download again.';
        });
      }
      return;
    }

    final position = resumeAt ?? player.state.position.inSeconds;

    final refreshed = await _refreshCurrentSource(resumeAt: position);
    if (refreshed) return;

    final resolved = await _resolveCurrentSourceViaBridge(resumeAt: position);
    if (resolved) return;

    await _fallbackSource(reason, resumeAt: position);
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

  Future<void> _manualRefreshSource() async {
    final position = player.state.position.inSeconds;
    var ok = await _refreshCurrentSource(resumeAt: position, manual: true);
    if (!ok) {
      ok = await _resolveCurrentSourceViaBridge(resumeAt: position);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Api.I.ar
                ? 'تعذر تحديث الرابط من المصدر.'
                : 'Could not refresh the playback URL from source.',
          ),
        ),
      );
    }
  }

  Future<void> _selectSubtitle(int index) async {
    if (index < 0) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      if (mounted) setState(() => currentSubtitle = -1);
      return;
    }
    if (index >= subtitles.length) return;
    final track = subtitles[index];
    final url = Api.I.absoluteUrl(track['url']);
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

  Future<void> _leaveToTab(int index) async {
    try{await _saveProgress();}catch(_){}
    try{await player.pause();}catch(_){}
    if(!mounted)return;
    AppShellController.go(context,index);
  }

  Future<void> _leaveToKey(String key) async {
    await _leaveToTab(AppShellController.indexFor(key));
  }

  void _handleTopTool(String value){
    switch(value){
      case 'speed':
        _showSpeed();
        break;
      case 'subtitles':
        _showSubtitles();
        break;
      case 'sources':
        _showSources();
        break;
      case 'episodes':
        _showEpisodes();
        break;
      case 'refresh':
        unawaited(_manualRefreshSource());
        break;
    }
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
                      imageUrl: Api.I.absoluteUrl(ep['still']),
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
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    playerErrorSub?.cancel();
    AppPlaybackSession.release(player);
    unawaited(_saveProgress());
    unawaited(OfflineDownloads.I.releasePlayback(_offlinePlaybackPath));
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
            tooltip:Api.I.ar?'الرئيسية':'Home',
            onPressed:()=>unawaited(_leaveToKey('home')),
            icon:const Icon(Icons.home_outlined),
          ),
          if(Api.I.section('search'))
            IconButton(
              tooltip:Api.I.ar?'بحث':'Search',
              onPressed:()=>unawaited(_leaveToKey('search')),
              icon:const Icon(Icons.search_rounded),
            ),
          if(Api.I.section('account'))
            IconButton(
              tooltip:Api.I.ar?'حسابي':'Account',
              onPressed:()=>unawaited(_leaveToKey('account')),
              icon:const Icon(Icons.person_outline_rounded),
            ),
          PopupMenuButton<String>(
            tooltip:Api.I.ar?'أدوات المشاهدة':'Playback tools',
            onSelected:_handleTopTool,
            itemBuilder:(_)=>[
              PopupMenuItem(
                value:'speed',
                child:ListTile(
                  dense:true,
                  leading:const Icon(Icons.speed_rounded),
                  title:Text(Api.I.ar?'سرعة التشغيل':'Playback speed'),
                ),
              ),
              if(subtitles.isNotEmpty)
                PopupMenuItem(
                  value:'subtitles',
                  child:ListTile(
                    dense:true,
                    leading:const Icon(Icons.subtitles_rounded),
                    title:Text(Api.I.ar?'الترجمة':'Subtitles'),
                  ),
                ),
              if(sources.length>1)
                PopupMenuItem(
                  value:'sources',
                  child:ListTile(
                    dense:true,
                    leading:const Icon(Icons.dns_outlined),
                    title:Text(Api.I.ar?'السيرفرات':'Servers'),
                  ),
                ),
              if(ownerType=='episode'&&
                  _boolSetting('show_episode_list',true)&&
                  contextData['episodes'] is List)
                PopupMenuItem(
                  value:'episodes',
                  child:ListTile(
                    dense:true,
                    leading:const Icon(Icons.format_list_numbered_rounded),
                    title:Text(Api.I.ar?'الحلقات':'Episodes'),
                  ),
                ),
              PopupMenuItem(
                value:'refresh',
                enabled:!refreshingSource,
                child:ListTile(
                  dense:true,
                  leading:Icon(refreshingSource?Icons.sync_rounded:Icons.refresh_rounded),
                  title:Text(Api.I.ar?'تحديث المصدر':'Refresh source'),
                ),
              ),
            ],
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
                        controls: (state) => ProVideoControls(
                          state: state,
                          title: title,
                          subtitle: episodeMeta,
                          hasSources: sources.length > 1,
                          hasSubtitles: subtitles.isNotEmpty,
                          hasEpisodes: ownerType == 'episode' &&
                              contextData['episodes'] is List,
                          hasPrevious: previous != null,
                          hasNext: next != null,
                          refreshingSource: refreshingSource,
                          onSources: _showSources,
                          onSubtitles: _showSubtitles,
                          onSpeed: _showSpeed,
                          onEpisodes: _showEpisodes,
                          onPrevious: _playPrevious,
                          onNext: _playNext,
                          onRefreshSource: _manualRefreshSource,
                        ),
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
                                        imageUrl: Api.I.absoluteUrl(next['still']),
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
                        if(ownerType!='tv')...[
                          const SizedBox(height:12),
                          OutlinedButton.icon(
                            onPressed:offlineAvailable||downloadingOffline?null:_downloadCurrent,
                            icon:downloadingOffline
                              ?SizedBox(
                                  width:18,
                                  height:18,
                                  child:CircularProgressIndicator(
                                    strokeWidth:2,
                                    value:offlineDownloadProgress>0?offlineDownloadProgress:null,
                                  ),
                                )
                              :Icon(
                                  offlineAvailable
                                    ?Icons.download_done_rounded
                                    :Icons.download_for_offline_outlined,
                                ),
                            label:Text(
                              downloadingOffline
                                ?(Api.I.ar
                                    ?'جاري التحميل ${(offlineDownloadProgress*100).round()}%'
                                    :'Downloading ${(offlineDownloadProgress*100).round()}%')
                                :offlineAvailable
                                  ?(Api.I.ar?'محفوظ بدون إنترنت':'Available offline')
                                  :(Api.I.ar?'تحميل للمشاهدة بدون إنترنت':'Download for offline'),
                            ),
                          ),
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
                        if (recommendations.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            ownerType == 'tv'
                                ? (Api.I.ar ? 'قنوات مقترحة' : 'Recommended channels')
                                : (Api.I.ar ? 'مقترح لك' : 'Recommended for you'),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: ownerType == 'tv' ? 132 : 238,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: recommendations.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (_, i) {
                                final item = recommendations[i];
                                if (ownerType == 'tv') {
                                  return SizedBox(
                                    width: 205,
                                    child: Card(
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => _loadTarget(
                                          'tv',
                                          (item['id'] as num).toInt(),
                                          (item['name'] ?? '').toString(),
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            CachedNetworkImage(
                                              imageUrl: Api.I.absoluteUrl(item['backdrop'] ?? item['logo']),
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  Container(color: Colors.white10),
                                            ),
                                            const DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Color(0xE8000000),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            PositionedDirectional(
                                              start: 10,
                                              end: 10,
                                              bottom: 9,
                                              child: Text(
                                                (item['name'] ?? '').toString(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return MediaCard(
                                  item: item,
                                  onTap: () async {
                                    final id = (item['id'] as num?)?.toInt() ?? 0;
                                    if (id <= 0 || transitioning) return;
                                    final itemType = (item['type'] ?? '').toString();
                                    final itemTitle = (item['title'] ??
                                            item['original_title'] ??
                                            '')
                                        .toString();

                                    await _saveProgress();
                                    await player.pause();

                                    if (itemType == 'movie') {
                                      await _loadTarget('media', id, itemTitle);
                                      return;
                                    }

                                    if (!mounted) return;
                                    AppNavigator.open(
                                      context,
                                      ProDetailPage(id:id),
                                      key:'media/$id',
                                    );
                                  },
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
      bottomNavigationBar:ValueListenableBuilder<int>(
        valueListenable:AppShellController.tab,
        builder:(_,selected,__){
          final nav=AppShellController.items();
          final safe=selected.clamp(0,nav.length-1);
          return NavigationBar(
            selectedIndex:safe,
            onDestinationSelected:(index)=>unawaited(_leaveToTab(index)),
            destinations:nav.map((item)=>NavigationDestination(
              icon:Icon(item.icon),
              selectedIcon:Icon(item.selected),
              label:item.label,
            )).toList(),
          );
        },
      ),
    );
  }
}

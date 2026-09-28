part of 'main.dart';

class ProHomePage extends StatefulWidget {
  const ProHomePage({super.key});

  @override
  State<ProHomePage> createState() => _ProHomePageState();
}

class _ProHomePageState extends State<ProHomePage> {
  late Future<Map<String, dynamic>> _home;

  @override
  void initState() {
    super.initState();
    _home = Api.I.call('home');
  }

  Future<void> _refresh() async {
    await Api.I.loadConfig();
    final next = Api.I.call('home');
    setState(() => _home = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _home,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return ErrorPage(error: snapshot.error, retry: _refresh);
              }
              return const Center(child: CircularProgressIndicator());
            }

            final data = Map<String, dynamic>.from(snapshot.data!['data'] as Map);
            final sliders = data['sliders'] as List? ?? const [];
            final sections = data['sections'] as List? ?? const [];

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  floating: true,
                  titleSpacing: 16,
                  title: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                            Positioned(
                              left: 6,
                              right: 6,
                              top: 5,
                              child: Divider(color: Colors.white, thickness: 2, height: 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              appDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.45,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'مسلسلات قصيرة',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: Api.I.ar ? 'تغيير اللغة' : 'Language',
                      onPressed: () async {
                        Api.I.locale = Api.I.ar ? 'en' : 'ar';
                        await _refresh();
                      },
                      icon: const Icon(Icons.language_rounded),
                    ),
                  ],
                ),
                if (sliders.isNotEmpty)
                  SliverToBoxAdapter(child: _HeroCarousel(sliders: sliders)),
                const SliverToBoxAdapter(child: AppAd('app_home_top')),
                if (Api.I.section('continue_watching'))
                  const SliverToBoxAdapter(child: _ContinueRail()),
                ...sections.map(
                  (raw) => SliverToBoxAdapter(
                    child: MediaSection(data: Map<String, dynamic>.from(raw as Map)),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroCarousel extends StatefulWidget {
  final List sliders;
  const _HeroCarousel({required this.sliders});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _controller = PageController(viewportFraction: .96);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.sliders.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!_controller.hasClients) return;
        final next = (_index + 1) % widget.sliders.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 390,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.sliders.length,
            onPageChanged: (v) => setState(() => _index = v),
            itemBuilder: (_, i) {
              final s = Map<String, dynamic>.from(widget.sliders[i] as Map);
              final image = Api.I.absoluteUrl(s['mobile_image'] ?? s['image'] ?? s['backdrop'] ?? s['poster']);
              final title = (s['title'] ?? s['original_title'] ?? '').toString();
              final mediaId = int.tryParse((s['media_id'] ?? '').toString()) ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: mediaId <= 0
                      ? null
                      : () => AppNavigator.open(
                            context,
                            ProDetailPage(id: mediaId),
                            key: 'media/$mediaId',
                          ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: Colors.white10),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xE607080B)],
                              stops: [.35, 1],
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          start: 18,
                          end: 18,
                          bottom: 26,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  height: 1.02,
                                  letterSpacing: -.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if ((s['year'] ?? '').toString().isNotEmpty)
                                    _HeroMeta((s['year'] ?? '').toString()),
                                  if ((s['rating'] ?? '').toString().isNotEmpty)
                                    _HeroMeta('★ ' + (s['rating'] ?? '').toString()),
                                  if ((s['quality'] ?? '').toString().isNotEmpty)
                                    _HeroMeta((s['quality'] ?? '').toString()),
                                ],
                              ),
                              const SizedBox(height: 14),
                              if (mediaId > 0)
                                Row(
                                  children: [
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      ),
                                      onPressed: () => AppNavigator.open(
                                        context,
                                        ProDetailPage(id: mediaId),
                                        key: 'media/$mediaId',
                                      ),
                                      icon: const Icon(Icons.play_arrow_rounded),
                                      label: Text(
                                        Api.I.ar ? 'مشاهدة' : 'Watch',
                                        style: const TextStyle(fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    FilledButton.tonalIcon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xB31B1B1B),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => ProDetailPage(id: mediaId)),
                                      ),
                                      icon: const Icon(Icons.info_outline_rounded),
                                      label: Text(
                                        Api.I.ar ? 'التفاصيل' : 'Details',
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.sliders.length > 1)
            Positioned(
              bottom: 13,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.sliders.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinueRail extends StatefulWidget {
  const _ContinueRail();

  @override
  State<_ContinueRail> createState() => _ContinueRailState();
}

class _ContinueRailState extends State<_ContinueRail> {
  Future<List<Map<String, dynamic>>> _load() async {
    if (!await Api.I.hasToken()) return const [];
    try {
      final result = await Api.I.call('continue');
      final rows = result['data'] as List? ?? const [];
      return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(),
      builder: (_, snapshot) {
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_outline_rounded, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      Api.I.ar ? 'متابعة المشاهدة' : 'Continue watching',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final row = rows[i];
                    final media = Map<String, dynamic>.from(row['media'] as Map);
                    final history = Map<String, dynamic>.from(row['history'] as Map);
                    final episode = row['episode'];
                    final p = (history['progress_seconds'] as num? ?? 0).toDouble();
                    final d = (history['duration_seconds'] as num? ?? 0).toDouble();
                    final ratio = d > 0 ? (p / d).clamp(0.0, 1.0) : 0.0;
                    final ownerType = episode is Map ? 'episode' : 'media';
                    final ownerId = episode is Map
                        ? (episode['id'] as num).toInt()
                        : (media['id'] as num).toInt();
                    final image = Api.I.absoluteUrl(
                      episode is Map
                          ? (episode['still'] ?? media['backdrop'] ?? media['poster'])
                          : (media['backdrop'] ?? media['poster']),
                    );
                    final subtitle = episode is Map
                        ? (Api.I.ar ? 'الموسم ' : 'S') + episode['season_number'].toString() +
                            ' • ' + (Api.I.ar ? 'الحلقة ' : 'E') + episode['episode_number'].toString()
                        : (media['year'] ?? '').toString();

                    return SizedBox(
                      width: 230,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => AppNavigator.open(
                          context,
                          ProPlayerPage(
                            ownerType: ownerType,
                            ownerId: ownerId,
                            title: (media['title'] ?? media['original_title'] ?? '').toString(),
                          ),
                          key: 'player/$ownerType/$ownerId',
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: image,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(color: Colors.white10),
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Color(0xE9000000)],
                                  ),
                                ),
                              ),
                              PositionedDirectional(
                                start: 12,
                                end: 12,
                                bottom: 14,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (media['title'] ?? media['original_title'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                    const SizedBox(height: 7),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(99),
                                      child: LinearProgressIndicator(
                                        value: ratio,
                                        minHeight: 4,
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PositionedDirectional(
                                end: 10,
                                top: 10,
                                child: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: Color(0xCC000000),
                                  child: Icon(Icons.play_arrow_rounded, size: 22),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _HeroMeta extends StatelessWidget {
  final String text;
  const _HeroMeta(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

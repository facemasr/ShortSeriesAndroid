part of 'main.dart';

class ProDetailPage extends StatefulWidget {
  final int id;
  const ProDetailPage({super.key, required this.id});

  @override
  State<ProDetailPage> createState() => _ProDetailPageState();
}

class _ProDetailPageState extends State<ProDetailPage> {
  late Future<Map<String, dynamic>> _future;
  bool _busyAction = false;
  bool _busyDownload = false;
  double _downloadProgress = 0;
  int _downloadDone = 0;
  int _downloadTotal = 0;

  @override
  void initState() {
    super.initState();
    _future = Api.I.call('media_detail', query: {'id': widget.id});
  }

  Future<void> _reload() async {
    final next = Api.I.call('media_detail', query: {'id': widget.id},forceRefresh:true);
    setState(() => _future = next);
    await next;
  }

  Future<void> _toggle(String action) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      await Api.I.call(
        action,
        method: 'POST',
        data: {'media_id': widget.id},
      );
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Api.I.ar ? 'سجّل الدخول أولًا' : 'Sign in first')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _downloadOne(String type,int id,String title) async {
    if(_busyDownload)return;
    setState((){
      _busyDownload=true;
      _downloadProgress=0;
      _downloadDone=0;
      _downloadTotal=1;
    });
    try{
      await OfflineDownloads.I.downloadOwner(
        type,
        id,
        title,
        onProgress:(value){
          if(mounted)setState(()=>_downloadProgress=value);
        },
      );
      if(!mounted)return;
      setState((){
        _downloadDone=1;
        _downloadProgress=1;
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
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))),
        );
      }
    }finally{
      if(mounted)setState(()=>_busyDownload=false);
    }
  }

  Future<void> _downloadEpisodes(List episodes,String mediaTitle) async {
    if(_busyDownload)return;
    final rows=episodes.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(rows.isEmpty)return;

    setState((){
      _busyDownload=true;
      _downloadDone=0;
      _downloadTotal=rows.length;
      _downloadProgress=0;
    });

    var done=0;
    try{
      for(final ep in rows){
        final id=(ep['id'] as num?)?.toInt()??0;
        if(id<=0)continue;
        final epTitle=(ep['title']??'').toString().trim();
        final episodeLabel=epTitle.isNotEmpty
          ?epTitle
          :'${Api.I.ar?'حلقة':'Episode'} ${ep['episode_number']??''}';
        final label='$mediaTitle • $episodeLabel';
        try{
          await OfflineDownloads.I.downloadOwner(
            'episode',
            id,
            label,
            groupTitle:mediaTitle,
            onProgress:(value){
              if(!mounted)return;
              final total=rows.length;
              setState((){
                _downloadProgress=(done+value)/total;
              });
            },
          );
        }catch(_){}
        done++;
        if(mounted){
          setState((){
            _downloadDone=done;
            _downloadProgress=done/rows.length;
          });
        }
      }
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:Text(
              Api.I.ar
                ?'اكتمل تنزيل $done من ${rows.length} حلقة.'
                :'Downloaded $done of ${rows.length} episodes.',
            ),
          ),
        );
      }
    }finally{
      if(mounted)setState(()=>_busyDownload=false);
    }
  }

  Future<void> _downloadSeries(List seasons,String mediaTitle) async {
    final episodes=<Map<String,dynamic>>[];
    for(final rawSeason in seasons){
      if(rawSeason is! Map)continue;
      final season=Map<String,dynamic>.from(rawSeason);
      for(final rawEp in season['episodes'] as List? ?? const[]){
        if(rawEp is Map)episodes.add(Map<String,dynamic>.from(rawEp));
      }
    }
    await _downloadEpisodes(episodes,mediaTitle);
  }

  Future<void> _playBest(Map<String, dynamic> item, List seasons) async {
    if (item['type'] == 'movie') {
      if (!mounted) return;
      AppNavigator.open(
        context,
        ProPlayerPage(
          ownerType: 'media',
          ownerId: widget.id,
          title: (item['title'] ?? item['original_title'] ?? '').toString(),
        ),
        key: 'player/media/${widget.id}',
      );
      return;
    }

    if (await Api.I.hasToken()) {
      try {
        final result = await Api.I.call('continue');
        final rows = result['data'] as List? ?? const [];
        for (final raw in rows) {
          final row = Map<String, dynamic>.from(raw as Map);
          final media = Map<String, dynamic>.from(row['media'] as Map);
          final episode = row['episode'];
          if ((media['id'] as num?)?.toInt() == widget.id && episode is Map) {
            if (!mounted) return;
            final episodeId = (episode['id'] as num).toInt();
            AppNavigator.open(
              context,
              ProPlayerPage(
                ownerType: 'episode',
                ownerId: episodeId,
                title: (media['title'] ?? media['original_title'] ?? '').toString(),
              ),
              key: 'player/episode/$episodeId',
            );
            return;
          }
        }
      } catch (_) {}
    }

    if (seasons.isEmpty) {
      if (!mounted) return;
      AppNavigator.open(
        context,
        ProPlayerPage(
          ownerType:'media',
          ownerId:widget.id,
          title:(item['title']??item['original_title']??'').toString(),
        ),
        key:'player/media/${widget.id}',
      );
      return;
    }
    final firstSeason = Map<String, dynamic>.from(seasons.first as Map);
    final episodes = firstSeason['episodes'] as List? ?? const [];
    if (episodes.isEmpty) {
      if (!mounted) return;
      AppNavigator.open(
        context,
        ProPlayerPage(
          ownerType:'media',
          ownerId:widget.id,
          title:(item['title']??item['original_title']??'').toString(),
        ),
        key:'player/media/${widget.id}',
      );
      return;
    }
    final ep = Map<String, dynamic>.from(episodes.first as Map);
    if (!mounted) return;
    final epId = (ep['id'] as num).toInt();
    AppNavigator.open(
      context,
      ProPlayerPage(
        ownerType: 'episode',
        ownerId: epId,
        title: (item['title'] ?? item['original_title'] ?? '').toString(),
      ),
      key: 'player/episode/$epId',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return ErrorPage(error: snapshot.error, retry: _reload);
            }
            return const Center(child: CircularProgressIndicator());
          }

          final item = Map<String, dynamic>.from(snapshot.data!['data'] as Map);
          final seasons = item['seasons'] as List? ?? const [];
          final cast = item['cast'] as List? ?? const [];
          final related = item['related'] as List? ?? const [];
          final title = (item['title'] ?? item['original_title'] ?? '').toString();
          final backdrop = Api.I.absoluteUrl(item['backdrop'] ?? item['poster']);
          final overview = (item['overview'] ?? item['story'] ?? '').toString();
          final favorite = item['in_favorites'] == true;
          final watchlist = item['in_watchlist'] == true;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 410,
                backgroundColor: const Color(0xFF08090C),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: backdrop,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: Colors.white10),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x22000000), Color(0xFF08090C)],
                            stops: [.35, 1],
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: 18,
                        end: 18,
                        bottom: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                height: 1.02,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if ((item['year'] ?? '').toString().isNotEmpty)
                                  _MetaChip(label: (item['year'] ?? '').toString()),
                                _MetaChip(label: '★ ' + (item['rating'] ?? 0).toString()),
                                if ((item['quality'] ?? '').toString().isNotEmpty)
                                  _MetaChip(label: (item['quality'] ?? '').toString()),
                                if ((item['views'] ?? '').toString().isNotEmpty)
                                  _MetaChip(
                                    label: (item['views'] ?? 0).toString() + ' ' + (Api.I.ar ? 'مشاهدة' : 'views'),
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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () => _playBest(item, seasons),
                            icon: const Icon(Icons.play_arrow_rounded, size: 28),
                            label: Text(
                              Api.I.ar ? 'تشغيل / استكمال' : 'Play / Resume',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busyAction ? null : () => _toggle('favorite_toggle'),
                            icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                            label: Text(Api.I.ar ? 'المفضلة' : 'Favorite'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busyAction ? null : () => _toggle('watchlist_toggle'),
                      icon: Icon(watchlist ? Icons.bookmark : Icons.bookmark_border),
                      label: Text(
                        watchlist
                            ? (Api.I.ar ? 'مضاف إلى قائمتي' : 'In My List')
                            : (Api.I.ar ? 'إضافة إلى قائمتي' : 'Add to My List'),
                      ),
                    ),
                    const SizedBox(height:10),
                    FilledButton.tonalIcon(
                      onPressed:_busyDownload
                        ?null
                        :(){
                            if(item['type']=='movie'){
                              _downloadOne('media',widget.id,title);
                            }else{
                              _downloadSeries(seasons,title);
                            }
                          },
                      icon:_busyDownload
                        ?SizedBox(
                            width:18,
                            height:18,
                            child:CircularProgressIndicator(
                              strokeWidth:2,
                              value:_downloadProgress>0?_downloadProgress:null,
                            ),
                          )
                        :const Icon(Icons.download_for_offline_rounded),
                      label:Text(
                        _busyDownload
                          ?(Api.I.ar
                              ?'جاري التحميل ${(_downloadProgress*100).round()}% ($_downloadDone/$_downloadTotal)'
                              :'Downloading ${(_downloadProgress*100).round()}% ($_downloadDone/$_downloadTotal)')
                          :item['type']=='movie'
                            ?(Api.I.ar?'تحميل الفيلم':'Download movie')
                            :(Api.I.ar?'تحميل المسلسل':'Download series'),
                      ),
                    ),
                    const AppAd('app_details'),
                    const AdMobNativeCard(placement:'details'),
                    if (overview.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        overview,
                        style: const TextStyle(height: 1.6, fontSize: 15.5, color: Colors.white70),
                      ),
                    ],
                    if (cast.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        Api.I.ar ? 'طاقم العمل' : 'Cast',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 154,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: cast.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final person = Map<String, dynamic>.from(cast[i] as Map);
                            final personId = (person['id'] as num?)?.toInt() ?? 0;
                            return SizedBox(
                              width: 94,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: personId > 0
                                    ? () => AppNavigator.open(
                                          context,
                                          PersonPage(id: personId),
                                          key: 'person/$personId',
                                        )
                                    : null,
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: CachedNetworkImage(
                                        imageUrl: Api.I.absoluteUrl(person['photo']),
                                        width: 94,
                                        height: 106,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Container(
                                          width: 94,
                                          height: 106,
                                          color: Colors.white10,
                                          child: const Icon(Icons.person_outline_rounded, size: 40),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      (person['name'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                    ),
                                    Text(
                                      (person['character_name'] ?? person['job'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (seasons.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        Api.I.ar ? 'الحلقات' : 'Episodes',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      ...seasons.map((raw) {
                        final season = Map<String, dynamic>.from(raw as Map);
                        final episodes = season['episodes'] as List? ?? const [];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            initiallyExpanded: seasons.length == 1,
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text(
                              (Api.I.ar ? 'الموسم ' : 'Season ') + season['season_number'].toString(),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(
                              episodes.length.toString() + ' ' + (Api.I.ar ? 'حلقة' : 'episodes'),
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing:IconButton(
                              tooltip:Api.I.ar?'تحميل الموسم':'Download season',
                              onPressed:_busyDownload?null:()=>_downloadEpisodes(episodes,title),
                              icon:const Icon(Icons.download_for_offline_outlined),
                            ),
                            children: episodes.map((rawEp) {
                              final ep = Map<String, dynamic>.from(rawEp as Map);
                              return _EpisodeTile(
                                episode: ep,
                                onTap: () {
                                  final epId = (ep['id'] as num).toInt();
                                  AppNavigator.open(
                                    context,
                                    ProPlayerPage(
                                      ownerType: 'episode',
                                      ownerId: epId,
                                      title: title,
                                    ),
                                    key: 'player/episode/$epId',
                                  );
                                },
                                onDownload:_busyDownload
                                  ?null
                                  :(){
                                      final epId=(ep['id'] as num).toInt();
                                      final epTitle=(ep['title']??'').toString().trim();
                                      _downloadOne(
                                        'episode',
                                        epId,
                                        epTitle.isNotEmpty?epTitle:title,
                                      );
                                    },
                              );
                            }).toList(),
                          ),
                        );
                      }),
                    ],
                    if (related.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      Text(
                        Api.I.ar ? 'مقترح لك' : 'Recommended for you',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 250,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: related.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => MediaCard(
                            item: Map<String, dynamic>.from(related[i] as Map),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Map<String, dynamic> episode;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  const _EpisodeTile({
    required this.episode,
    required this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final still = (episode['still'] ?? '').toString();
    final duration = (episode['duration'] ?? 0).toString();
    final views = (episode['views'] ?? 0).toString();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      leading: SizedBox(
        width: 96,
        height: 58,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: still,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Colors.white10,
                  child: const Icon(Icons.movie_outlined),
                ),
              ),
              const Center(
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xCC000000),
                  child: Icon(Icons.play_arrow_rounded, size: 21),
                ),
              ),
            ],
          ),
        ),
      ),
      title: Text(
        episode['episode_number'].toString() + '. ' + (episode['title'] ?? '').toString(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        duration + ' ' + (Api.I.ar ? 'دقيقة' : 'min') + ' • ' +
            views + ' ' + (Api.I.ar ? 'مشاهدة' : 'views'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing:Row(
        mainAxisSize:MainAxisSize.min,
        children:[
          IconButton(
            tooltip:Api.I.ar?'تحميل الحلقة':'Download episode',
            onPressed:onDownload,
            icon:const Icon(Icons.download_for_offline_outlined),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: onTap,
    );
  }
}
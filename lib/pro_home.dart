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
    _home = Api.I.call('home',forceRefresh:true);
  }

  Future<void> _refresh() async {
    await Api.I.loadConfig(forceRefresh:true);
    final next = Api.I.call('home',forceRefresh:true);
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

            final data=Api.I.mapFrom(snapshot.data!['data']);
            final sliders=Api.I.rowsFrom(
              data['sliders']??data['slides']??data['hero']??const [],
              keys:const ['sliders','slides','hero','items','rows','data'],
            );
            final sections=Api.I.rowsFrom(
              data['sections']??const [],
              keys:const ['sections','items','rows','data'],
            );

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

class _HeroCarouselState extends State<_HeroCarousel> with WidgetsBindingObserver {
  late final PageController _controller;
  Timer? _timer;
  int _index=0;
  bool _interacting=false;

  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller=PageController(viewportFraction:.94);
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)_scheduleAuto();
    });
  }

  @override
  void didUpdateWidget(covariant _HeroCarousel oldWidget){
    super.didUpdateWidget(oldWidget);
    if(widget.sliders.length!=oldWidget.sliders.length){
      if(widget.sliders.isEmpty){
        _index=0;
      }else if(_index>=widget.sliders.length){
        _index=0;
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(mounted&&_controller.hasClients)_controller.jumpToPage(0);
        });
      }
      _scheduleAuto();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed){
      _scheduleAuto();
    }else{
      _timer?.cancel();
    }
  }

  void _scheduleAuto(){
    _timer?.cancel();
    if(widget.sliders.length<=1||_interacting)return;
    _timer=Timer(const Duration(seconds:5),() async{
      if(!mounted||_interacting||!_controller.hasClients)return;
      final next=(_index+1)%widget.sliders.length;
      final reduce=WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures.disableAnimations;
      if(reduce){
        _controller.jumpToPage(next);
      }else{
        await _controller.animateToPage(
          next,
          duration:const Duration(milliseconds:520),
          curve:Curves.easeInOutCubic,
        );
      }
      if(mounted&&!_interacting)_scheduleAuto();
    });
  }

  void _pauseAuto(){
    _interacting=true;
    _timer?.cancel();
  }

  void _resumeAuto(){
    _interacting=false;
    _scheduleAuto();
  }

  Future<void> _goTo(int index) async{
    if(index<0||index>=widget.sliders.length||!_controller.hasClients)return;
    _pauseAuto();
    await _controller.animateToPage(
      index,
      duration:const Duration(milliseconds:360),
      curve:Curves.easeOutCubic,
    );
    if(mounted)_resumeAuto();
  }

  Map<String,dynamic> _slide(int index){
    final raw=widget.sliders[index];
    return raw is Map?Map<String,dynamic>.from(raw):<String,dynamic>{};
  }

  Map<String,dynamic> _media(Map<String,dynamic> slide){
    return Api.I.mapFrom(slide['media']);
  }

  String _title(Map<String,dynamic> slide){
    final media=_media(slide);
    return Api.I.localizedValue(
      slide['title']??
      slide['title_json']??
      media['title']??
      media['original_title'],
    ).trim();
  }

  String _image(Map<String,dynamic> slide){
    final media=_media(slide);
    final value=
      slide['mobile_image']??
      slide['image']??
      slide['backdrop']??
      media['backdrop']??
      slide['poster']??
      media['poster'];
    return Api.I.absoluteUrl(value);
  }

  int _mediaId(Map<String,dynamic> slide){
    final media=_media(slide);
    return int.tryParse(
      (slide['media_id']??media['id']??slide['id']??'').toString(),
    )??0;
  }

  String _meta(Map<String,dynamic> slide,String key){
    final media=_media(slide);
    return (slide[key]??media[key]??'').toString().trim();
  }

  @override
  void dispose(){
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    final size=MediaQuery.sizeOf(context);
    final compact=size.width<430;
    final heroHeight=(size.width*(compact?.78:.56))
      .clamp(compact?292.0:320.0,compact?370.0:420.0)
      .toDouble();

    if(widget.sliders.isEmpty)return const SizedBox.shrink();

    return SizedBox(
      height:heroHeight,
      child:Stack(
        alignment:Alignment.center,
        children:[
          NotificationListener<ScrollNotification>(
            onNotification:(notification){
              if(notification is ScrollStartNotification)_pauseAuto();
              if(notification is ScrollEndNotification)_resumeAuto();
              return false;
            },
            child:PageView.builder(
              controller:_controller,
              physics:const BouncingScrollPhysics(parent:PageScrollPhysics()),
              itemCount:widget.sliders.length,
              onPageChanged:(value){
                if(!mounted)return;
                setState(()=>_index=value);
                if(!_interacting)_scheduleAuto();
              },
              itemBuilder:(_,i){
                final slide=_slide(i);
                final image=_image(slide);
                final title=_title(slide);
                final mediaId=_mediaId(slide);
                final year=_meta(slide,'year');
                final rating=_meta(slide,'rating');
                final quality=_meta(slide,'quality');

                void openDetails(){
                  if(mediaId<=0)return;
                  AppNavigator.open(
                    context,
                    ProDetailPage(id:mediaId),
                    key:'media/'+mediaId.toString(),
                  );
                }

                return AnimatedPadding(
                  duration:const Duration(milliseconds:220),
                  padding:EdgeInsets.fromLTRB(
                    i==_index?8:12,
                    7,
                    i==_index?8:12,
                    12,
                  ),
                  child:Material(
                    color:const Color(0xFF111214),
                    borderRadius:BorderRadius.circular(compact?20:24),
                    clipBehavior:Clip.antiAlias,
                    child:InkWell(
                      onTap:mediaId>0?openDetails:null,
                      child:Stack(
                        fit:StackFit.expand,
                        children:[
                          if(image.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl:image,
                              fit:BoxFit.cover,
                              alignment:Alignment.topCenter,
                              placeholder:(_,__)=>Container(color:const Color(0xFF15161A)),
                              errorWidget:(_,__,___)=>Container(
                                color:const Color(0xFF15161A),
                                child:const Icon(Icons.movie_outlined,size:52,color:Colors.white24),
                              ),
                            )
                          else
                            Container(
                              color:const Color(0xFF15161A),
                              child:const Icon(Icons.movie_outlined,size:52,color:Colors.white24),
                            ),
                          const DecoratedBox(
                            decoration:BoxDecoration(
                              gradient:LinearGradient(
                                begin:Alignment.topCenter,
                                end:Alignment.bottomCenter,
                                colors:[
                                  Color(0x08000000),
                                  Color(0x30000000),
                                  Color(0xF307080B),
                                ],
                                stops:[0,.50,1],
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            start:compact?17:24,
                            end:compact?17:24,
                            bottom:compact?35:40,
                            child:Column(
                              crossAxisAlignment:CrossAxisAlignment.start,
                              mainAxisSize:MainAxisSize.min,
                              children:[
                                Text(
                                  title.isEmpty?(Api.I.ar?'SHORT SERIES':'Featured') : title,
                                  maxLines:2,
                                  overflow:TextOverflow.ellipsis,
                                  style:TextStyle(
                                    fontSize:compact?23:30,
                                    fontWeight:FontWeight.w900,
                                    height:1.04,
                                  ),
                                ),
                                const SizedBox(height:8),
                                Wrap(
                                  spacing:7,
                                  runSpacing:5,
                                  children:[
                                    if(year.isNotEmpty)_HeroMeta(year),
                                    if(rating.isNotEmpty&&rating!='0')_HeroMeta('★ '+rating),
                                    if(quality.isNotEmpty)_HeroMeta(quality),
                                  ],
                                ),
                                if(mediaId>0)...[
                                  const SizedBox(height:12),
                                  FilledButton.icon(
                                    style:FilledButton.styleFrom(
                                      backgroundColor:Colors.white,
                                      foregroundColor:Colors.black,
                                      padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
                                    ),
                                    onPressed:openDetails,
                                    icon:const Icon(Icons.play_arrow_rounded),
                                    label:Text(
                                      Api.I.ar?'مشاهدة الآن':'Watch now',
                                      style:const TextStyle(fontWeight:FontWeight.w900),
                                    ),
                                  ),
                                ],
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
          ),
          if(widget.sliders.length>1)...[
            PositionedDirectional(
              start:4,
              child:_HeroArrow(
                icon:Api.I.ar?Icons.chevron_right_rounded:Icons.chevron_left_rounded,
                onTap:()=>_goTo((_index-1+widget.sliders.length)%widget.sliders.length),
              ),
            ),
            PositionedDirectional(
              end:4,
              child:_HeroArrow(
                icon:Api.I.ar?Icons.chevron_left_rounded:Icons.chevron_right_rounded,
                onTap:()=>_goTo((_index+1)%widget.sliders.length),
              ),
            ),
            Positioned(
              bottom:15,
              left:0,
              right:0,
              child:Center(
                child:Row(
                  mainAxisSize:MainAxisSize.min,
                  children:List.generate(
                    widget.sliders.length,
                    (i)=>InkWell(
                      borderRadius:BorderRadius.circular(99),
                      onTap:()=>_goTo(i),
                      child:AnimatedContainer(
                        duration:const Duration(milliseconds:220),
                        margin:const EdgeInsets.symmetric(horizontal:3,vertical:6),
                        width:i==_index?24:7,
                        height:7,
                        decoration:BoxDecoration(
                          color:i==_index?Colors.white:Colors.white38,
                          borderRadius:BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroArrow extends StatelessWidget{
  final IconData icon;
  final VoidCallback onTap;
  const _HeroArrow({required this.icon,required this.onTap});

  @override
  Widget build(BuildContext context){
    return Material(
      color:const Color(0x99000000),
      shape:const CircleBorder(),
      child:InkWell(
        customBorder:const CircleBorder(),
        onTap:onTap,
        child:SizedBox(
          width:38,
          height:38,
          child:Icon(icon,color:Colors.white,size:28),
        ),
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

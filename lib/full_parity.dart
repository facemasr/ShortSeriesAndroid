part of 'main.dart';

class ProBrowsePage extends StatefulWidget {
  const ProBrowsePage({super.key});
  @override
  State<ProBrowsePage> createState() => _ProBrowsePageState();
}

class _ProBrowsePageState extends State<ProBrowsePage>
    with SingleTickerProviderStateMixin {
  late final TabController controller;
  @override
  void initState() {
    super.initState();
    controller = TabController(length: 4, vsync: this);
  }
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final a=Api.I;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12,10,12,4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    a.ar ? 'اكتشف' : 'Discover',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: ()=>Navigator.push(
                    context,
                    MaterialPageRoute(builder:(_)=>const GenrePage()),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: a.ar ? 'التصنيفات' : 'Genres',
                ),
              ],
            ),
          ),
          TabBar(
            controller: controller,
            isScrollable: true,
            tabs: [
              Tab(text:a.ar?'أفلام':'Movies'),
              Tab(text:a.ar?'مسلسلات':'Series'),
              Tab(text:a.ar?'قصيرة':'Shorts'),
              Tab(text:a.ar?'فنانون':'Artists'),
            ],
          ),
          const SizedBox(height:4),
          Expanded(
            child: TabBarView(
              controller: controller,
              children: const [
                ProPagedMediaGrid(type:'movie'),
                ProPagedMediaGrid(type:'series'),
                ProPagedMediaGrid(type:'short_series'),
                PeopleGridPage(embedded:true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProPagedMediaGrid extends StatefulWidget {
  final String type;
  final String query;
  const ProPagedMediaGrid({super.key,required this.type,this.query=''});
  @override
  State<ProPagedMediaGrid> createState()=>_ProPagedMediaGridState();
}

class _ProPagedMediaGridState extends State<ProPagedMediaGrid> {
  final scroll=ScrollController();
  final rows=<Map<String,dynamic>>[];
  bool loading=false;
  bool done=false;
  int page=1;
  @override
  void initState(){
    super.initState();
    scroll.addListener((){
      if(scroll.position.pixels>scroll.position.maxScrollExtent-500) _load();
    });
    _load(reset:true);
  }
  @override
  void didUpdateWidget(covariant ProPagedMediaGrid oldWidget){
    super.didUpdateWidget(oldWidget);
    if(oldWidget.type!=widget.type||oldWidget.query!=widget.query) _load(reset:true);
  }
  Future<void> _load({bool reset=false}) async {
    if(loading) return;
    if(reset){
      rows.clear(); page=1; done=false;
      if(mounted)setState((){});
    }
    if(done)return;
    setState(()=>loading=true);
    try{
      final res=await Api.I.call('media',query:{
        'type':widget.type,'q':widget.query,'page':page,'limit':30,
      });
      final list=(res['data'] as List? ?? const [])
          .map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      rows.addAll(list);
      final meta=res['meta'];
      final total=meta is Map ? (meta['total'] as num? ?? rows.length).toInt() : rows.length;
      done=rows.length>=total||list.isEmpty;
      page++;
    }catch(_){}
    if(mounted)setState(()=>loading=false);
  }
  @override
  void dispose(){scroll.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    if(rows.isEmpty&&loading)return const Center(child:CircularProgressIndicator());
    if(rows.isEmpty)return Center(child:Text(Api.I.ar?'لا يوجد محتوى':'No content'));
    return RefreshIndicator(
      onRefresh:()=>_load(reset:true),
      child:GridView.builder(
        controller:scroll,
        padding:const EdgeInsets.all(12),
        gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent:190,childAspectRatio:.57,crossAxisSpacing:12,mainAxisSpacing:14,
        ),
        itemCount:rows.length+(loading?1:0),
        itemBuilder:(_,i){
          if(i>=rows.length)return const Center(child:CircularProgressIndicator());
          return MediaCard(item:rows[i]);
        },
      ),
    );
  }
}

class GenrePage extends StatefulWidget{
  const GenrePage({super.key});
  @override
  State<GenrePage> createState()=>_GenrePageState();
}
class _GenrePageState extends State<GenrePage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('genres');}
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(title:Text(Api.I.ar?'التصنيفات':'Genres')),
      body:FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(_,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final rows=s.data!['data'] as List? ?? const[];
          return ListView.separated(
            padding:const EdgeInsets.all(12),
            itemCount:rows.length,
            separatorBuilder:(_,__)=>const Divider(height:1),
            itemBuilder:(_,i){
              final g=Map<String,dynamic>.from(rows[i] as Map);
              return ListTile(
                leading:const CircleAvatar(child:Icon(Icons.local_movies_outlined)),
                title:Text((g['name']??'').toString()),
                trailing:Text((g['media_count']??0).toString()),
              );
            },
          );
        },
      ),
    );
  }
}

class PeopleGridPage extends StatefulWidget{
  final bool embedded;
  const PeopleGridPage({super.key,this.embedded=false});
  @override
  State<PeopleGridPage> createState()=>_PeopleGridPageState();
}
class _PeopleGridPageState extends State<PeopleGridPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('people',query:{'limit':50});}
  @override
  Widget build(BuildContext context){
    final body=FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(_,s){
        if(!s.hasData)return const Center(child:CircularProgressIndicator());
        final rows=s.data!['data'] as List? ?? const[];
        return GridView.builder(
          padding:const EdgeInsets.all(12),
          gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent:180,childAspectRatio:.72,crossAxisSpacing:12,mainAxisSpacing:14,
          ),
          itemCount:rows.length,
          itemBuilder:(_,i){
            final p=Map<String,dynamic>.from(rows[i] as Map);
            return InkWell(
              borderRadius:BorderRadius.circular(16),
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PersonPage(id:(p['id'] as num).toInt()))),
              child:Column(
                children:[
                  Expanded(
                    child:ClipRRect(
                      borderRadius:BorderRadius.circular(16),
                      child:CachedNetworkImage(
                        imageUrl:(p['photo']??'').toString(),
                        width:double.infinity,fit:BoxFit.cover,
                        errorWidget:(_,__,___)=>Container(color:Colors.white10,child:const Icon(Icons.person,size:52)),
                      ),
                    ),
                  ),
                  const SizedBox(height:7),
                  Text((p['name']??'').toString(),maxLines:1,overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontWeight:FontWeight.w800)),
                  Text((p['known_for']??'').toString(),maxLines:1,overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontSize:11,color:Colors.white54)),
                ],
              ),
            );
          },
        );
      },
    );
    if(widget.embedded)return body;
    return Scaffold(appBar:AppBar(title:Text(Api.I.ar?'الفنانون':'Artists')),body:body);
  }
}

class PersonPage extends StatefulWidget{
  final int id;
  const PersonPage({super.key,required this.id});
  @override
  State<PersonPage> createState()=>_PersonPageState();
}
class _PersonPageState extends State<PersonPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('person',query:{'id':widget.id});}
  @override
  Widget build(BuildContext context){
    return Scaffold(
      body:FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(_,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final root=Map<String,dynamic>.from(s.data!['data'] as Map);
          final p=Map<String,dynamic>.from(root['person'] as Map);
          final works=root['works'] as List? ?? const[];
          return CustomScrollView(
            slivers:[
              SliverAppBar(
                pinned:true,expandedHeight:320,
                flexibleSpace:FlexibleSpaceBar(
                  title:Text((p['name']??'').toString(),maxLines:1,overflow:TextOverflow.ellipsis),
                  background:CachedNetworkImage(
                    imageUrl:(p['photo']??'').toString(),fit:BoxFit.cover,
                    errorWidget:(_,__,___)=>Container(color:Colors.white10),
                  ),
                ),
              ),
              SliverPadding(
                padding:const EdgeInsets.all(16),
                sliver:SliverList(delegate:SliverChildListDelegate([
                  if((p['biography']??'').toString().isNotEmpty)
                    Text((p['biography']??'').toString(),style:const TextStyle(height:1.55)),
                  const SizedBox(height:18),
                  Text(Api.I.ar?'الأعمال':'Filmography',
                    style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
                  const SizedBox(height:10),
                  ...works.map((raw){
                    final w=Map<String,dynamic>.from(raw as Map);
                    final mediaId=(w['media_id'] as num?)?.toInt()??0;
                    return ListTile(
                      contentPadding:EdgeInsets.zero,
                      leading:SizedBox(width:54,child:CachedNetworkImage(
                        imageUrl:(w['poster']??'').toString(),fit:BoxFit.cover,
                        errorWidget:(_,__,___)=>const Icon(Icons.movie_outlined),
                      )),
                      title:Text((w['title']??w['original_title']??'').toString()),
                      subtitle:Text([(w['year']??'').toString(),(w['character_name']??w['job']??'').toString()]
                        .where((x)=>x.isNotEmpty).join(' • ')),
                      onTap:mediaId>0?()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProDetailPage(id:mediaId))):null,
                    );
                  }),
                ])),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProTvPage extends StatefulWidget{
  const ProTvPage({super.key});
  @override
  State<ProTvPage> createState()=>_ProTvPageState();
}
class _ProTvPageState extends State<ProTvPage>{
  final q=TextEditingController();
  Timer? debounce;
  Future<Map<String,dynamic>>? future;
  @override
  void initState(){super.initState();future=_load('');}
  Future<Map<String,dynamic>> _load(String text)=>Api.I.call('channels',query:{'q':text,'limit':50});
  @override
  void dispose(){q.dispose();debounce?.cancel();super.dispose();}
  @override
  Widget build(BuildContext context){
    return SafeArea(
      child:Column(
        children:[
          Padding(
            padding:const EdgeInsets.fromLTRB(12,10,12,6),
            child:SearchBar(
              controller:q,
              hintText:Api.I.ar?'ابحث في القنوات':'Search channels',
              leading:const Icon(Icons.live_tv_outlined),
              onChanged:(v){
                debounce?.cancel();
                debounce=Timer(const Duration(milliseconds:350),()=>setState(()=>future=_load(v)));
              },
            ),
          ),
          Expanded(
            child:FutureBuilder<Map<String,dynamic>>(
              future:future,
              builder:(_,s){
                if(!s.hasData)return const Center(child:CircularProgressIndicator());
                final rows=s.data!['data'] as List? ?? const[];
                return GridView.builder(
                  padding:const EdgeInsets.all(12),
                  gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent:220,childAspectRatio:1.12,crossAxisSpacing:12,mainAxisSpacing:12,
                  ),
                  itemCount:rows.length,
                  itemBuilder:(_,i){
                    final ch=Map<String,dynamic>.from(rows[i] as Map);
                    return Card(
                      clipBehavior:Clip.antiAlias,
                      child:InkWell(
                        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProPlayerPage(
                          ownerType:'tv',ownerId:(ch['id'] as num).toInt(),title:(ch['name']??'').toString(),
                        ))),
                        child:Stack(
                          fit:StackFit.expand,
                          children:[
                            CachedNetworkImage(
                              imageUrl:(ch['backdrop']??ch['logo']??'').toString(),
                              fit:BoxFit.cover,
                              errorWidget:(_,__,___)=>Container(color:Colors.white10),
                            ),
                            const DecoratedBox(decoration:BoxDecoration(
                              gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,
                                colors:[Colors.transparent,Color(0xE0000000)]),
                            )),
                            PositionedDirectional(start:12,end:12,bottom:10,
                              child:Row(children:[
                                SizedBox(width:38,height:38,child:CachedNetworkImage(
                                  imageUrl:(ch['logo']??'').toString(),fit:BoxFit.contain,
                                  errorWidget:(_,__,___)=>const Icon(Icons.live_tv),
                                )),
                                const SizedBox(width:9),
                                Expanded(child:Text((ch['name']??'').toString(),
                                  maxLines:2,overflow:TextOverflow.ellipsis,
                                  style:const TextStyle(fontWeight:FontWeight.w900))),
                              ])),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProSearchPage extends StatefulWidget{
  const ProSearchPage({super.key});
  @override
  State<ProSearchPage> createState()=>_ProSearchPageState();
}
class _ProSearchPageState extends State<ProSearchPage>{
  final controller=TextEditingController();
  Timer? debounce;
  Future<Map<String,dynamic>>? future;
  void search(String q){
    debounce?.cancel();
    if(q.trim().isEmpty){setState(()=>future=null);return;}
    debounce=Timer(const Duration(milliseconds:320),(){
      setState(()=>future=Api.I.call('search',query:{'q':q.trim()}));
    });
  }
  @override
  void dispose(){controller.dispose();debounce?.cancel();super.dispose();}
  @override
  Widget build(BuildContext context){
    return SafeArea(
      child:Column(
        children:[
          Padding(
            padding:const EdgeInsets.all(12),
            child:SearchBar(
              controller:controller,
              autofocus:false,
              hintText:Api.I.ar?'ابحث عن فيلم، مسلسل، قناة أو فنان':'Movies, series, TV or artists',
              leading:const Icon(Icons.search_rounded),
              trailing:[
                if(controller.text.isNotEmpty)IconButton(onPressed:(){
                  controller.clear();setState(()=>future=null);
                },icon:const Icon(Icons.close_rounded)),
              ],
              onChanged:(v){setState((){});search(v);},
              onSubmitted:search,
            ),
          ),
          Expanded(
            child:future==null
              ? _SearchEmpty()
              : FutureBuilder<Map<String,dynamic>>(
                  future:future,
                  builder:(_,s){
                    if(!s.hasData)return const Center(child:CircularProgressIndicator());
                    final root=Map<String,dynamic>.from(s.data!['data'] as Map);
                    final media=root['media'] as List? ?? const[];
                    final people=root['people'] as List? ?? const[];
                    final channels=root['channels'] as List? ?? const[];
                    if(media.isEmpty&&people.isEmpty&&channels.isEmpty){
                      return Center(child:Text(Api.I.ar?'لا توجد نتائج':'No results'));
                    }
                    return ListView(
                      padding:const EdgeInsets.fromLTRB(12,0,12,24),
                      children:[
                        if(media.isNotEmpty)...[
                          _SearchHeader(Api.I.ar?'الأفلام والمسلسلات':'Movies & Series',media.length),
                          GridView.builder(
                            shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
                            gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent:170,childAspectRatio:.58,crossAxisSpacing:10,mainAxisSpacing:12),
                            itemCount:media.length,
                            itemBuilder:(_,i)=>MediaCard(item:Map<String,dynamic>.from(media[i] as Map)),
                          ),
                        ],
                        if(channels.isNotEmpty)...[
                          _SearchHeader(Api.I.ar?'القنوات':'TV Channels',channels.length),
                          ...channels.map((raw){
                            final ch=Map<String,dynamic>.from(raw as Map);
                            return ListTile(
                              leading:CircleAvatar(backgroundImage:(ch['logo']??'').toString().isEmpty?null:NetworkImage(ch['logo'].toString()),
                                child:(ch['logo']??'').toString().isEmpty?const Icon(Icons.live_tv):null),
                              title:Text((ch['name']??'').toString()),
                              subtitle:Text([(ch['category']??'').toString(),(ch['country']??'').toString()]
                                .where((x)=>x.isNotEmpty).join(' • ')),
                              trailing:const Icon(Icons.play_arrow_rounded),
                              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProPlayerPage(
                                ownerType:'tv',ownerId:(ch['id'] as num).toInt(),title:(ch['name']??'').toString(),
                              ))),
                            );
                          }),
                        ],
                        if(people.isNotEmpty)...[
                          _SearchHeader(Api.I.ar?'الفنانون':'Artists',people.length),
                          ...people.map((raw){
                            final p=Map<String,dynamic>.from(raw as Map);
                            return ListTile(
                              leading:CircleAvatar(backgroundImage:(p['photo']??'').toString().isEmpty?null:NetworkImage(p['photo'].toString()),
                                child:(p['photo']??'').toString().isEmpty?const Icon(Icons.person):null),
                              title:Text((p['name']??'').toString()),
                              subtitle:Text((p['known_for']??'').toString()),
                              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PersonPage(id:(p['id'] as num).toInt()))),
                            );
                          }),
                        ],
                      ],
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget{
  @override
  Widget build(BuildContext context)=>Center(
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.manage_search_rounded,size:72,color:Colors.white24),
      const SizedBox(height:10),
      Text(Api.I.ar?'بحث موحّد في كل محتوى ShortSeris':'Search all ShortSeris content',
        style:const TextStyle(color:Colors.white54)),
    ]),
  );
}
class _SearchHeader extends StatelessWidget{
  final String title; final int count;
  const _SearchHeader(this.title,this.count);
  @override
  Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.fromLTRB(2,20,2,10),
    child:Row(children:[
      Expanded(child:Text(title,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900))),
      Text(count.toString(),style:const TextStyle(color:Colors.white54)),
    ]),
  );
}

class ProAccountPage extends StatefulWidget{
  const ProAccountPage({super.key});
  @override
  State<ProAccountPage> createState()=>_ProAccountPageState();
}
class _ProAccountPageState extends State<ProAccountPage>{
  Future<Map<String,dynamic>>? future;
  @override
  void initState(){super.initState();future=Api.I.call('me');}
  void reload()=>setState(()=>future=Api.I.call('me'));
  @override
  Widget build(BuildContext context){
    return SafeArea(
      child:FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(_,s){
          if(s.hasError)return LoginPage(key:ValueKey(DateTime.now().millisecondsSinceEpoch));
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final u=Map<String,dynamic>.from(s.data!['data'] as Map);
          final role=(u['role']??'user').toString().toLowerCase();
          final staff=['admin','editor','moderator','seo'].contains(role);
          final links=Api.I.config['links'];
          return ListView(
            padding:const EdgeInsets.all(16),
            children:[
              Center(
                child:CircleAvatar(
                  radius:44,
                  backgroundImage:(u['avatar']??'').toString().isEmpty?null:NetworkImage(u['avatar'].toString()),
                  child:(u['avatar']??'').toString().isEmpty?const Icon(Icons.person,size:44):null,
                ),
              ),
              const SizedBox(height:12),
              Center(child:Text((u['name']??'').toString(),
                style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900))),
              Center(child:Text((u['email']??'').toString(),style:const TextStyle(color:Colors.white54))),
              const SizedBox(height:18),
              if(staff)
                Card(
                  child:ListTile(
                    leading:const CircleAvatar(child:Icon(Icons.admin_panel_settings_rounded)),
                    title:Text(Api.I.ar?'استوديو الإدارة':'Admin Studio',
                      style:const TextStyle(fontWeight:FontWeight.w900)),
                    subtitle:Text(Api.I.ar?'الجلب، TMDB، المحتوى والسيرفرات':'Import, TMDB, content & servers'),
                    trailing:const Icon(Icons.chevron_right_rounded),
                    onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AdminStudioPage())),
                  ),
                ),
              Card(
                child:Column(children:[
                  ListTile(
                    leading:const Icon(Icons.history_rounded),
                    title:Text(Api.I.ar?'متابعة المشاهدة':'Continue watching'),
                    onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const ContinuePage())),
                  ),
                  ListTile(
                    leading:const Icon(Icons.favorite_border_rounded),
                    title:Text(Api.I.ar?'المفضلة':'Favorites'),
                    onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AccountMediaListPage(action:'favorites'))),
                  ),
                  ListTile(
                    leading:const Icon(Icons.bookmark_border_rounded),
                    title:Text(Api.I.ar?'قائمتي':'My List'),
                    onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AccountMediaListPage(action:'watchlist'))),
                  ),
                ]),
              ),
              if(links is Map)...[
                if((links['support']??'').toString().isNotEmpty)ListTile(
                  leading:const Icon(Icons.support_agent_rounded),title:Text(Api.I.ar?'الدعم':'Support'),
                  onTap:()=>launchUrl(Uri.parse(links['support'].toString()),mode:LaunchMode.externalApplication),
                ),
                if((links['privacy']??'').toString().isNotEmpty)ListTile(
                  leading:const Icon(Icons.privacy_tip_outlined),title:Text(Api.I.ar?'الخصوصية':'Privacy'),
                  onTap:()=>launchUrl(Uri.parse(links['privacy'].toString()),mode:LaunchMode.externalApplication),
                ),
              ],
              const SizedBox(height:10),
              OutlinedButton.icon(
                onPressed:() async {await Api.I.logout();reload();},
                icon:const Icon(Icons.logout_rounded),
                label:Text(Api.I.ar?'تسجيل الخروج':'Logout'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AccountMediaListPage extends StatelessWidget{
  final String action;
  const AccountMediaListPage({super.key,required this.action});
  @override
  Widget build(BuildContext context){
    final title=action=='favorites'?(Api.I.ar?'المفضلة':'Favorites'):(Api.I.ar?'قائمتي':'My List');
    return Scaffold(
      appBar:AppBar(title:Text(title)),
      body:FutureBuilder<Map<String,dynamic>>(
        future:Api.I.call(action),
        builder:(_,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final rows=s.data!['data'] as List? ?? const[];
          return GridView.builder(
            padding:const EdgeInsets.all(12),
            gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:190,childAspectRatio:.57,crossAxisSpacing:12,mainAxisSpacing:14),
            itemCount:rows.length,
            itemBuilder:(_,i)=>MediaCard(item:Map<String,dynamic>.from(rows[i] as Map)),
          );
        },
      ),
    );
  }
}

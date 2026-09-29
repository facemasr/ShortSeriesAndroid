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
                  onPressed: ()=>AppNavigator.open(
                    context,
                    const GenrePage(),
                    key:'browse/genres',
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
  Future<void> _load({bool reset=false,bool forceRefresh=false}) async {
    if(loading)return;
    if(reset){
      rows.clear();
      page=1;
      done=false;
      if(mounted)setState((){});
    }
    if(done)return;
    if(mounted)setState(()=>loading=true);

    try{
      final res=await Api.I.call(
        'media',
        query:{
          'type':widget.type,
          'q':widget.query,
          'page':page,
          'limit':30,
        },
        forceRefresh:forceRefresh,
      );

      final list=Api.I.responseRows(
        res,
        keys:const ['media','items','rows','data','results'],
      );

      final existing=rows
        .map((row)=>int.tryParse((row['id']??'').toString())??0)
        .where((id)=>id>0)
        .toSet();

      var added=0;
      for(final row in list){
        final id=int.tryParse((row['id']??'').toString())??0;
        if(id>0&&existing.contains(id))continue;
        rows.add(row);
        if(id>0)existing.add(id);
        added++;
      }

      final dataMap=Api.I.mapFrom(res['data']);
      dynamic meta=res['meta'];
      meta??=dataMap['meta'];
      meta??=dataMap['pagination'];

      if(meta is Map){
        final total=int.tryParse(
          (meta['total']??meta['total_items']??meta['count']??'').toString(),
        );
        if(total!=null&&total>=0){
          done=rows.length>=total;
        }else{
          done=list.isEmpty||added==0||list.length<30;
        }
      }else{
        done=list.isEmpty||added==0||list.length<30;
      }
      page++;
    }catch(_){
      if(rows.isEmpty)done=true;
    }

    if(mounted)setState(()=>loading=false);
  }
  @override
  void dispose(){scroll.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    if(rows.isEmpty&&loading)return const Center(child:CircularProgressIndicator());
    if(rows.isEmpty)return Center(child:Text(Api.I.ar?'لا يوجد محتوى':'No content'));
    return RefreshIndicator(
      onRefresh:()=>_load(reset:true,forceRefresh:true),
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
  void initState(){
    super.initState();
    future=Api.I.call('genres');
  }

  Future<void> _refresh() async{
    final next=Api.I.call('genres',forceRefresh:true);
    setState(()=>future=next);
    await next;
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(title:Text(Api.I.ar?'التصنيفات':'Genres')),
      body:RefreshIndicator(
        onRefresh:_refresh,
        child:FutureBuilder<Map<String,dynamic>>(
          future:future,
          builder:(_,snapshot){
            if(snapshot.hasError){
              return ListView(
                children:[
                  const SizedBox(height:180),
                  Center(
                    child:FilledButton.icon(
                      onPressed:_refresh,
                      icon:const Icon(Icons.refresh_rounded),
                      label:Text(Api.I.ar?'إعادة المحاولة':'Retry'),
                    ),
                  ),
                ],
              );
            }
            if(!snapshot.hasData){
              return const Center(child:CircularProgressIndicator());
            }

            final rows=Api.I.responseRows(
              snapshot.data!,
              keys:const ['genres','items','rows','data','results'],
            );

            if(rows.isEmpty){
              return ListView(
                children:[
                  const SizedBox(height:180),
                  Center(child:Text(Api.I.ar?'لا توجد تصنيفات':'No genres')),
                ],
              );
            }

            return ListView.separated(
              padding:const EdgeInsets.fromLTRB(12,10,12,24),
              itemCount:rows.length,
              separatorBuilder:(_,__)=>const SizedBox(height:8),
              itemBuilder:(_,i){
                final g=rows[i];
                final id=int.tryParse((g['id']??g['genre_id']??'').toString())??0;
                final name=(g['name']??g['title']??'').toString().trim();
                final slug=(g['slug']??'').toString().trim();
                final count=(g['media_count']??g['count']??g['items_count']??'').toString();

                return Card(
                  clipBehavior:Clip.antiAlias,
                  child:ListTile(
                    contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:5),
                    leading:CircleAvatar(
                      backgroundColor:const Color(0x22E50914),
                      child:const Icon(Icons.local_movies_outlined),
                    ),
                    title:Text(
                      name.isEmpty?(Api.I.ar?'تصنيف':'Genre'):name,
                      style:const TextStyle(fontWeight:FontWeight.w900),
                    ),
                    subtitle:count.isEmpty?null:Text(
                      Api.I.ar?'$count عمل':'$count titles',
                    ),
                    trailing:const Icon(Icons.chevron_right_rounded),
                    onTap:id<=0?null:(){
                      AppNavigator.open(
                        context,
                        GenreMediaPage(
                          genreId:id,
                          name:name,
                          slug:slug,
                        ),
                        key:'genre/$id',
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class GenreMediaPage extends StatefulWidget{
  final int genreId;
  final String name;
  final String slug;

  const GenreMediaPage({
    super.key,
    required this.genreId,
    required this.name,
    this.slug='',
  });

  @override
  State<GenreMediaPage> createState()=>_GenreMediaPageState();
}

class _GenreMediaPageState extends State<GenreMediaPage>{
  late Future<Map<String,dynamic>> future;

  @override
  void initState(){
    super.initState();
    future=_load();
  }

  Future<Map<String,dynamic>> _load({bool forceRefresh=false}){
    return Api.I.call(
      'media',
      query:{
        'genre_id':widget.genreId,
        if(widget.slug.isNotEmpty)'genre':widget.slug,
        'limit':100,
      },
      forceRefresh:forceRefresh,
    );
  }

  Future<void> _refresh() async{
    final next=_load(forceRefresh:true);
    setState(()=>future=next);
    await next;
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(
        title:Text(widget.name.isEmpty?(Api.I.ar?'التصنيف':'Genre'):widget.name),
      ),
      body:RefreshIndicator(
        onRefresh:_refresh,
        child:FutureBuilder<Map<String,dynamic>>(
          future:future,
          builder:(_,snapshot){
            if(snapshot.hasError){
              return ListView(
                children:[
                  const SizedBox(height:180),
                  Center(
                    child:FilledButton.icon(
                      onPressed:_refresh,
                      icon:const Icon(Icons.refresh_rounded),
                      label:Text(Api.I.ar?'إعادة المحاولة':'Retry'),
                    ),
                  ),
                ],
              );
            }
            if(!snapshot.hasData){
              return const Center(child:CircularProgressIndicator());
            }

            final rows=Api.I.responseRows(
              snapshot.data!,
              keys:const ['media','items','rows','data','results'],
            );

            if(rows.isEmpty){
              return ListView(
                children:[
                  const SizedBox(height:180),
                  Center(child:Text(Api.I.ar?'لا يوجد محتوى في هذا التصنيف':'No titles in this genre')),
                ],
              );
            }

            return GridView.builder(
              padding:const EdgeInsets.all(12),
              gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent:180,
                childAspectRatio:.55,
                crossAxisSpacing:11,
                mainAxisSpacing:12,
              ),
              itemCount:rows.length,
              itemBuilder:(_,i)=>MediaCard(item:rows[i]),
            );
          },
        ),
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
  void initState(){
    super.initState();
    future=Api.I.call('people',query:{'limit':100});
  }

  Future<void> _refresh() async{
    final next=Api.I.call(
      'people',
      query:{'limit':100},
      forceRefresh:true,
    );
    setState(()=>future=next);
    await next;
  }

  String _photo(Map<String,dynamic> person){
    final direct=(person['photo']??person['profile']??person['image']??'').toString().trim();
    if(direct.isNotEmpty)return Api.I.absoluteUrl(direct);
    final path=(person['profile_path']??'').toString().trim();
    if(path.isNotEmpty){
      return 'https://image.tmdb.org/t/p/w500${path.startsWith('/')?path:'/$path'}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context){
    final body=RefreshIndicator(
      onRefresh:_refresh,
      child:FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(_,snapshot){
          if(snapshot.hasError){
            return ListView(
              children:[
                const SizedBox(height:180),
                Center(
                  child:FilledButton.icon(
                    onPressed:_refresh,
                    icon:const Icon(Icons.refresh_rounded),
                    label:Text(Api.I.ar?'إعادة المحاولة':'Retry'),
                  ),
                ),
              ],
            );
          }
          if(!snapshot.hasData){
            return const Center(child:CircularProgressIndicator());
          }

          final rows=Api.I.responseRows(
            snapshot.data!,
            keys:const ['people','artists','items','rows','data','results'],
          );

          if(rows.isEmpty){
            return ListView(
              children:[
                const SizedBox(height:180),
                Center(child:Text(Api.I.ar?'لا يوجد فنانون':'No artists')),
              ],
            );
          }

          return GridView.builder(
            padding:const EdgeInsets.all(12),
            gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:175,
              childAspectRatio:.70,
              crossAxisSpacing:11,
              mainAxisSpacing:13,
            ),
            itemCount:rows.length,
            itemBuilder:(_,i){
              final person=rows[i];
              final personId=int.tryParse((person['id']??person['person_id']??'').toString())??0;
              final photo=_photo(person);
              final name=(person['name']??person['title']??'').toString().trim();
              final knownFor=(person['known_for']??person['department']??'').toString().trim();

              return Material(
                color:const Color(0xFF101114),
                borderRadius:BorderRadius.circular(16),
                clipBehavior:Clip.antiAlias,
                child:InkWell(
                  onTap:personId<=0?null:(){
                    AppNavigator.open(
                      context,
                      PersonPage(id:personId),
                      key:'person/$personId',
                    );
                  },
                  child:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Expanded(
                        child:photo.isEmpty
                          ?Container(
                              width:double.infinity,
                              color:const Color(0xFF17181C),
                              child:const Icon(Icons.person_rounded,size:56,color:Colors.white24),
                            )
                          :CachedNetworkImage(
                              imageUrl:photo,
                              width:double.infinity,
                              fit:BoxFit.cover,
                              errorWidget:(_,__,___)=>Container(
                                color:const Color(0xFF17181C),
                                child:const Icon(Icons.person_rounded,size:56,color:Colors.white24),
                              ),
                            ),
                      ),
                      Padding(
                        padding:const EdgeInsets.fromLTRB(9,8,9,9),
                        child:Column(
                          crossAxisAlignment:CrossAxisAlignment.start,
                          children:[
                            Text(
                              name.isEmpty?(Api.I.ar?'فنان':'Artist'):name,
                              maxLines:1,
                              overflow:TextOverflow.ellipsis,
                              style:const TextStyle(fontWeight:FontWeight.w900),
                            ),
                            const SizedBox(height:2),
                            Text(
                              knownFor,
                              maxLines:1,
                              overflow:TextOverflow.ellipsis,
                              style:const TextStyle(fontSize:10.5,color:Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    if(widget.embedded)return body;
    return Scaffold(
      appBar:AppBar(title:Text(Api.I.ar?'الفنانون':'Artists')),
      body:body,
    );
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
  void initState(){
    super.initState();
    future=Api.I.call('person',query:{'id':widget.id});
  }

  Map<String,dynamic> _rawJson(Map<String,dynamic> work){
    final raw=(work['raw_json']??'').toString().trim();
    if(raw.isEmpty)return const {};
    try{
      final decoded=jsonDecode(raw);
      return decoded is Map ? Map<String,dynamic>.from(decoded) : const {};
    }catch(_){
      return const {};
    }
  }

  String _poster(Map<String,dynamic> work){
    final direct=(work['poster']??work['poster_url']??work['image']??work['profile']??'').toString().trim();
    if(direct.isNotEmpty)return Api.I.absoluteUrl(direct);
    final explicitPath=(work['poster_path']??'').toString().trim();
    if(explicitPath.isNotEmpty){
      return 'https://image.tmdb.org/t/p/w342${explicitPath.startsWith('/')?explicitPath:'/$explicitPath'}';
    }
    final raw=_rawJson(work);
    final path=(raw['poster_path']??'').toString().trim();
    if(path.isNotEmpty){
      return 'https://image.tmdb.org/t/p/w342${path.startsWith('/')?path:'/$path'}';
    }
    return '';
  }

  int _localMediaId(Map<String,dynamic> work){
    return int.tryParse((work['local_media_id']??work['media_id']??'').toString())??0;
  }

  List<Map<String,dynamic>> _dedupeWorks(List rawWorks){
    final byKey=<String,Map<String,dynamic>>{};
    for(final workEntry in rawWorks){
      if(workEntry is! Map)continue;
      final w=Map<String,dynamic>.from(workEntry);
      final tmdb=(w['tmdb_id']??'').toString();
      final type=(w['media_type']??w['type']??'').toString();
      final rawData=_rawJson(w);
      final title=(w['title']??w['name']??w['original_title']??w['original_name']??rawData['title']??rawData['name']??'').toString();
      final key=tmdb.isNotEmpty?'$type:$tmdb':'$type:$title';
      final existing=byKey[key];
      if(existing==null){
        byKey[key]=w;
        continue;
      }

      final existingLocal=_localMediaId(existing);
      final nextLocal=_localMediaId(w);
      if(existingLocal<=0&&nextLocal>0){
        byKey[key]=w;
        continue;
      }

      final roles=<String>{};
      for(final value in [
        existing['character_name'],existing['job'],
        w['character_name'],w['job'],
      ]){
        final text=(value??'').toString().trim();
        if(text.isNotEmpty)roles.add(text);
      }
      if(roles.isNotEmpty){
        existing['_roles']=roles.join(' • ');
      }
    }

    final out=byKey.values.toList();
    out.sort((a,b){
      final ay=int.tryParse((a['year']??'0').toString())??0;
      final by=int.tryParse((b['year']??'0').toString())??0;
      if(ay!=by)return by.compareTo(ay);
      final ad=(a['release_date']??'').toString();
      final bd=(b['release_date']??'').toString();
      return bd.compareTo(ad);
    });
    return out;
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body:FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(_,s){
          if(s.hasError){
            return Center(child:Text(Api.I.ar?'تعذر تحميل بيانات الفنان':'Could not load artist'));
          }
          if(!s.hasData)return const Center(child:CircularProgressIndicator());

          final rawData=s.data!['data'];
          final root=Api.I.mapFrom(rawData);

          final p=root['person'] is Map
            ?Map<String,dynamic>.from(root['person'] as Map)
            :Map<String,dynamic>.from(root);

          final rawWorks=<dynamic>[];
          for(final candidate in [
            root['works'],
            root['filmography'],
            p['works'],
            p['filmography'],
          ]){
            if(candidate is List)rawWorks.addAll(candidate);
          }

          final localItems=Api.I.rowsFrom(
            root,
            keys:const ['items','media','local_works','credits'],
          );
          for(final local in localItems){
            final copy=Map<String,dynamic>.from(local);
            copy['local_media_id']??=copy['id'];
            rawWorks.add(copy);
          }

          final works=_dedupeWorks(rawWorks);
          final biography=(p['biography']??p['overview']??'').toString().trim();
          final knownFor=(p['known_for']??'').toString().trim();
          final birthday=(p['birthday']??'').toString().trim();
          final birthplace=(p['place_of_birth']??'').toString().trim();

          return CustomScrollView(
            slivers:[
              SliverAppBar(
                pinned:true,
                expandedHeight:340,
                flexibleSpace:FlexibleSpaceBar(
                  title:Text(
                    (p['name']??'').toString(),
                    maxLines:1,
                    overflow:TextOverflow.ellipsis,
                  ),
                  background:Stack(
                    fit:StackFit.expand,
                    children:[
                      CachedNetworkImage(
                        imageUrl:Api.I.absoluteUrl(p['photo']),
                        fit:BoxFit.cover,
                        errorWidget:(_,__,___)=>Container(
                          color:Colors.white10,
                          child:const Icon(Icons.person,size:84),
                        ),
                      ),
                      const DecoratedBox(
                        decoration:BoxDecoration(
                          gradient:LinearGradient(
                            begin:Alignment.topCenter,
                            end:Alignment.bottomCenter,
                            colors:[Colors.transparent,Color(0xE6000000)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding:const EdgeInsets.fromLTRB(16,16,16,28),
                sliver:SliverList(
                  delegate:SliverChildListDelegate([
                    Wrap(
                      spacing:8,
                      runSpacing:8,
                      children:[
                        if(knownFor.isNotEmpty)Chip(label:Text(knownFor)),
                        if(birthday.isNotEmpty)Chip(label:Text(birthday)),
                        if(birthplace.isNotEmpty)Chip(label:Text(birthplace)),
                      ],
                    ),
                    if(biography.isNotEmpty)...[
                      const SizedBox(height:14),
                      Text(
                        biography,
                        style:const TextStyle(height:1.6,color:Colors.white70),
                      ),
                    ],
                    const SizedBox(height:22),
                    Row(
                      children:[
                        Expanded(
                          child:Text(
                            Api.I.ar?'أعمال الفنان':'Filmography',
                            style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900),
                          ),
                        ),
                        Text(
                          works.length.toString(),
                          style:const TextStyle(color:Colors.white54,fontWeight:FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height:10),
                    if(works.isEmpty)
                      Card(
                        child:Padding(
                          padding:const EdgeInsets.all(18),
                          child:Text(
                            Api.I.ar
                              ?'لا توجد أعمال محفوظة لهذا الفنان حتى الآن.'
                              :'No saved filmography is available for this artist yet.',
                            textAlign:TextAlign.center,
                          ),
                        ),
                      ),
                    ...works.map((w){
                      final mediaId=_localMediaId(w);
                      final poster=_poster(w);
                      final title=(w['title']??w['original_title']??'').toString();
                      final roles=(w['_roles']??w['character_name']??w['job']??'').toString().trim();
                      final year=(w['year']??'').toString().trim();
                      final mediaType=(w['media_type']??w['type']??'').toString();
                      final meta=<String>[
                        if(year.isNotEmpty)year,
                        if(mediaType.isNotEmpty)(mediaType=='tv'?(Api.I.ar?'مسلسل':'Series'):(Api.I.ar?'فيلم':'Movie')),
                        if(roles.isNotEmpty)roles,
                      ];

                      return Card(
                        margin:const EdgeInsets.only(bottom:10),
                        clipBehavior:Clip.antiAlias,
                        child:ListTile(
                          minVerticalPadding:8,
                          leading:ClipRRect(
                            borderRadius:BorderRadius.circular(8),
                            child:SizedBox(
                              width:54,
                              height:78,
                              child:poster.isEmpty
                                ?Container(color:Colors.white10,child:const Icon(Icons.movie_outlined))
                                :CachedNetworkImage(
                                    imageUrl:poster,
                                    fit:BoxFit.cover,
                                    errorWidget:(_,__,___)=>Container(
                                      color:Colors.white10,
                                      child:const Icon(Icons.movie_outlined),
                                    ),
                                  ),
                            ),
                          ),
                          title:Text(title,maxLines:2,overflow:TextOverflow.ellipsis),
                          subtitle:Text(
                            meta.join(' • '),
                            maxLines:2,
                            overflow:TextOverflow.ellipsis,
                          ),
                          trailing:mediaId>0
                            ?const Icon(Icons.chevron_right_rounded)
                            :const Icon(Icons.info_outline_rounded,color:Colors.white38),
                          onTap:mediaId>0
                            ?(){
                                AppNavigator.open(
                                  context,
                                  ProDetailPage(id:mediaId),
                                  key:'media/$mediaId',
                                );
                              }
                            :null,
                        ),
                      );
                    }),
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
                        onTap:(){
                          final id=(ch['id'] as num).toInt();
                          AppNavigator.open(
                            context,
                            ProPlayerPage(ownerType:'tv',ownerId:id,title:(ch['name']??'').toString()),
                            key:'player/tv/$id',
                          );
                        },
                        child:Stack(
                          fit:StackFit.expand,
                          children:[
                            CachedNetworkImage(
                              imageUrl:Api.I.absoluteUrl(ch['backdrop']??ch['logo']),
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
                                  imageUrl:Api.I.absoluteUrl(ch['logo']),fit:BoxFit.contain,
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
                              leading:CircleAvatar(backgroundImage:(ch['logo']??'').toString().isEmpty?null:NetworkImage(Api.I.absoluteUrl(ch['logo'])),
                                child:(ch['logo']??'').toString().isEmpty?const Icon(Icons.live_tv):null),
                              title:Text((ch['name']??'').toString()),
                              subtitle:Text([(ch['category']??'').toString(),(ch['country']??'').toString()]
                                .where((x)=>x.isNotEmpty).join(' • ')),
                              trailing:const Icon(Icons.play_arrow_rounded),
                              onTap:(){
                                final id=(ch['id'] as num).toInt();
                                AppNavigator.open(
                                  context,
                                  ProPlayerPage(ownerType:'tv',ownerId:id,title:(ch['name']??'').toString()),
                                  key:'player/tv/$id',
                                );
                              },
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
                              onTap:(){
                                final id=(p['id'] as num).toInt();
                                AppNavigator.open(context,PersonPage(id:id),key:'person/$id');
                              },
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
  Future<Map<String,int>>? statsFuture;

  @override
  void initState(){
    super.initState();
    _refresh();
  }

  void _refresh(){
    future=Api.I.call('me');
    statsFuture=_loadStats();
  }

  void reload(){
    if(!mounted)return;
    setState(_refresh);
  }

  Future<int> _count(String action) async{
    try{
      final res=await Api.I.call(action);
      final data=res['data'];
      if(data is List)return data.length;
      if(data is Map){
        final rows=data['items']??data['rows']??data['data'];
        if(rows is List)return rows.length;
        final count=data['count'];
        if(count is num)return count.toInt();
      }
    }catch(_){}
    return 0;
  }

  Future<Map<String,int>> _loadStats() async{
    final values=await Future.wait<int>([
      _count('continue'),
      _count('favorites'),
      _count('watchlist'),
    ]);
    final downloads=(await OfflineDownloads.I.all()).length;
    return <String,int>{
      'continue':values[0],
      'favorites':values[1],
      'watchlist':values[2],
      'downloads':downloads,
    };
  }

  String _roleLabel(String role){
    switch(role){
      case 'admin':return Api.I.ar?'مدير الموقع':'Administrator';
      case 'editor':return Api.I.ar?'محرر':'Editor';
      case 'moderator':return Api.I.ar?'مشرف':'Moderator';
      case 'seo':return 'SEO';
      default:return Api.I.ar?'مشترك':'Subscriber';
    }
  }

  @override
  Widget build(BuildContext context){
    return SafeArea(
      child:RefreshIndicator(
        onRefresh:() async{
          _refresh();
          setState((){});
          try{await future;}catch(_){}
        },
        child:FutureBuilder<Map<String,dynamic>>(
          future:future,
          builder:(_,s){
            if(s.hasError){
              final err=s.error;
              final networkError=err is DioException&&err.response==null;
              if(networkError){
                return OfflineAccountPage(onRetry:reload);
              }
              return LoginPage(onAuthenticated:reload);
            }
            if(!s.hasData){
              return ListView(
                physics:const AlwaysScrollableScrollPhysics(),
                children:const [
                  SizedBox(height:260),
                  Center(child:CircularProgressIndicator()),
                ],
              );
            }

            final u=Map<String,dynamic>.from(s.data!['data'] as Map);
            final role=(u['role']??'user').toString().toLowerCase();
            final isAdmin=role=='admin';
            final isStaff=['admin','editor','moderator','seo'].contains(role);
            final email=(u['email']??'').toString();
            final avatar=Api.I.absoluteUrl(u['avatar']);
            final status=(u['status']??'active').toString();
            final links=Api.I.config['links'];

            return ListView(
              physics:const AlwaysScrollableScrollPhysics(),
              padding:const EdgeInsets.fromLTRB(14,14,14,30),
              children:[
                Card(
                  clipBehavior:Clip.antiAlias,
                  child:Container(
                    padding:const EdgeInsets.all(18),
                    decoration:const BoxDecoration(
                      gradient:LinearGradient(
                        begin:Alignment.topLeft,
                        end:Alignment.bottomRight,
                        colors:[Color(0xFF181A20),Color(0xFF0C0D10)],
                      ),
                    ),
                    child:Row(
                      children:[
                        CircleAvatar(
                          radius:40,
                          backgroundImage:avatar.isEmpty?null:NetworkImage(avatar),
                          child:avatar.isEmpty?const Icon(Icons.person_rounded,size:40):null,
                        ),
                        const SizedBox(width:14),
                        Expanded(
                          child:Column(
                            crossAxisAlignment:CrossAxisAlignment.start,
                            children:[
                              Text(
                                (u['name']??'').toString(),
                                maxLines:1,
                                overflow:TextOverflow.ellipsis,
                                style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900),
                              ),
                              if(email.isNotEmpty)...[
                                const SizedBox(height:2),
                                Text(
                                  email,
                                  maxLines:1,
                                  overflow:TextOverflow.ellipsis,
                                  style:const TextStyle(color:Colors.white60),
                                ),
                              ],
                              const SizedBox(height:9),
                              Wrap(
                                spacing:7,
                                runSpacing:7,
                                children:[
                                  Chip(
                                    avatar:Icon(
                                      isAdmin
                                        ?Icons.admin_panel_settings_rounded
                                        :isStaff
                                          ?Icons.verified_user_outlined
                                          :Icons.workspace_premium_outlined,
                                      size:16,
                                    ),
                                    label:Text(_roleLabel(role)),
                                  ),
                                  Chip(
                                    avatar:Icon(
                                      status=='active'?Icons.check_circle_outline:Icons.info_outline,
                                      size:16,
                                    ),
                                    label:Text(
                                      status=='active'
                                        ?(Api.I.ar?'نشط':'Active')
                                        :status,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip:Api.I.ar?'تفاصيل الحساب':'Account details',
                          onPressed:()=>AppNavigator.open(
                            context,
                            AccountDetailsPage(user:u),
                            key:'account/details',
                          ),
                          icon:const Icon(Icons.manage_accounts_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height:14),

                FutureBuilder<Map<String,int>>(
                  future:statsFuture,
                  builder:(_,stats){
                    final data=stats.data??const <String,int>{};
                    return GridView.count(
                      crossAxisCount:4,
                      shrinkWrap:true,
                      physics:const NeverScrollableScrollPhysics(),
                      childAspectRatio:.78,
                      crossAxisSpacing:8,
                      mainAxisSpacing:8,
                      children:[
                        _AccountStat(
                          icon:Icons.history_rounded,
                          label:Api.I.ar?'متابعة':'Continue',
                          value:data['continue'],
                          onTap:()=>AppNavigator.open(
                            context,
                            const ContinuePage(),
                            key:'account/continue',
                          ),
                        ),
                        _AccountStat(
                          icon:Icons.favorite_rounded,
                          label:Api.I.ar?'المفضلة':'Favorites',
                          value:data['favorites'],
                          onTap:()=>AppNavigator.open(
                            context,
                            const AccountMediaListPage(action:'favorites'),
                            key:'account/favorites',
                          ),
                        ),
                        _AccountStat(
                          icon:Icons.bookmark_rounded,
                          label:Api.I.ar?'قائمتي':'My List',
                          value:data['watchlist'],
                          onTap:()=>AppNavigator.open(
                            context,
                            const AccountMediaListPage(action:'watchlist'),
                            key:'account/watchlist',
                          ),
                        ),
                        _AccountStat(
                          icon:Icons.download_done_rounded,
                          label:Api.I.ar?'التنزيلات':'Downloads',
                          value:data['downloads'],
                          onTap:()=>AppNavigator.open(
                            context,
                            const OfflineLibraryPage(),
                            key:'account/downloads',
                          ),
                        ),
                      ],
                    );
                  },
                ),

                if(isAdmin)...[
                  const SizedBox(height:18),
                  Text(
                    Api.I.ar?'إدارة الموقع':'Website Administration',
                    style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900),
                  ),
                  const SizedBox(height:9),
                  Card(
                    clipBehavior:Clip.antiAlias,
                    child:Column(
                      children:[
                        ListTile(
                          contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:7),
                          leading:const CircleAvatar(
                            backgroundColor:Color(0x22E50914),
                            child:Icon(Icons.dashboard_customize_rounded,color:Color(0xFFE50914)),
                          ),
                          title:Text(
                            Api.I.ar?'لوحة التحكم الكاملة':'Full Website Control Panel',
                            style:const TextStyle(fontWeight:FontWeight.w900),
                          ),
                          subtitle:Text(
                            Api.I.ar
                              ?'كل أقسام إدارة الموقع كما في نسخة الويب'
                              :'Every website admin section, embedded in the app',
                          ),
                          trailing:const Icon(Icons.chevron_right_rounded),
                          onTap:()=>AppNavigator.open(
                            context,
                            AdminWebHubPage(userEmail:email),
                            key:'admin/web-hub',
                          ),
                        ),
                        const Divider(height:1),
                        ListTile(
                          contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:7),
                          leading:const CircleAvatar(child:Icon(Icons.bolt_rounded)),
                          title:Text(
                            Api.I.ar?'استوديو الإدارة السريع':'Native Admin Studio',
                            style:const TextStyle(fontWeight:FontWeight.w900),
                          ),
                          subtitle:Text(
                            Api.I.ar
                              ?'الجلب، TMDB، المحتوى والقنوات مباشرة من التطبيق'
                              :'Import, TMDB, content and TV tools',
                          ),
                          trailing:const Icon(Icons.chevron_right_rounded),
                          onTap:()=>AppNavigator.open(
                            context,
                            AdminStudioPage(userEmail:email),
                            key:'admin/studio',
                          ),
                        ),
                        const Divider(height:1),
                        ListTile(
                          leading:const Icon(Icons.group_rounded),
                          title:Text(Api.I.ar?'المشتركون والمستخدمون':'Subscribers & Users'),
                          subtitle:Text(Api.I.ar?'إدارة الأدوار والحالة والحسابات':'Roles, account status and users'),
                          trailing:const Icon(Icons.chevron_right_rounded),
                          onTap:()=>AppNavigator.open(
                            context,
                            AdminWebPanelPage(
                              initialPath:'/admin/users',
                              title:Api.I.ar?'المشتركون':'Users',
                              userEmail:email,
                            ),
                            key:'admin/web/users',
                          ),
                        ),
                      ],
                    ),
                  ),
                ]else if(isStaff)...[
                  const SizedBox(height:18),
                  Card(
                    child:ListTile(
                      leading:const CircleAvatar(child:Icon(Icons.admin_panel_settings_rounded)),
                      title:Text(
                        Api.I.ar?'استوديو الإدارة':'Admin Studio',
                        style:const TextStyle(fontWeight:FontWeight.w900),
                      ),
                      subtitle:Text(
                        Api.I.ar
                          ?'الأدوات المتاحة حسب صلاحيات حسابك'
                          :'Tools available for your account role',
                      ),
                      trailing:const Icon(Icons.chevron_right_rounded),
                      onTap:()=>AppNavigator.open(
                        context,
                        AdminStudioPage(userEmail:email),
                        key:'admin/studio',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height:18),
                Text(
                  Api.I.ar?'حساب المشترك':'Subscriber Center',
                  style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900),
                ),
                const SizedBox(height:9),
                Card(
                  child:Column(
                    children:[
                      ListTile(
                        leading:const Icon(Icons.manage_accounts_outlined),
                        title:Text(Api.I.ar?'معلومات الحساب':'Account information'),
                        subtitle:Text(Api.I.ar?'البيانات والدور وحالة الحساب':'Profile, role and account status'),
                        trailing:const Icon(Icons.chevron_right_rounded),
                        onTap:()=>AppNavigator.open(
                          context,
                          AccountDetailsPage(user:u),
                          key:'account/details',
                        ),
                      ),
                      const Divider(height:1),
                      ListTile(
                        leading:const Icon(Icons.history_rounded),
                        title:Text(Api.I.ar?'متابعة المشاهدة':'Continue watching'),
                        onTap:()=>AppNavigator.open(context,const ContinuePage(),key:'account/continue'),
                      ),
                      ListTile(
                        leading:const Icon(Icons.favorite_border_rounded),
                        title:Text(Api.I.ar?'المفضلة':'Favorites'),
                        onTap:()=>AppNavigator.open(
                          context,
                          const AccountMediaListPage(action:'favorites'),
                          key:'account/favorites',
                        ),
                      ),
                      ListTile(
                        leading:const Icon(Icons.bookmark_border_rounded),
                        title:Text(Api.I.ar?'قائمتي':'My List'),
                        onTap:()=>AppNavigator.open(
                          context,
                          const AccountMediaListPage(action:'watchlist'),
                          key:'account/watchlist',
                        ),
                      ),
                      ListTile(
                        leading:const Icon(Icons.download_for_offline_outlined),
                        title:Text(Api.I.ar?'التنزيلات':'Downloads'),
                        subtitle:Text(Api.I.ar?'المحتوى المشفّر للمشاهدة بدون إنترنت':'Encrypted offline media'),
                        onTap:()=>AppNavigator.open(
                          context,
                          const OfflineLibraryPage(),
                          key:'account/downloads',
                        ),
                      ),
                      ListTile(
                        leading:const Icon(Icons.offline_bolt_outlined),
                        title:Text(Api.I.ar?'الصفحات المحفوظة':'Saved pages'),
                        subtitle:Text(Api.I.ar?'كاش سريع وصفحات للاستخدام بدون إنترنت':'Fast cache and offline page access'),
                        onTap:()=>AppNavigator.open(
                          context,
                          const PageCacheSettingsPage(),
                          key:'account/page-cache',
                        ),
                      ),
                    ],
                  ),
                ),

                if(links is Map)...[
                  const SizedBox(height:14),
                  Card(
                    child:Column(
                      children:[
                        if((links['support']??'').toString().isNotEmpty)
                          ListTile(
                            leading:const Icon(Icons.support_agent_rounded),
                            title:Text(Api.I.ar?'الدعم':'Support'),
                            trailing:const Icon(Icons.open_in_new_rounded,size:18),
                            onTap:()=>launchUrl(
                              Uri.parse(links['support'].toString()),
                              mode:LaunchMode.externalApplication,
                            ),
                          ),
                        if((links['privacy']??'').toString().isNotEmpty)
                          ListTile(
                            leading:const Icon(Icons.privacy_tip_outlined),
                            title:Text(Api.I.ar?'الخصوصية':'Privacy'),
                            trailing:const Icon(Icons.open_in_new_rounded,size:18),
                            onTap:()=>launchUrl(
                              Uri.parse(links['privacy'].toString()),
                              mode:LaunchMode.externalApplication,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height:14),
                OutlinedButton.icon(
                  onPressed:() async{
                    await Api.I.logout();
                    reload();
                  },
                  icon:const Icon(Icons.logout_rounded),
                  label:Text(Api.I.ar?'تسجيل الخروج':'Logout'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class OfflineAccountPage extends StatelessWidget{
  final VoidCallback onRetry;
  const OfflineAccountPage({super.key,required this.onRetry});

  @override
  Widget build(BuildContext context){
    return ListView(
      physics:const AlwaysScrollableScrollPhysics(),
      padding:const EdgeInsets.fromLTRB(16,26,16,30),
      children:[
        const Icon(Icons.cloud_off_rounded,size:62,color:Colors.white38),
        const SizedBox(height:14),
        Text(
          Api.I.ar?'أنت تستخدم التطبيق بدون إنترنت':'You are offline',
          textAlign:TextAlign.center,
          style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900),
        ),
        const SizedBox(height:7),
        Text(
          Api.I.ar
            ?'يمكنك تشغيل المحتوى الذي تم تنزيله وفتح الصفحات المحفوظة محليًا.'
            :'You can play downloaded media and open locally cached pages.',
          textAlign:TextAlign.center,
          style:const TextStyle(color:Colors.white60,height:1.5),
        ),
        const SizedBox(height:22),
        Card(
          child:Column(
            children:[
              ListTile(
                contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
                leading:const CircleAvatar(child:Icon(Icons.download_done_rounded)),
                title:Text(
                  Api.I.ar?'الأفلام والمسلسلات المحمّلة':'Downloaded movies & series',
                  style:const TextStyle(fontWeight:FontWeight.w900),
                ),
                subtitle:Text(Api.I.ar?'تشغيل بدون إنترنت':'Play without internet'),
                trailing:const Icon(Icons.chevron_right_rounded),
                onTap:()=>AppNavigator.open(
                  context,
                  const OfflineLibraryPage(),
                  key:'account/downloads',
                ),
              ),
              const Divider(height:1),
              ListTile(
                contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
                leading:const CircleAvatar(child:Icon(Icons.offline_bolt_outlined)),
                title:Text(
                  Api.I.ar?'الصفحات المحفوظة':'Saved pages',
                  style:const TextStyle(fontWeight:FontWeight.w900),
                ),
                subtitle:Text(Api.I.ar?'المحتوى الذي سبق فتحه':'Previously opened content'),
                trailing:const Icon(Icons.chevron_right_rounded),
                onTap:()=>AppNavigator.open(
                  context,
                  const PageCacheSettingsPage(),
                  key:'account/page-cache',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height:14),
        FilledButton.icon(
          onPressed:onRetry,
          icon:const Icon(Icons.wifi_rounded),
          label:Text(Api.I.ar?'إعادة الاتصال':'Reconnect'),
        ),
      ],
    );
  }
}

class _AccountStat extends StatelessWidget{
  final IconData icon;
  final String label;
  final int? value;
  final VoidCallback onTap;

  const _AccountStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context){
    return Card(
      clipBehavior:Clip.antiAlias,
      child:InkWell(
        onTap:onTap,
        child:Padding(
          padding:const EdgeInsets.symmetric(horizontal:6,vertical:10),
          child:Column(
            mainAxisAlignment:MainAxisAlignment.center,
            children:[
              Icon(icon,size:24),
              const SizedBox(height:6),
              Text(
                value?.toString()??'—',
                style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900),
              ),
              const SizedBox(height:2),
              Text(
                label,
                maxLines:1,
                overflow:TextOverflow.ellipsis,
                textAlign:TextAlign.center,
                style:const TextStyle(fontSize:10.5,color:Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountDetailsPage extends StatelessWidget{
  final Map<String,dynamic> user;
  const AccountDetailsPage({super.key,required this.user});

  String _value(String key)=>(user[key]??'').toString().trim();

  @override
  Widget build(BuildContext context){
    final role=_value('role').isEmpty?'user':_value('role');
    final fields=<({IconData icon,String label,String value})>[
      (icon:Icons.person_outline_rounded,label:Api.I.ar?'الاسم':'Name',value:_value('name')),
      (icon:Icons.mail_outline_rounded,label:Api.I.ar?'البريد الإلكتروني':'Email',value:_value('email')),
      (icon:Icons.badge_outlined,label:Api.I.ar?'نوع الحساب':'Role',value:role),
      (icon:Icons.verified_user_outlined,label:Api.I.ar?'الحالة':'Status',value:_value('status')),
      (icon:Icons.language_rounded,label:Api.I.ar?'اللغة':'Locale',value:_value('locale')),
      (icon:Icons.login_rounded,label:Api.I.ar?'آخر دخول':'Last login',value:_value('last_login_at')),
      (icon:Icons.calendar_month_outlined,label:Api.I.ar?'تاريخ إنشاء الحساب':'Created',value:_value('created_at')),
    ].where((row)=>row.value.isNotEmpty).toList();

    return Scaffold(
      appBar:AppBar(title:Text(Api.I.ar?'تفاصيل الحساب':'Account Details')),
      body:ListView(
        padding:const EdgeInsets.fromLTRB(14,14,14,28),
        children:[
          Card(
            child:Padding(
              padding:const EdgeInsets.all(18),
              child:Column(
                children:[
                  CircleAvatar(
                    radius:42,
                    backgroundImage:_value('avatar').isEmpty
                      ?null
                      :NetworkImage(Api.I.absoluteUrl(_value('avatar'))),
                    child:_value('avatar').isEmpty
                      ?const Icon(Icons.person_rounded,size:42)
                      :null,
                  ),
                  const SizedBox(height:12),
                  Text(
                    _value('name'),
                    style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900),
                  ),
                  if(_value('email').isNotEmpty)
                    Text(_value('email'),style:const TextStyle(color:Colors.white60)),
                ],
              ),
            ),
          ),
          const SizedBox(height:12),
          Card(
            child:Column(
              children:[
                for(var i=0;i<fields.length;i++)...[
                  ListTile(
                    leading:Icon(fields[i].icon),
                    title:Text(fields[i].label),
                    subtitle:Text(fields[i].value),
                  ),
                  if(i<fields.length-1)const Divider(height:1),
                ],
              ],
            ),
          ),
          const SizedBox(height:12),
          FutureBuilder<PackageInfo>(
            future:PackageInfo.fromPlatform(),
            builder:(_,s){
              if(!s.hasData)return const SizedBox.shrink();
              return ListTile(
                leading:const Icon(Icons.android_rounded),
                title:const Text('SHORT SERIES TV'),
                subtitle:Text(
                  'v${s.data!.version} (${s.data!.buildNumber})',
                ),
              );
            },
          ),
        ],
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

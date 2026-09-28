part of 'main.dart';

class AdminStudioPage extends StatefulWidget {
  const AdminStudioPage({super.key});
  @override
  State<AdminStudioPage> createState()=>_AdminStudioPageState();
}

class _AdminStudioPageState extends State<AdminStudioPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('admin_overview');}
  Future<void> reload() async{final n=Api.I.call('admin_overview');setState(()=>future=n);await n;}
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(Api.I.ar?'استوديو الإدارة':'Admin Studio')),
    body:RefreshIndicator(
      onRefresh:reload,
      child:FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(_,s){
          if(!s.hasData){if(s.hasError)return ErrorPage(error:s.error,retry:reload);return const Center(child:CircularProgressIndicator());}
          final root=Map<String,dynamic>.from(s.data!['data'] as Map);
          final counts=Map<String,dynamic>.from(root['counts'] as Map? ?? {});
          final jobs=root['jobs'] as List? ?? const[];
          return ListView(
            padding:const EdgeInsets.all(14),
            children:[
              Text(Api.I.ar?'نظرة عامة':'Overview',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900)),
              const SizedBox(height:12),
              GridView.count(
                crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),childAspectRatio:1.8,crossAxisSpacing:10,mainAxisSpacing:10,
                children:[
                  _AdminStat(Api.I.ar?'أفلام':'Movies',counts['movies']??0,Icons.movie_outlined),
                  _AdminStat(Api.I.ar?'مسلسلات':'Series',counts['series']??0,Icons.tv_rounded),
                  _AdminStat(Api.I.ar?'حلقات':'Episodes',counts['episodes']??0,Icons.format_list_numbered),
                  _AdminStat(Api.I.ar?'قنوات':'Channels',counts['channels']??0,Icons.live_tv),
                ],
              ),
              const SizedBox(height:18),
              _AdminAction(icon:Icons.cloud_download_outlined,title:Api.I.ar?'الجلب من المصدر':'Source Importers',subtitle:Api.I.ar?'تشغيل المستوردات المفعلة على السيرفر':'Run enabled server-side importers',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const ImporterCenterPage()))),
              _AdminAction(icon:Icons.travel_explore_rounded,title:'TMDB',subtitle:Api.I.ar?'بحث واستيراد أفلام ومسلسلات ومسلسلات قصيرة وفنانين':'Search and import media & artists',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const TmdbStudioPage()))),
              _AdminAction(icon:Icons.video_library_outlined,title:Api.I.ar?'إدارة المحتوى':'Content Manager',subtitle:Api.I.ar?'المحتوى والمواسم والحلقات وسيرفرات التشغيل':'Media, seasons, episodes & playback servers',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AdminContentPage()))),
              _AdminAction(icon:Icons.live_tv_rounded,title:Api.I.ar?'إدارة القنوات':'TV Manager',subtitle:Api.I.ar?'القنوات ومصادر البث':'Channels & stream sources',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AdminChannelsPage()))),
              const SizedBox(height:20),
              Row(children:[Expanded(child:Text(Api.I.ar?'آخر عمليات الاستيراد':'Recent import jobs',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900))),Text(jobs.length.toString(),style:const TextStyle(color:Colors.white54))]),
              const SizedBox(height:8),
              ...jobs.take(15).map((raw){
                final j=Map<String,dynamic>.from(raw as Map);
                return ListTile(
                  contentPadding:EdgeInsets.zero,
                  leading:CircleAvatar(child:Icon((j['status']??'').toString().toLowerCase().contains('fail')?Icons.error_outline:Icons.sync_rounded)),
                  title:Text([(j['provider']??'').toString(),(j['entity_type']??'').toString()].where((x)=>x.isNotEmpty).join(' • ')),
                  subtitle:Text((j['message']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis),
                  trailing:Text((j['status']??'').toString()),
                );
              }),
            ],
          );
        },
      ),
    ),
  );
}

class _AdminStat extends StatelessWidget{
  final String label;final dynamic value;final IconData icon;
  const _AdminStat(this.label,this.value,this.icon);
  @override
  Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
    CircleAvatar(child:Icon(icon)),const SizedBox(width:10),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
      Text(value.toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
      Text(label,style:const TextStyle(fontSize:12,color:Colors.white60)),
    ])),
  ])));
}

class _AdminAction extends StatelessWidget{
  final IconData icon;final String title,subtitle;final VoidCallback onTap;
  const _AdminAction({required this.icon,required this.title,required this.subtitle,required this.onTap});
  @override
  Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:9),child:ListTile(
    contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:7),leading:CircleAvatar(child:Icon(icon)),
    title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_right_rounded),onTap:onTap,
  ));
}

class ImporterCenterPage extends StatefulWidget{
  const ImporterCenterPage({super.key});
  @override
  State<ImporterCenterPage> createState()=>_ImporterCenterPageState();
}
class _ImporterCenterPageState extends State<ImporterCenterPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('admin_importers');}
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(Api.I.ar?'الجلب من المصدر':'Source Importers')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(_,s){
        if(!s.hasData)return const Center(child:CircularProgressIndicator());
        final rows=s.data!['data'] as List? ?? const[];
        if(rows.isEmpty)return Center(child:Text(Api.I.ar?'لا توجد مستوردات مفعلة قابلة للتشغيل من التطبيق':'No enabled app-compatible importers'));
        return ListView.separated(
          padding:const EdgeInsets.all(12),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),
          itemBuilder:(_,i){
            final im=Map<String,dynamic>.from(rows[i] as Map);
            return Card(child:ListTile(
              contentPadding:const EdgeInsets.all(14),leading:const CircleAvatar(child:Icon(Icons.cloud_download_outlined)),
              title:Text((im['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text((im['description']??'').toString()),
              trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ImporterRunPage(importer:im))),
            ));
          },
        );
      },
    ),
  );
}

class ImporterRunPage extends StatefulWidget{
  final Map<String,dynamic> importer;
  const ImporterRunPage({super.key,required this.importer});

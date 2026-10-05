part of 'main.dart';

class AdminStudioPage extends StatefulWidget {
  final String userEmail;
  const AdminStudioPage({super.key,this.userEmail=''});
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
              _AdminAction(
                icon:Icons.dashboard_customize_rounded,
                title:Api.I.ar?'لوحة تحكم الموقع الكاملة':'Full Website Control Panel',
                subtitle:Api.I.ar?'كل أقسام إدارة الموقع كما في الويب':'All website admin sections inside the app',
                onTap:()=>AppNavigator.open(
                  context,
                  AdminWebHubPage(userEmail:widget.userEmail),
                  key:'admin/web-hub',
                ),
              ),
              _AdminAction(
                icon:Icons.campaign_outlined,
                title:Api.I.ar?'استوديو الإعلانات':'Ads Studio',
                subtitle:Api.I.ar?'الحالة والإحصائيات والتحكم بالإعلانات':'Ad status, analytics and management',
                onTap:()=>AppNavigator.open(
                  context,
                  AdminAdsSummaryPage(userEmail:widget.userEmail),
                  key:'admin/ads-summary',
                ),
              ),
              _AdminAction(
                icon:Icons.group_rounded,
                title:Api.I.ar?'المشتركون والمستخدمون':'Subscribers & Users',
                subtitle:Api.I.ar?'إدارة الحسابات والأدوار والحالة':'Manage accounts, roles and status',
                onTap:()=>AppNavigator.open(
                  context,
                  AdminWebPanelPage(
                    initialPath:'/admin/users',
                    title:Api.I.ar?'المشتركون':'Users',
                    userEmail:widget.userEmail,
                  ),
                  key:'admin/web/users',
                ),
              ),
              _AdminAction(icon:Icons.cloud_download_outlined,title:Api.I.ar?'الجلب من المصدر':'Source Importers',subtitle:Api.I.ar?'تشغيل المستوردات المفعلة على السيرفر':'Run enabled server-side importers',onTap:()=>AppNavigator.open(context,const ImportBridgePage(),key:'admin/import-bridge')),
              _AdminAction(icon:Icons.travel_explore_rounded,title:'TMDB',subtitle:Api.I.ar?'بحث واستيراد أفلام ومسلسلات ومسلسلات قصيرة وفنانين':'Search and import media & artists',onTap:()=>AppNavigator.open(context,const TmdbStudioPage(),key:'admin/tmdb')),
              _AdminAction(icon:Icons.video_library_outlined,title:Api.I.ar?'إدارة المحتوى':'Content Manager',subtitle:Api.I.ar?'المحتوى والمواسم والحلقات وسيرفرات التشغيل':'Media, seasons, episodes & playback servers',onTap:()=>AppNavigator.open(context,const AdminContentPage(),key:'admin/content')),
              _AdminAction(icon:Icons.live_tv_rounded,title:Api.I.ar?'إدارة القنوات':'TV Manager',subtitle:Api.I.ar?'القنوات ومصادر البث':'Channels & stream sources',onTap:()=>AppNavigator.open(context,const AdminChannelsPage(),key:'admin/channels')),
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

typedef AdminAdsSummaryLoader=Future<Map<String,dynamic>> Function();

class AdminAdsSummaryPage extends StatefulWidget{
  static const fullManagementPath='/admin/ads';
  final AdminAdsSummaryLoader? summaryLoader;
  final VoidCallback? onOpenFullManagement;
  final String userEmail;
  const AdminAdsSummaryPage({
    super.key,
    this.summaryLoader,
    this.onOpenFullManagement,
    this.userEmail='',
  });
  @override
  State<AdminAdsSummaryPage> createState()=>_AdminAdsSummaryPageState();
}

class _AdminAdsSummaryPageState extends State<AdminAdsSummaryPage>{
  late Future<_AdminAdsSummaryState> _future;

  @override
  void initState(){
    super.initState();
    _future=_load();
  }

  bool _bool(dynamic value,[bool fallback=false]){
    if(value is bool)return value;
    if(value is num)return value!=0;
    final text=(value??'').toString().trim().toLowerCase();
    if(const {'1','true','yes','on','enabled'}.contains(text))return true;
    if(const {'0','false','no','off','disabled'}.contains(text))return false;
    return fallback;
  }

  int _int(dynamic value){
    if(value is num)return value.toInt();
    return int.tryParse((value??'').toString())??0;
  }

  Future<_AdminAdsSummaryState> _load() async{
    try{
      final result=await (widget.summaryLoader?.call()??Api.I.call('admin_ads_summary'));
      final raw=result['data'];
      final data=raw is Map?Map<String,dynamic>.from(raw):Map<String,dynamic>.from(result);
      return _AdminAdsSummaryState(
        serverAvailable:true,
        enabled:_bool(data['enabled'],true),
        activeCampaigns:_int(data['active_campaigns']),
        impressions:_int(data['impressions_today']),
        clicks:_int(data['clicks_today']),
        errors:_int(data['errors_today']),
      );
    }catch(_){
      final raw=Api.I.config['admob'];
      final admob=raw is Map?Map<String,dynamic>.from(raw):<String,dynamic>{};
      return _AdminAdsSummaryState(
        serverAvailable:false,
        enabled:_bool(admob['enabled'],false),
        activeCampaigns:0,
        impressions:0,
        clicks:0,
        errors:0,
      );
    }
  }

  void _openFullManagement(){
    if(widget.onOpenFullManagement!=null){
      widget.onOpenFullManagement!();
      return;
    }
    AppNavigator.open(
      context,
      AdminWebPanelPage(
        initialPath:AdminAdsSummaryPage.fullManagementPath,
        title:Api.I.ar?'إدارة الإعلانات':'Ads Management',
        userEmail:widget.userEmail,
      ),
      key:'admin/web/ads',
    );
  }

  Widget _stat(String label,int value,IconData icon)=>Card(
    child:Padding(
      padding:const EdgeInsets.all(14),
      child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Icon(icon,color:Colors.white70),
          const Spacer(),
          Text(value.toString(),style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
          Text(label,style:const TextStyle(color:Colors.white60,fontSize:12)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(Api.I.ar?'استوديو الإعلانات':'Ads Studio')),
    body:FutureBuilder<_AdminAdsSummaryState>(
      future:_future,
      builder:(context,snapshot){
        if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
        final data=snapshot.data!;
        final status=data.enabled?(Api.I.ar?'مفعّل':'Enabled'):(Api.I.ar?'متوقف':'Disabled');
        return RefreshIndicator(
          onRefresh:() async{
            final next=_load();
            setState(()=>_future=next);
            await next;
          },
          child:ListView(
            physics:const AlwaysScrollableScrollPhysics(),
            padding:const EdgeInsets.fromLTRB(14,14,14,28),
            children:[
              Card(
                child:ListTile(
                  leading:CircleAvatar(child:Icon(data.enabled?Icons.check_circle_outline:Icons.pause_circle_outline)),
                  title:Text(Api.I.ar?'حالة نظام الإعلانات':'Advertising system'),
                  subtitle:Text(status),
                  trailing:Text(status,style:const TextStyle(fontWeight:FontWeight.w900)),
                ),
              ),
              if(!data.serverAvailable)
                Padding(
                  padding:const EdgeInsets.symmetric(vertical:10),
                  child:Text(
                    Api.I.ar?'واجهة Ads Studio على السيرفر لم يتم نشرها بعد.':'Ads Studio API is not deployed yet.',
                    style:const TextStyle(color:Colors.amberAccent),
                  ),
                ),
              const SizedBox(height:8),
              GridView.count(
                shrinkWrap:true,
                physics:const NeverScrollableScrollPhysics(),
                crossAxisCount:2,
                childAspectRatio:1.55,
                crossAxisSpacing:10,
                mainAxisSpacing:10,
                children:[
                  _stat(Api.I.ar?'الحملات النشطة':'Active campaigns',data.activeCampaigns,Icons.campaign_outlined),
                  _stat(Api.I.ar?'مرات الظهور اليوم':'Impressions today',data.impressions,Icons.visibility_outlined),
                  _stat(Api.I.ar?'النقرات اليوم':'Clicks today',data.clicks,Icons.ads_click_outlined),
                  _stat(Api.I.ar?'الأخطاء اليوم':'Errors today',data.errors,Icons.error_outline),
                ],
              ),
              const SizedBox(height:16),
              FilledButton.icon(
                key:const Key('open-full-ads-studio'),
                onPressed:_openFullManagement,
                icon:const Icon(Icons.open_in_new_rounded),
                label:Text(Api.I.ar?'فتح الإدارة الكاملة':'Open full Ads Studio'),
              ),
              const SizedBox(height:8),
              Text(
                Api.I.ar?'الإدارة الكاملة للحملات وVAST/VMAP والاستهداف تبقى في /admin/ads.':'Campaign, VAST/VMAP and targeting management remains canonical in /admin/ads.',
                style:const TextStyle(color:Colors.white54,fontSize:12),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _AdminAdsSummaryState{
  final bool serverAvailable;
  final bool enabled;
  final int activeCampaigns;
  final int impressions;
  final int clicks;
  final int errors;
  const _AdminAdsSummaryState({
    required this.serverAvailable,
    required this.enabled,
    required this.activeCampaigns,
    required this.impressions,
    required this.clicks,
    required this.errors,
  });
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

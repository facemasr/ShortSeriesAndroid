part of 'main.dart';

class ProImportCenterPage extends StatefulWidget {
  const ProImportCenterPage({super.key});
  @override
  State<ProImportCenterPage> createState()=>_ProImportCenterPageState();
}

class _ProImportCenterPageState extends State<ProImportCenterPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('admin_import_sources');}
  Future<void> reload() async{final n=Api.I.call('admin_import_sources');setState(()=>future=n);await n;}

  IconData _icon(String value){
    switch(value){
      case 'movie': return Icons.movie_outlined;
      case 'series': return Icons.tv_rounded;
      case 'shorts': return Icons.flash_on_rounded;
      case 'queue': return Icons.pending_actions_rounded;
      case 'search': return Icons.manage_search_rounded;
      case 'folder': return Icons.folder_outlined;
      case 'radar': return Icons.radar_rounded;
      default: return Icons.extension_rounded;
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(
      title:Text(Api.I.ar?'مركز الجلب الاحترافي':'Professional Import Center'),
      actions:[
        IconButton(
          tooltip:Api.I.ar?'تشخيص':'Diagnostics',
          onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const ImportDiagnosticsPage())),
          icon:const Icon(Icons.monitor_heart_outlined),
        ),
      ],
    ),
    body:RefreshIndicator(
      onRefresh:reload,
      child:FutureBuilder<Map<String,dynamic>>(
        future:future,
        builder:(_,s){
          if(!s.hasData){
            if(s.hasError)return ErrorPage(error:s.error,retry:reload);
            return const Center(child:CircularProgressIndicator());
          }
          final rows=s.data!['data'] as List? ?? const[];
          if(rows.isEmpty)return ListView(children:[
            SizedBox(height:MediaQuery.sizeOf(context).height*.28),
            Center(child:Text(Api.I.ar?'لم يتم اكتشاف إضافات جلب':'No import providers detected')),
          ]);
          return ListView.separated(
            padding:const EdgeInsets.all(14),
            itemCount:rows.length,
            separatorBuilder:(_,__)=>const SizedBox(height:10),
            itemBuilder:(_,i){
              final p=Map<String,dynamic>.from(rows[i] as Map);
              final enabled=p['enabled']==true;
              final acts=p['actions'] as List? ?? const[];
              return Card(
                clipBehavior:Clip.antiAlias,
                child:InkWell(
                  onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProviderControlPage(provider:p))).then((_){reload();}),
                  child:Padding(
                    padding:const EdgeInsets.all(15),
                    child:Row(
                      children:[
                        Container(
                          width:54,height:54,
                          decoration:BoxDecoration(
                            borderRadius:BorderRadius.circular(16),
                            color:enabled?Theme.of(context).colorScheme.primaryContainer:Colors.white10,
                          ),
                          child:Icon(_icon((p['icon']??'plugin').toString()),size:28),
                        ),
                        const SizedBox(width:13),
                        Expanded(
                          child:Column(
                            crossAxisAlignment:CrossAxisAlignment.start,
                            children:[
                              Row(children:[
                                Expanded(child:Text((p['title']??p['name']??'').toString(),
                                  style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16))),
                                Container(
                                  padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                                  decoration:BoxDecoration(
                                    color:enabled?const Color(0x2237D67A):const Color(0x22FF5A67),
                                    borderRadius:BorderRadius.circular(99),
                                  ),
                                  child:Text(
                                    enabled?(Api.I.ar?'مفعّل':'Enabled'):(Api.I.ar?'متوقف':'Disabled'),
                                    style:TextStyle(
                                      color:enabled?const Color(0xFF71E59E):const Color(0xFFFF8790),
                                      fontSize:11,fontWeight:FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ]),
                              const SizedBox(height:4),
                              Text(
                                (p['description']??'').toString(),
                                maxLines:2,overflow:TextOverflow.ellipsis,
                                style:const TextStyle(color:Colors.white60,fontSize:12.5,height:1.35),
                              ),
                              const SizedBox(height:8),
                              Wrap(
                                spacing:6,runSpacing:6,
                                children:[
                                  _MiniPill(acts.length.toString()+' '+(Api.I.ar?'عمليات':'actions')),
                                  if((p['version']??'').toString().isNotEmpty)_MiniPill('v'+(p['version']??'').toString()),
                                  _MiniPill((p['kind']??'source').toString()),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width:6),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class _MiniPill extends StatelessWidget{
  final String text; const _MiniPill(this.text);
  @override
  Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
    decoration:BoxDecoration(color:Colors.white10,borderRadius:BorderRadius.circular(99)),
    child:Text(text,style:const TextStyle(fontSize:10.5,color:Colors.white70,fontWeight:FontWeight.w700)),
  );
}

class ProviderControlPage extends StatefulWidget{
  final Map<String,dynamic> provider;
  const ProviderControlPage({super.key,required this.provider});
  @override
  State<ProviderControlPage> createState()=>_ProviderControlPageState();
}

class _ProviderControlPageState extends State<ProviderControlPage>{
  late Map<String,dynamic> provider;
  bool toggling=false;

  @override
  void initState(){super.initState();provider=Map<String,dynamic>.from(widget.provider);}

  Future<void> _toggle(bool enabled) async{
    setState(()=>toggling=true);
    try{
      await Api.I.call('admin_import_plugin_toggle',method:'POST',data:{
        'slug':provider['slug'],'enabled':enabled,
      });
      if(mounted)setState(()=>provider['enabled']=enabled);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    }
    if(mounted)setState(()=>toggling=false);
  }

  @override
  Widget build(BuildContext context){
    final enabled=provider['enabled']==true;
    final acts=provider['actions'] as List? ?? const[];
    final status=provider['status'];
    return Scaffold(
      appBar:AppBar(title:Text((provider['title']??provider['name']??'Source').toString())),
      body:ListView(
        padding:const EdgeInsets.all(14),
        children:[
          Card(
            child:Padding(
              padding:const EdgeInsets.all(14),
              child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Row(children:[
                    Expanded(child:Text((provider['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18))),
                    Switch.adaptive(value:enabled,onChanged:toggling?null:_toggle),
                  ]),
                  Text((provider['description']??'').toString(),style:const TextStyle(color:Colors.white60,height:1.45)),
                  if(status is Map && status.isNotEmpty)...[
                    const SizedBox(height:12),
                    _StatusSummary(data:Map<String,dynamic>.from(status)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height:12),
          Text(Api.I.ar?'العمليات المتاحة':'Available actions',
            style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
          const SizedBox(height:8),
          if(!enabled)
            Padding(
              padding:const EdgeInsets.only(bottom:10),
              child:Container(
                padding:const EdgeInsets.all(12),
                decoration:BoxDecoration(color:const Color(0x22FFB020),borderRadius:BorderRadius.circular(14)),
                child:Text(Api.I.ar?'فعّل الإضافة أولاً لتشغيل عمليات الجلب.':'Enable this plugin before running import actions.'),
              ),
            ),
          ...acts.map((raw){
            final a=Map<String,dynamic>.from(raw as Map);
            return Card(
              margin:const EdgeInsets.only(bottom:8),
              child:ListTile(
                enabled:enabled,
                leading:CircleAvatar(child:Icon(_actionIcon((a['key']??'').toString()))),
                title:Text((a['label']??a['key']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
                subtitle:Text((a['description']??'').toString()),
                trailing:const Icon(Icons.chevron_right_rounded),
                onTap:enabled?()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProviderActionPage(provider:provider,action:a))):null,
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _actionIcon(String k){
    if(k.contains('search'))return Icons.search_rounded;
    if(k.contains('scan'))return Icons.radar_rounded;
    if(k.contains('import')||k.contains('direct'))return Icons.cloud_download_rounded;
    if(k.contains('queue')||k.contains('job'))return Icons.pending_actions_rounded;
    if(k.contains('sync')||k.contains('refresh'))return Icons.sync_rounded;
    if(k.contains('inspect')||k.contains('probe')||k.contains('analyze'))return Icons.biotech_outlined;
    return Icons.play_arrow_rounded;
  }
}

class _StatusSummary extends StatelessWidget{
  final Map<String,dynamic> data; const _StatusSummary({required this.data});
  @override
  Widget build(BuildContext context){
    final items=<MapEntry<String,dynamic>>[];
    void addMap(Map m){
      for(final e in m.entries){
        if(items.length>=8)break;
        if(e.value is num || e.value is String || e.value is bool)items.add(MapEntry(e.key.toString(),e.value));
      }
    }
    final stats=data['stats'];
    if(stats is Map)addMap(stats);
    if(items.isEmpty)addMap(data);
    if(items.isEmpty)return const SizedBox.shrink();
    return Wrap(
      spacing:8,runSpacing:8,
      children:items.map((e)=>Container(
        padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
        decoration:BoxDecoration(color:Colors.white10,borderRadius:BorderRadius.circular(12)),
        child:Text(e.key+': '+e.value.toString(),style:const TextStyle(fontSize:11.5,fontWeight:FontWeight.w700)),
      )).toList(),
    );
  }
}

class ProviderActionPage extends StatefulWidget{
  final Map<String,dynamic> provider;
  final Map<String,dynamic> action;
  final Map<String,dynamic>? initial;
  const ProviderActionPage({super.key,required this.provider,required this.action,this.initial});
  @override
  State<ProviderActionPage> createState()=>_ProviderActionPageState();
}

class _ProviderActionPageState extends State<ProviderActionPage>{
  final ctrls=<String,TextEditingController>{};
  final selects=<String,String>{};
  bool running=false;
  dynamic result;
  Timer? jobTimer;
  int? activeJobId;

  @override
  void initState(){
    super.initState();
    for(final raw in widget.action['fields'] as List? ?? const[]){
      final f=Map<String,dynamic>.from(raw as Map);
      final name=(f['name']??'').toString();
      final type=(f['type']??'text').toString();
      final initial=(widget.initial?[name]??'').toString();
      if(type=='select'){
        final opts=f['options'];
        String v=initial;
        if(v.isEmpty && opts is Map && opts.isNotEmpty)v=opts.keys.first.toString();
        selects[name]=v;
      }else{
        ctrls[name]=TextEditingController(text:initial);
      }
    }
  }

  @override
  void dispose(){jobTimer?.cancel();for(final c in ctrls.values)c.dispose();super.dispose();}

  Map<String,dynamic> _payload(){
    final out=<String,dynamic>{};
    for(final e in ctrls.entries)out[e.key]=e.value.text.trim();
    out.addAll(selects);
    return out;
  }

  Future<void> run() async{
    if(running)return;
    for(final raw in widget.action['fields'] as List? ?? const[]){
      final f=Map<String,dynamic>.from(raw as Map);
      if(f['required']!=true)continue;
      final name=(f['name']??'').toString();
      final value=(f['type']=='select'?selects[name]:ctrls[name]?.text)?.trim()??'';
      if(value.isEmpty){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text((f['label']??name).toString())));
        return;
      }
    }
    setState(()=>running=true);
    try{
      final res=await Api.I.call('admin_import_action',method:'POST',data:{
        'provider':widget.provider['slug'],
        'operation':widget.action['key'],
        'input':_payload(),
      });
      final root=Map<String,dynamic>.from(res['data'] as Map);
      final r=root['result'];
      setState(()=>result=r);
      final job=_extractJobId(r);
      if(job>0){
        activeJobId=job;
        _startJobPolling(job);
      }
    }catch(e){
      setState(()=>result={'error':e.toString()});
    }
    if(mounted)setState(()=>running=false);
  }

  int _extractJobId(dynamic v){
    if(v is Map){
      final direct=int.tryParse((v['job_id']??'').toString())??0;
      if(direct>0)return direct;
      for(final x in v.values){final n=_extractJobId(x);if(n>0)return n;}
    }
    return 0;
  }

  void _startJobPolling(int id){
    jobTimer?.cancel();
    jobTimer=Timer.periodic(const Duration(seconds:3),(_)=>_pollJob(id));
    _pollJob(id);
  }

  Future<void> _pollJob(int id) async{
    if(!mounted)return;
    try{
      final res=await Api.I.call('admin_import_action',method:'POST',data:{
        'provider':'egy-ak-movie-importer',
        'operation':'job_status',
        'input':{'job_id':id},
      });
      final root=Map<String,dynamic>.from(res['data'] as Map);
      final r=root['result'];
      if(mounted)setState(()=>result=r);
      if(r is Map){
        final st=(r['status']??'').toString();
        if(['success','error','failed'].contains(st)){
          jobTimer?.cancel();
          activeJobId=null;
        }
      }
    }catch(_){}
  }

  List<Map<String,dynamic>> _searchRows(dynamic v){
    if(v is List)return v.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(v is Map){
      final rr=v['results'];
      if(rr is List)return rr.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    }
    return const[];
  }

  String _rowTitle(Map<String,dynamic> r)=>
      (r['source_title']??r['title']??r['name']??r['slug']??'Result').toString();
  String _rowUrl(Map<String,dynamic> r)=>
      (r['source_url']??r['url']??r['page_url']??'').toString();

  Map<String,dynamic>? _directAction(){
    final actions=widget.provider['actions'] as List? ?? const[];
    for(final raw in actions){
      final a=Map<String,dynamic>.from(raw as Map);
      final k=(a['key']??'').toString();
      if(['direct_import','import_url'].contains(k))return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context){
    final fields=widget.action['fields'] as List? ?? const[];
    final rows=_searchRows(result);
    final direct=_directAction();
    return Scaffold(
      appBar:AppBar(title:Text((widget.action['label']??'Action').toString())),
      body:ListView(
        padding:const EdgeInsets.all(16),
        children:[
          Text((widget.action['description']??'').toString(),style:const TextStyle(color:Colors.white70,height:1.5)),
          const SizedBox(height:14),
          ...fields.map((raw){
            final f=Map<String,dynamic>.from(raw as Map);
            final name=(f['name']??'').toString();
            final type=(f['type']??'text').toString();
            if(type=='select'){
              final opts=f['options'] is Map?Map<String,dynamic>.from(f['options'] as Map):<String,dynamic>{};
              return Padding(
                padding:const EdgeInsets.only(bottom:12),
                child:DropdownButtonFormField<String>(
                  initialValue:selects[name],
                  items:opts.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value.toString()))).toList(),
                  onChanged:(v)=>setState(()=>selects[name]=v??''),
                  decoration:InputDecoration(labelText:(f['label']??name).toString()),
                ),
              );
            }
            return Padding(
              padding:const EdgeInsets.only(bottom:12),
              child:TextField(
                controller:ctrls[name],
                minLines:type=='textarea'?5:1,maxLines:type=='textarea'?12:1,
                keyboardType:type=='number'?TextInputType.number:(type=='url'?TextInputType.url:TextInputType.text),
                decoration:InputDecoration(
                  labelText:(f['label']??name).toString(),
                  hintText:(f['placeholder']??'').toString(),
                  suffixText:f['required']==true?'*':null,
                ),
              ),
            );
          }),
          FilledButton.icon(
            onPressed:running?null:run,
            icon:running?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.play_arrow_rounded),
            label:Text(running?(Api.I.ar?'جاري التنفيذ...':'Running...'):(widget.action['label']??'Run').toString()),
          ),
          if(activeJobId!=null)...[
            const SizedBox(height:12),
            LinearProgressIndicator(borderRadius:BorderRadius.circular(99)),
            const SizedBox(height:6),
            Text((Api.I.ar?'متابعة المهمة #':'Monitoring job #')+activeJobId.toString(),
              style:const TextStyle(color:Colors.white60,fontWeight:FontWeight.w700)),
          ],
          if(rows.isNotEmpty)...[
            const SizedBox(height:20),
            Text(Api.I.ar?'نتائج المصدر':'Source results',
              style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
            const SizedBox(height:8),
            ...rows.map((r){
              final image=(r['poster']??r['image']??r['thumbnail']??'').toString();
              final url=_rowUrl(r);
              return Card(
                child:ListTile(
                  leading:SizedBox(
                    width:52,height:70,
                    child:ClipRRect(
                      borderRadius:BorderRadius.circular(8),
                      child:image.isEmpty
                        ?Container(color:Colors.white10,child:const Icon(Icons.movie_outlined))
                        :CachedNetworkImage(imageUrl:image,fit:BoxFit.cover,errorWidget:(_,__,___)=>Container(color:Colors.white10)),
                    ),
                  ),
                  title:Text(_rowTitle(r),maxLines:2,overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontWeight:FontWeight.w900)),
                  subtitle:Text([
                    (r['content_type']??r['type']??'').toString(),
                    (r['status']??'').toString(),
                    (r['smart_percent']??'').toString().isEmpty?'':((r['smart_percent']??'').toString()+'%'),
                  ].where((x)=>x.isNotEmpty).join(' • ')),
                  trailing:direct!=null&&url.isNotEmpty
                    ?IconButton(
                        tooltip:Api.I.ar?'استيراد':'Import',
                        icon:const Icon(Icons.cloud_download_rounded),
                        onPressed:()=>Navigator.push(context,MaterialPageRoute(
                          builder:(_)=>ProviderActionPage(
                            provider:widget.provider,
                            action:direct,
                            initial:{
                              'url':url,
                              'content_type':(r['content_type']??r['type']??'').toString(),
                              'tmdb_id':(r['tmdb_id']??'').toString(),
                            },
                          ),
                        )),
                      )
                    :null,
                ),
              );
            }),
          ] else if(result!=null)...[
            const SizedBox(height:18),
            _PrettyResult(data:result),
          ],
        ],
      ),
    );
  }
}

class _PrettyResult extends StatelessWidget{
  final dynamic data; const _PrettyResult({required this.data});
  @override
  Widget build(BuildContext context){
    if(data is Map){
      final m=Map<String,dynamic>.from(data as Map);
      final status=(m['status']??(m['ok']==true?'success':'')).toString();
      final message=(m['message']??m['last_error']??'').toString();
      return Card(
        child:Padding(
          padding:const EdgeInsets.all(14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Icon(status.contains('error')||status.contains('fail')?Icons.error_outline:Icons.check_circle_outline),
              const SizedBox(width:8),
              Expanded(child:Text(status.isEmpty?(Api.I.ar?'النتيجة':'Result'):status,
                style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16))),
            ]),
            if(message.isNotEmpty)...[const SizedBox(height:8),Text(message)],
            const SizedBox(height:10),
            SelectableText(const JsonEncoder.withIndent('  ').convert(m),
              style:const TextStyle(fontFamily:'monospace',fontSize:11,color:Colors.white60)),
          ]),
        ),
      );
    }
    return Card(child:Padding(padding:const EdgeInsets.all(14),child:SelectableText(data.toString())));
  }
}

class ImportDiagnosticsPage extends StatefulWidget{
  const ImportDiagnosticsPage({super.key});
  @override
  State<ImportDiagnosticsPage> createState()=>_ImportDiagnosticsPageState();
}
class _ImportDiagnosticsPageState extends State<ImportDiagnosticsPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('admin_import_diagnostics');}
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(Api.I.ar?'تشخيص الجلب':'Import diagnostics')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(_,s){
        if(!s.hasData)return const Center(child:CircularProgressIndicator());
        final root=Map<String,dynamic>.from(s.data!['data'] as Map);
        final plugins=root['plugins'] as List? ?? const[];
        return ListView(
          padding:const EdgeInsets.all(14),
          children:[
            Card(child:Padding(padding:const EdgeInsets.all(14),child:Wrap(
              spacing:8,runSpacing:8,
              children:[
                _DiagChip('PHP '+(root['php']??'').toString()),
                _DiagChip('cURL '+(root['curl']==true?'✓':'✗')),
                _DiagChip('mbstring '+(root['mbstring']==true?'✓':'✗')),
                _DiagChip('ZIP '+(root['zip']==true?'✓':'✗')),
              ],
            ))),
            const SizedBox(height:12),
            Text(Api.I.ar?'الإضافات المكتشفة':'Detected plugins',
              style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
            const SizedBox(height:8),
            ...plugins.map((raw){
              final p=Map<String,dynamic>.from(raw as Map);
              final enabled=p['enabled']==true;
              return ListTile(
                leading:Icon(enabled?Icons.check_circle:Icons.pause_circle_outline,
                  color:enabled?const Color(0xFF71E59E):Colors.white38),
                title:Text((p['name']??p['slug']??'').toString()),
                subtitle:Text((p['slug']??'').toString()+' • v'+(p['version']??'').toString()),
                trailing:Text(enabled?(Api.I.ar?'مفعّل':'ON'):(Api.I.ar?'متوقف':'OFF')),
              );
            }),
          ],
        );
      },
    ),
  );
}

class _DiagChip extends StatelessWidget{
  final String text; const _DiagChip(this.text);
  @override
  Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
    decoration:BoxDecoration(color:Colors.white10,borderRadius:BorderRadius.circular(12)),
    child:Text(text,style:const TextStyle(fontWeight:FontWeight.w800)),
  );
}

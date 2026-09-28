part of 'main.dart';

class ImportBridgePage extends StatefulWidget {
  const ImportBridgePage({super.key});
  @override
  State<ImportBridgePage> createState()=>_ImportBridgePageState();
}

class _ImportBridgePageState extends State<ImportBridgePage>{
  late Future<Map<String,dynamic>> future;
  bool busy=false;
  @override
  void initState(){super.initState();future=Api.I.call('admin_import_sources');}
  Future<void> reload() async{final n=Api.I.call('admin_import_sources');setState(()=>future=n);await n;}
  Future<void> toggle(Map<String,dynamic> p) async{
    if(busy)return;setState(()=>busy=true);
    try{
      await Api.I.call('admin_import_plugin_toggle',method:'POST',data:{'slug':p['slug'],'enabled':p['enabled']!=true});
      await reload();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>busy=false);
  }
  Future<void> diagnostics() async{
    try{
      final r=await Api.I.call('admin_import_diagnostics');
      if(!mounted)return;
      await showModalBottomSheet<void>(
        context:context,isScrollControlled:true,showDragHandle:true,
        backgroundColor:const Color(0xFF101114),
        builder:(_)=>_BridgeResult(title:Api.I.ar?'تشخيص الجلب':'Import diagnostics',result:r['data']),
      );
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  IconData icon(String k)=>switch(k){
    'movie'=>Icons.movie_outlined,'series'=>Icons.video_library_outlined,
    'short_series'=>Icons.bolt_rounded,'movie_series'=>Icons.ondemand_video_rounded,
    'resolver'=>Icons.radar_rounded,'folder'=>Icons.folder_copy_outlined,
    _=>Icons.extension_rounded,
  };
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFF050505),
    appBar:AppBar(
      backgroundColor:const Color(0xFF050505),surfaceTintColor:Colors.transparent,
      title:Text(Api.I.ar?'مركز الجلب الاحترافي':'Professional Import Center',style:const TextStyle(fontWeight:FontWeight.w900)),
      actions:[
        IconButton(onPressed:diagnostics,icon:const Icon(Icons.health_and_safety_outlined)),
        IconButton(onPressed:reload,icon:const Icon(Icons.refresh_rounded)),
      ],
    ),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(_,s){
        if(!s.hasData){if(s.hasError)return ErrorPage(error:s.error,retry:reload);return const Center(child:CircularProgressIndicator());}
        final rows=(s.data!['data'] as List? ?? const[]).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
        return RefreshIndicator(
          onRefresh:reload,
          child:ListView(
            padding:const EdgeInsets.fromLTRB(14,10,14,28),
            children:[
              Container(
                padding:const EdgeInsets.all(17),
                decoration:BoxDecoration(
                  gradient:const LinearGradient(colors:[Color(0xFF2B1016),Color(0xFF111214)]),
                  borderRadius:BorderRadius.circular(22),border:Border.all(color:const Color(0x33E50914)),
                ),
                child:Row(children:[
                  const CircleAvatar(radius:25,backgroundColor:Color(0x22E50914),child:Icon(Icons.cloud_sync_rounded,color:Color(0xFFE50914))),
                  const SizedBox(width:12),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(Api.I.ar?'الجلب حسب قدرات كل مصدر':'Source-aware importing',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18)),
                    const SizedBox(height:4),
                    Text(Api.I.ar?'بحث، فحص، فهرسة، Queue، Sync وتحديث المصادر حسب ما تدعمه الإضافة فعلياً.':'Search, inspect, scan, queue, sync and refresh based on each plugin capability.',style:const TextStyle(color:Colors.white60,height:1.4,fontSize:12)),
                  ])),
                ]),
              ),
              const SizedBox(height:16),
              ...rows.map((p){
                final enabled=p['enabled']==true;
                final actions=p['actions'] as List? ?? const[];
                final status=p['status'];
                return Card(
                  color:const Color(0xFF111214),margin:const EdgeInsets.only(bottom:11),
                  clipBehavior:Clip.antiAlias,
                  child:Padding(
                    padding:const EdgeInsets.all(15),
                    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Row(children:[
                        Container(width:50,height:50,decoration:BoxDecoration(color:enabled?const Color(0x22E50914):Colors.white10,borderRadius:BorderRadius.circular(15)),child:Icon(icon((p['kind']??'').toString()),color:enabled?const Color(0xFFE50914):Colors.white54)),
                        const SizedBox(width:11),
                        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                          Text((p['title']??p['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),
                          Text('v'+(p['version']??'').toString(),style:const TextStyle(color:Colors.white54,fontSize:11)),
                        ])),
                        _BridgePill(enabled:enabled),
                      ]),
                      const SizedBox(height:10),
                      Text((p['description']??'').toString(),maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white70,height:1.45,fontSize:12.5)),
                      const SizedBox(height:10),
                      Wrap(spacing:6,runSpacing:6,children:[
                        ...actions.take(5).map((a)=>_BridgeChip(label:(a is Map?a['label']:a).toString())),
                        if(actions.length>5)_BridgeChip(label:'+'+(actions.length-5).toString()),
                      ]),
                      if(enabled&&status is Map&&status.isNotEmpty)...[
                        const SizedBox(height:10),
                        _BridgeStatus(status:Map<String,dynamic>.from(status)),
                      ],
                      const SizedBox(height:12),
                      SizedBox(
                        width:double.infinity,
                        child:enabled
                          ?FilledButton.icon(
                              onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ImportProviderPage(provider:p))).then((_)=>reload()),
                              icon:const Icon(Icons.dashboard_customize_outlined),
                              label:Text(Api.I.ar?'فتح أدوات المصدر':'Open source tools'),
                            )
                          :FilledButton.icon(
                              onPressed:busy?null:()=>toggle(p),
                              icon:const Icon(Icons.power_settings_new_rounded),
                              label:Text(Api.I.ar?'تفعيل الإضافة':'Enable plugin'),
                            ),
                      ),
                    ]),
                  ),
                );
              }),
            ],
          ),
        );
      },
    ),
  );
}

class ImportProviderPage extends StatefulWidget{
  final Map<String,dynamic> provider;
  const ImportProviderPage({super.key,required this.provider});
  @override
  State<ImportProviderPage> createState()=>_ImportProviderPageState();
}
class _ImportProviderPageState extends State<ImportProviderPage>{
  Map<String,dynamic>? status;
  bool refreshing=false;
  @override
  void initState(){super.initState();final s=widget.provider['status'];if(s is Map)status=Map<String,dynamic>.from(s);}
  Future<void> refreshStatus() async{
    setState(()=>refreshing=true);
    try{
      final r=await Api.I.call('admin_import_action',method:'POST',data:{'provider':widget.provider['slug'],'operation':'status','input':const{}});
      final x=(r['data'] as Map?)?['result'];if(x is Map&&mounted)setState(()=>status=Map<String,dynamic>.from(x));
    }catch(_){}
    if(mounted)setState(()=>refreshing=false);
  }
  Future<void> run(Map<String,dynamic> a,{Map<String,dynamic>? initial}) async{
    final fields=(a['fields'] as List? ?? const[]).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    Map<String,dynamic>? input;
    if(fields.isEmpty){
      final yes=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(
        title:Text((a['label']??'').toString()),content:Text((a['description']??'').toString()),
        actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(Api.I.ar?'إلغاء':'Cancel')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:Text(Api.I.ar?'تنفيذ':'Run'))],
      ));
      if(yes!=true)return;input={};
    }else{
      input=await showModalBottomSheet<Map<String,dynamic>>(
        context:context,isScrollControlled:true,showDragHandle:true,backgroundColor:const Color(0xFF101114),
        builder:(_)=>_BridgeForm(action:a,initial:initial??const{}),
      );
      if(input==null)return;
    }
    if(!mounted)return;
    showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>const Center(child:CircularProgressIndicator()));
    try{
      final r=await Api.I.call('admin_import_action',method:'POST',data:{'provider':widget.provider['slug'],'operation':a['key'],'input':input});
      if(mounted)Navigator.pop(context);
      final result=(r['data'] as Map?)?['result'];
      if(!mounted)return;
      await showModalBottomSheet<void>(
        context:context,isScrollControlled:true,showDragHandle:true,backgroundColor:const Color(0xFF101114),
        builder:(_)=>_BridgeResult(
          title:(a['label']??'').toString(),result:result,
          onUseUrl:(url){Navigator.pop(context);final direct=_directAction();if(direct!=null)run(direct,initial:{'url':url});},
          onJob:(id,process){Navigator.pop(context);run({'key':process?'process_job':'job_status','label':process?(Api.I.ar?'تشغيل المهمة':'Run job'):(Api.I.ar?'حالة المهمة':'Job status'),'description':'','fields':[{'name':'job_id','label':'Job ID','type':'number','required':true}]},initial:{'job_id':id.toString()});},
        ),
      );
      await refreshStatus();
    }catch(e){
      if(mounted)Navigator.pop(context);
      if(mounted)showDialog<void>(context:context,builder:(d)=>AlertDialog(title:Text(Api.I.ar?'فشل التنفيذ':'Action failed'),content:SelectableText(e.toString()),actions:[FilledButton(onPressed:()=>Navigator.pop(d),child:Text(Api.I.ar?'إغلاق':'Close'))]));
    }
  }
  Map<String,dynamic>? _directAction(){
    final list=(widget.provider['actions'] as List? ?? const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    for(final k in ['direct_import','import_url']){for(final a in list)if(a['key']==k)return a;}return null;
  }
  IconData opIcon(String k){
    if(k.contains('search'))return Icons.search_rounded;
    if(k.contains('scan'))return Icons.radar_rounded;
    if(k.contains('queue'))return Icons.playlist_add_check_circle_outlined;
    if(k.contains('sync')||k.contains('refresh'))return Icons.sync_rounded;
    if(k.contains('job')||k.contains('status'))return Icons.fact_check_outlined;
    if(k.contains('analyze')||k.contains('probe'))return Icons.biotech_outlined;
    return Icons.cloud_download_outlined;
  }
  @override
  Widget build(BuildContext context){
    final actions=(widget.provider['actions'] as List? ?? const[]).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    return Scaffold(
      backgroundColor:const Color(0xFF050505),
      appBar:AppBar(
        backgroundColor:const Color(0xFF050505),surfaceTintColor:Colors.transparent,
        title:Text((widget.provider['title']??widget.provider['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
        actions:[IconButton(onPressed:refreshing?null:refreshStatus,icon:refreshing?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.refresh_rounded))],
      ),
      body:ListView(padding:const EdgeInsets.fromLTRB(14,8,14,28),children:[
        Text((widget.provider['description']??'').toString(),style:const TextStyle(color:Colors.white70,height:1.5)),
        if(status!=null&&status!.isNotEmpty)...[const SizedBox(height:14),_BridgeStatus(status:status!)],
        const SizedBox(height:18),
        Text(Api.I.ar?'العمليات المتاحة':'Available operations',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
        const SizedBox(height:9),
        ...actions.map((a)=>Card(
          color:const Color(0xFF111214),margin:const EdgeInsets.only(bottom:8),
          child:ListTile(
            contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:7),
            leading:CircleAvatar(backgroundColor:const Color(0x22E50914),child:Icon(opIcon((a['key']??'').toString()),color:const Color(0xFFE50914))),
            title:Text((a['label']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
            subtitle:Text((a['description']??'').toString(),maxLines:3,overflow:TextOverflow.ellipsis),
            trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>run(a),
          ),
        )),
      ]),
    );
  }
}

class _BridgeForm extends StatefulWidget{
  final Map<String,dynamic> action,initial;
  const _BridgeForm({required this.action,required this.initial});
  @override
  State<_BridgeForm> createState()=>_BridgeFormState();
}
class _BridgeFormState extends State<_BridgeForm>{
  final controllers=<String,TextEditingController>{};
  final selects=<String,String>{};
  @override
  void initState(){
    super.initState();
    for(final raw in widget.action['fields'] as List? ?? const[]){
      final f=Map<String,dynamic>.from(raw as Map);final n=(f['name']??'').toString();final t=(f['type']??'text').toString();
      final init=(widget.initial[n]??'').toString();
      if(t=='select'){
        final o=f['options'];var v=init;
        if(o is Map&&(!o.containsKey(v)||v.isEmpty))v=o.keys.isNotEmpty?o.keys.first.toString():'';
        selects[n]=v;
      }else controllers[n]=TextEditingController(text:init);
    }
  }
  @override
  void dispose(){for(final c in controllers.values)c.dispose();super.dispose();}
  void submit(){
    final out=<String,dynamic>{};
    for(final raw in widget.action['fields'] as List? ?? const[]){
      final f=Map<String,dynamic>.from(raw as Map);final n=(f['name']??'').toString();final t=(f['type']??'text').toString();
      final v=t=='select'?(selects[n]??''):(controllers[n]?.text.trim()??'');
      if(f['required']==true&&v.isEmpty){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text((f['label']??n).toString())));return;}
      out[n]=v;
    }
    Navigator.pop(context,out);
  }
  @override
  Widget build(BuildContext context){
    final fields=(widget.action['fields'] as List? ?? const[]).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    return SafeArea(child:Padding(
      padding:EdgeInsets.fromLTRB(16,0,16,MediaQuery.of(context).viewInsets.bottom+18),
      child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text((widget.action['label']??'').toString(),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),
        const SizedBox(height:4),Text((widget.action['description']??'').toString(),style:const TextStyle(color:Colors.white60)),
        const SizedBox(height:15),
        ...fields.map((f){
          final n=(f['name']??'').toString();final t=(f['type']??'text').toString();final o=f['options'];
          if(t=='select'&&o is Map)return Padding(
            padding:const EdgeInsets.only(bottom:10),
            child:DropdownButtonFormField<String>(
              initialValue:(selects[n]??'').isEmpty?null:selects[n],
              items:o.entries.map((e)=>DropdownMenuItem(value:e.key.toString(),child:Text(e.value.toString()))).toList(),
              onChanged:(v)=>setState(()=>selects[n]=v??''),
              decoration:InputDecoration(labelText:(f['label']??n).toString()),
            ),
          );
          return Padding(
            padding:const EdgeInsets.only(bottom:10),
            child:TextField(
              controller:controllers[n],minLines:t=='textarea'?4:1,maxLines:t=='textarea'?10:1,
              keyboardType:t=='number'?TextInputType.number:(t=='url'?TextInputType.url:TextInputType.text),
              decoration:InputDecoration(labelText:(f['label']??n).toString(),hintText:(f['placeholder']??'').toString(),suffixText:f['required']==true?'*':null),
            ),
          );
        }),
        FilledButton.icon(onPressed:submit,icon:const Icon(Icons.play_arrow_rounded),label:Text(Api.I.ar?'تنفيذ العملية':'Run operation')),
      ])),
    ));
  }
}

class _BridgeResult extends StatelessWidget{
  final String title;final dynamic result;final void Function(String)? onUseUrl;final void Function(int,bool)? onJob;
  const _BridgeResult({required this.title,required this.result,this.onUseUrl,this.onJob});
  List<dynamic> rows(){
    if(result is List)return result as List;
    if(result is Map){
      final m=result as Map;
      if(m['results'] is List)return m['results'] as List;
      if(m['items'] is List)return m['items'] as List;
      if(m['jobs'] is List)return m['jobs'] as List;
    }
    return const[];
  }
  @override
  Widget build(BuildContext context){
    final m=result is Map?Map<String,dynamic>.from(result as Map):<String,dynamic>{};
    final jobId=(m['job_id'] as num?)?.toInt()??int.tryParse((m['job_id']??'').toString())??0;
    final worker=m['worker_started']==true;final list=rows();
    return SafeArea(child:DraggableScrollableSheet(
      expand:false,minChildSize:.35,initialChildSize:.72,maxChildSize:.94,
      builder:(_,sc)=>ListView(controller:sc,padding:const EdgeInsets.fromLTRB(16,0,16,26),children:[
        Text(title,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),
        if(jobId>0)...[
          const SizedBox(height:10),
          Card(color:const Color(0xFF18191D),child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Job #'+jobId.toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),
            const SizedBox(height:4),
            Text(worker?(Api.I.ar?'Worker بدأ على السيرفر.':'Server worker started.'):(Api.I.ar?'المهمة في Queue ولم يبدأ Worker مستقل.':'Job is queued and no standalone worker started.'),style:const TextStyle(color:Colors.white70)),
            const SizedBox(height:9),
            Row(children:[
              Expanded(child:OutlinedButton.icon(onPressed:onJob==null?null:()=>onJob!(jobId,false),icon:const Icon(Icons.fact_check_outlined),label:Text(Api.I.ar?'الحالة':'Status'))),
              if(!worker)...[const SizedBox(width:7),Expanded(child:FilledButton.icon(onPressed:onJob==null?null:()=>onJob!(jobId,true),icon:const Icon(Icons.play_arrow_rounded),label:Text(Api.I.ar?'تشغيل الآن':'Run now')))],
            ]),
          ]))),
        ],
        if(list.isNotEmpty)...[
          const SizedBox(height:13),
          Text(Api.I.ar?'النتائج':'Results',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18)),
          const SizedBox(height:7),
          ...list.take(50).map((raw){
            if(raw is! Map)return ListTile(title:Text(raw.toString()));
            final r=Map<String,dynamic>.from(raw);final label=(r['title']??r['name']??r['source_title']??r['url']??r['id']??'').toString();
            final url=(r['url']??r['source_url']??'').toString();
            final sub=[r['type'],r['year'],r['status'],r['message']].where((e)=>e!=null&&e.toString().isNotEmpty).map((e)=>e.toString()).join(' • ');
            return Card(child:ListTile(
              title:Text(label,maxLines:2,overflow:TextOverflow.ellipsis),
              subtitle:Text(sub.isNotEmpty?sub:url,maxLines:2,overflow:TextOverflow.ellipsis),
              trailing:url.isNotEmpty&&onUseUrl!=null?IconButton(onPressed:()=>onUseUrl!(url),icon:const Icon(Icons.arrow_circle_down_rounded)):null,
            ));
          }),
        ],
        const SizedBox(height:12),
        ExpansionTile(
          tilePadding:EdgeInsets.zero,title:Text(Api.I.ar?'البيانات التقنية':'Technical data',style:const TextStyle(fontWeight:FontWeight.w800)),
          children:[Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFF090A0C),borderRadius:BorderRadius.circular(12)),child:SelectableText(const JsonEncoder.withIndent('  ').convert(result),style:const TextStyle(fontFamily:'monospace',fontSize:11)))],
        ),
      ]),
    ));
  }
}

class _BridgePill extends StatelessWidget{
  final bool enabled;const _BridgePill({required this.enabled});
  @override
  Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),
    decoration:BoxDecoration(color:enabled?const Color(0x2234C759):const Color(0x22FF453A),borderRadius:BorderRadius.circular(99)),
    child:Text(enabled?(Api.I.ar?'مفعّل':'Enabled'):(Api.I.ar?'متوقف':'Disabled'),style:TextStyle(color:enabled?const Color(0xFF6CE58B):const Color(0xFFFF716A),fontSize:11,fontWeight:FontWeight.w800)),
  );
}
class _BridgeChip extends StatelessWidget{
  final String label;const _BridgeChip({required this.label});
  @override
  Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:Colors.white10,borderRadius:BorderRadius.circular(99)),child:Text(label,style:const TextStyle(color:Colors.white70,fontSize:10,fontWeight:FontWeight.w700)));
}
class _BridgeStatus extends StatelessWidget{
  final Map<String,dynamic> status;const _BridgeStatus({required this.status});
  @override
  Widget build(BuildContext context){
    final stats=status['stats'];if(stats is! Map||stats.isEmpty){final e=(status['error']??'').toString();return e.isEmpty?const SizedBox.shrink():Text(e,style:const TextStyle(color:Colors.orangeAccent,fontSize:11));}
    return Wrap(spacing:9,runSpacing:5,children:stats.entries.where((e)=>e.value is num||e.value is String).take(6).map((e)=>Text(e.key.toString()+': '+e.value.toString(),style:const TextStyle(color:Colors.white54,fontSize:10.5))).toList());
  }
}

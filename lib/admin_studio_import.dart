part of 'main.dart';

class ImporterRunPage extends StatefulWidget{
  final Map<String,dynamic> importer;
  const ImporterRunPage({super.key,required this.importer});
  @override
  State<ImporterRunPage> createState()=>_ImporterRunPageState();
}
class _ImporterRunPageState extends State<ImporterRunPage>{
  final controllers=<String,TextEditingController>{};bool running=false;String result='';
  @override
  void initState(){super.initState();for(final raw in widget.importer['fields'] as List? ?? const[]){final f=Map<String,dynamic>.from(raw as Map);controllers[(f['name']??'').toString()]=TextEditingController();}}
  @override
  void dispose(){for(final c in controllers.values)c.dispose();super.dispose();}
  Future<void> run() async{
    if(running)return;final fields=widget.importer['fields'] as List? ?? const[];
    for(final raw in fields){final f=Map<String,dynamic>.from(raw as Map);final name=(f['name']??'').toString();if(f['required']==true&&(controllers[name]?.text.trim().isEmpty??true)){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text((f['label']??name).toString())));return;}}
    setState((){running=true;result='';});
    try{
      final payload=<String,dynamic>{};for(final e in controllers.entries)payload[e.key]=e.value.text.trim();
      final res=await Api.I.call('admin_importer_run',method:'POST',data:{'slug':widget.importer['slug'],'input':payload});
      final data=Map<String,dynamic>.from(res['data'] as Map);setState(()=>result=(data['result']??'OK').toString());
    }catch(e){setState(()=>result=e.toString());}
    if(mounted)setState(()=>running=false);
  }
  @override
  Widget build(BuildContext context){
    final fields=widget.importer['fields'] as List? ?? const[];
    return Scaffold(
      appBar:AppBar(title:Text((widget.importer['name']??'Importer').toString())),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Text((widget.importer['description']??'').toString(),style:const TextStyle(color:Colors.white70,height:1.5)),const SizedBox(height:16),
        ...fields.map((raw){final f=Map<String,dynamic>.from(raw as Map);final name=(f['name']??'').toString();final type=(f['type']??'text').toString();return Padding(
          padding:const EdgeInsets.only(bottom:12),child:TextField(controller:controllers[name],minLines:type=='textarea'?5:1,maxLines:type=='textarea'?12:1,
            keyboardType:type=='number'?TextInputType.number:(type=='url'?TextInputType.url:TextInputType.text),
            decoration:InputDecoration(labelText:(f['label']??name).toString(),hintText:(f['placeholder']??'').toString(),suffixText:f['required']==true?'*':null)),
        );}),
        FilledButton.icon(onPressed:running?null:run,icon:running?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.cloud_download_rounded),label:Text(running?(Api.I.ar?'جاري الجلب...':'Importing...'):(Api.I.ar?'ابدأ الجلب / التحديث':'Run importer'))),
        if(result.isNotEmpty)...[const SizedBox(height:16),SelectableText(result,style:const TextStyle(fontFamily:'monospace'))],
      ]),
    );
  }
}

class TmdbStudioPage extends StatefulWidget{
  const TmdbStudioPage({super.key});
  @override
  State<TmdbStudioPage> createState()=>_TmdbStudioPageState();
}
class _TmdbStudioPageState extends State<TmdbStudioPage>{
  final q=TextEditingController();String kind='multi';Future<Map<String,dynamic>>? future;bool importing=false;
  @override
  void dispose(){q.dispose();super.dispose();}
  void search(){if(q.text.trim().isEmpty)return;setState(()=>future=Api.I.call('admin_tmdb_search',query:{'q':q.text.trim(),'kind':kind}));}
  Future<void> import(Map<String,dynamic> row,{bool short=false}) async{
    setState(()=>importing=true);
    try{
      var k=(row['media_type']??kind).toString();if(k=='multi')k=row.containsKey('title')?'movie':'tv';
      await Api.I.call('admin_tmdb_import',method:'POST',data:{'kind':k,'tmdb_id':row['id'],'short_series':short,'translations':true,'seasons':k=='tv','episode_translations':false,'people_details':true});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(Api.I.ar?'تم الاستيراد بنجاح':'Imported successfully')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>importing=false);
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('TMDB Studio')),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        SegmentedButton<String>(segments:const[ButtonSegment(value:'multi',label:Text('All')),ButtonSegment(value:'movie',label:Text('Movie')),ButtonSegment(value:'tv',label:Text('TV')),ButtonSegment(value:'person',label:Text('Person'))],selected:{kind},onSelectionChanged:(s)=>setState(()=>kind=s.first)),
        const SizedBox(height:10),
        SearchBar(controller:q,leading:const Icon(Icons.search),hintText:Api.I.ar?'اسم الفيلم أو المسلسل أو الفنان':'Movie, series or artist',onSubmitted:(_)=>search(),trailing:[IconButton(onPressed:search,icon:const Icon(Icons.arrow_forward_rounded))]),
      ])),
      Expanded(child:future==null?const Center(child:Icon(Icons.travel_explore_rounded,size:70,color:Colors.white24)):FutureBuilder<Map<String,dynamic>>(
        future:future,builder:(_,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!['data'] as List? ?? const[];
          return ListView.separated(padding:const EdgeInsets.all(12),itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(_,i){
            final row=Map<String,dynamic>.from(rows[i] as Map);final type=(row['media_type']??(row.containsKey('title')?'movie':'tv')).toString();final title=(row['title']??row['name']??'').toString();
            final poster=(row['poster_path']??row['profile_path']??'').toString();final img=poster.isEmpty?'':'https://image.tmdb.org/t/p/w185'+poster;
            return ListTile(
              leading:SizedBox(width:48,height:68,child:CachedNetworkImage(imageUrl:img,fit:BoxFit.cover,errorWidget:(_,__,___)=>const Icon(Icons.image_not_supported_outlined))),
              title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text([type,(row['release_date']??row['first_air_date']??'').toString()].where((x)=>x.isNotEmpty).join(' • ')),
              trailing:PopupMenuButton<String>(enabled:!importing,onSelected:(v){if(v=='import')import(row);if(v=='short')import(row,short:true);},itemBuilder:(_)=>[
                PopupMenuItem(value:'import',child:Text(Api.I.ar?'استيراد':'Import')),if(type=='tv')PopupMenuItem(value:'short',child:Text(Api.I.ar?'استيراد كمسلسل قصير':'Import as Short Series')),
              ]),
            );
          });
        },
      )),
    ]),
  );
}

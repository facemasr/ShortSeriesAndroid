part of 'main.dart';

class AdminContentPage extends StatefulWidget{
  const AdminContentPage({super.key});
  @override
  State<AdminContentPage> createState()=>_AdminContentPageState();
}
class _AdminContentPageState extends State<AdminContentPage>{
  final q=TextEditingController();String type='';Future<Map<String,dynamic>>? future;
  @override
  void initState(){super.initState();load();}
  @override
  void dispose(){q.dispose();super.dispose();}
  void load()=>setState(()=>future=Api.I.call('admin_content',query:{'q':q.text.trim(),'type':type,'limit':50}));
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(Api.I.ar?'إدارة المحتوى':'Content Manager')),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        SearchBar(controller:q,leading:const Icon(Icons.search),onSubmitted:(_)=>load(),hintText:Api.I.ar?'بحث بالاسم أو slug':'Title or slug'),const SizedBox(height:8),
        SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[for(final x in <String>['','movie','series','short_series'])Padding(
          padding:const EdgeInsetsDirectional.only(end:7),child:ChoiceChip(selected:type==x,label:Text(x.isEmpty?(Api.I.ar?'الكل':'All'):x),onSelected:(_){type=x;load();}),
        )])),
      ])),
      Expanded(child:FutureBuilder<Map<String,dynamic>>(
        future:future,builder:(_,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!['data'] as List? ?? const[];
          return ListView.separated(padding:const EdgeInsets.fromLTRB(12,0,12,20),itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(_,i){
            final m=Map<String,dynamic>.from(rows[i] as Map);
            final subtitle=(m['type']??'').toString()+' • '+(m['source_count']??0).toString()+' servers • ID '+(m['id']??0).toString();
            return ListTile(
              leading:SizedBox(width:48,height:68,child:CachedNetworkImage(imageUrl:(m['poster']??'').toString(),fit:BoxFit.cover,errorWidget:(_,__,___)=>const Icon(Icons.movie_outlined))),
              title:Text((m['title']??m['original_title']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_right_rounded),
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>AdminMediaPage(id:(m['id'] as num).toInt()))),
            );
          });
        },
      )),
    ]),
  );
}

class AdminMediaPage extends StatefulWidget{
  final int id;const AdminMediaPage({super.key,required this.id});
  @override
  State<AdminMediaPage> createState()=>_AdminMediaPageState();
}
class _AdminMediaPageState extends State<AdminMediaPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();future=Api.I.call('admin_media',query:{'id':widget.id});}
  void reload()=>setState(()=>future=Api.I.call('admin_media',query:{'id':widget.id}));
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(Api.I.ar?'تفاصيل المحتوى':'Content details')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,builder:(_,s){
        if(!s.hasData)return const Center(child:CircularProgressIndicator());final root=Map<String,dynamic>.from(s.data!['data'] as Map);final media=Map<String,dynamic>.from(root['media'] as Map);final seasons=root['seasons'] as List? ?? const[];final sources=root['sources'] as List? ?? const[];
        return ListView(padding:const EdgeInsets.all(14),children:[
          Text((media['title']??media['original_title']??'').toString(),style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900)),
          Text((media['type']??'').toString()+' • ID '+(media['id']??0).toString(),style:const TextStyle(color:Colors.white54)),const SizedBox(height:12),
          FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SourceManagerPage(ownerType:'media',ownerId:widget.id,title:(media['title']??media['original_title']??'').toString()))).then((_){reload();}),icon:const Icon(Icons.dns_outlined),label:Text((Api.I.ar?'سيرفرات المحتوى':'Media servers')+' ('+sources.length.toString()+')')),
          const SizedBox(height:16),
          ...seasons.map((raw){final season=Map<String,dynamic>.from(raw as Map);final eps=season['episodes'] as List? ?? const[];return Card(child:ExpansionTile(
            title:Text((Api.I.ar?'الموسم ':'Season ')+season['season_number'].toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
            children:eps.map((rawEp){final ep=Map<String,dynamic>.from(rawEp as Map);final sub=(ep['source_count']??0).toString()+' servers • ID '+(ep['id']??0).toString();return ListTile(
              title:Text(ep['episode_number'].toString()+'. '+(ep['title']??'').toString()),subtitle:Text(sub),trailing:const Icon(Icons.dns_outlined),
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SourceManagerPage(ownerType:'episode',ownerId:(ep['id'] as num).toInt(),title:(ep['title']??'').toString()))).then((_){reload();}),
            );}).toList(),
          ));}),
        ]);
      },
    ),
  );
}

class SourceManagerPage extends StatefulWidget{
  final String ownerType;final int ownerId;final String title;
  const SourceManagerPage({super.key,required this.ownerType,required this.ownerId,required this.title});
  @override
  State<SourceManagerPage> createState()=>_SourceManagerPageState();
}
class _SourceManagerPageState extends State<SourceManagerPage>{
  late Future<Map<String,dynamic>> future;
  @override
  void initState(){super.initState();load();}
  void load()=>setState(()=>future=Api.I.call('admin_sources',query:{'owner_type':widget.ownerType,'owner_id':widget.ownerId}));
  Future<void> edit([Map<String,dynamic>? source]) async{
    final label=TextEditingController(text:(source?['label']??'Server').toString());final url=TextEditingController(text:(source?['url']??'').toString());final quality=TextEditingController(text:(source?['quality']??'Auto').toString());final language=TextEditingController(text:(source?['language']??'').toString());final priority=TextEditingController(text:(source?['priority']??0).toString());String type=(source?['source_type']??(widget.ownerType=='tv'?'hls':'auto')).toString();
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setLocal)=>AlertDialog(
      title:Text(source==null?(Api.I.ar?'إضافة سيرفر':'Add server'):(Api.I.ar?'تعديل السيرفر':'Edit server')),
      content:SizedBox(width:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:label,decoration:const InputDecoration(labelText:'Label')),const SizedBox(height:8),
        DropdownButtonFormField<String>(initialValue:['auto','mp4','hls','dash','embed','mpegts'].contains(type)?type:'auto',items:['auto','mp4','hls','dash','embed','mpegts'].map((x)=>DropdownMenuItem(value:x,child:Text(x.toUpperCase()))).toList(),onChanged:(v)=>setLocal(()=>type=v??'auto'),decoration:const InputDecoration(labelText:'Type')),
        const SizedBox(height:8),TextField(controller:url,minLines:2,maxLines:5,decoration:const InputDecoration(labelText:'URL')),
        if(widget.ownerType!='tv')...[const SizedBox(height:8),TextField(controller:quality,decoration:const InputDecoration(labelText:'Quality')),const SizedBox(height:8),TextField(controller:language,decoration:const InputDecoration(labelText:'Language'))],
        const SizedBox(height:8),TextField(controller:priority,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Priority')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(Api.I.ar?'إلغاء':'Cancel')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:Text(Api.I.ar?'حفظ':'Save'))],
    )));
    if(ok==true&&url.text.trim().isNotEmpty){await Api.I.call('admin_source_save',method:'POST',data:{'id':source?['id']??0,'owner_type':widget.ownerType,'owner_id':widget.ownerId,'label':label.text.trim(),'source_type':type,'url':url.text.trim(),'quality':quality.text.trim(),'language':language.text.trim(),'priority':int.tryParse(priority.text)??0,'active':true});load();}
    label.dispose();url.dispose();quality.dispose();language.dispose();priority.dispose();
  }
  Future<void> remove(Map<String,dynamic> source) async{
    final yes=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(Api.I.ar?'حذف السيرفر؟':'Delete server?'),content:Text((source['label']??'').toString()),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(Api.I.ar?'إلغاء':'Cancel')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:Text(Api.I.ar?'حذف':'Delete'))]));
    if(yes==true){await Api.I.call('admin_source_delete',method:'POST',data:{'id':source['id'],'owner_type':widget.ownerType,'owner_id':widget.ownerId});load();}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.title),actions:[IconButton(onPressed:()=>edit(),icon:const Icon(Icons.add_rounded))]),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,builder:(_,s){
        if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!['data'] as List? ?? const[];
        if(rows.isEmpty)return Center(child:FilledButton.icon(onPressed:()=>edit(),icon:const Icon(Icons.add),label:Text(Api.I.ar?'إضافة أول سيرفر':'Add first server')));
        return ListView.builder(padding:const EdgeInsets.all(12),itemCount:rows.length,itemBuilder:(_,i){
          final src=Map<String,dynamic>.from(rows[i] as Map);final sub=[(src['source_type']??'').toString(),(src['quality']??'').toString(),(src['language']??'').toString()].where((x)=>x.isNotEmpty).join(' • ');
          return Card(child:ListTile(
            leading:CircleAvatar(child:Text((i+1).toString())),title:Text((src['label']??'Server').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(sub),
            trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')edit(src);if(v=='delete')remove(src);},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(Api.I.ar?'تعديل':'Edit')),PopupMenuItem(value:'delete',child:Text(Api.I.ar?'حذف':'Delete'))]),onTap:()=>edit(src),
          ));
        });
      },
    ),
  );
}

class AdminChannelsPage extends StatefulWidget{
  const AdminChannelsPage({super.key});
  @override
  State<AdminChannelsPage> createState()=>_AdminChannelsPageState();
}
class _AdminChannelsPageState extends State<AdminChannelsPage>{
  final q=TextEditingController();Future<Map<String,dynamic>>? future;
  @override
  void initState(){super.initState();load();}
  @override
  void dispose(){q.dispose();super.dispose();}
  void load()=>setState(()=>future=Api.I.call('admin_channels',query:{'q':q.text.trim(),'limit':50}));
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(Api.I.ar?'إدارة القنوات':'TV Manager')),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:SearchBar(controller:q,onSubmitted:(_)=>load(),leading:const Icon(Icons.search),trailing:[IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded))])),
      Expanded(child:FutureBuilder<Map<String,dynamic>>(
        future:future,builder:(_,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!['data'] as List? ?? const[];
          return ListView.separated(padding:const EdgeInsets.fromLTRB(12,0,12,20),itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(_,i){
            final ch=Map<String,dynamic>.from(rows[i] as Map);final sub=(ch['source_count']??0).toString()+' servers • ID '+(ch['id']??0).toString();
            return ListTile(
              leading:CircleAvatar(backgroundImage:(ch['logo']??'').toString().isEmpty?null:NetworkImage(ch['logo'].toString()),child:(ch['logo']??'').toString().isEmpty?const Icon(Icons.live_tv):null),
              title:Text((ch['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(sub),trailing:const Icon(Icons.dns_outlined),
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SourceManagerPage(ownerType:'tv',ownerId:(ch['id'] as num).toInt(),title:(ch['name']??'').toString()))).then((_){load();}),
            );
          });
        },
      )),
    ]),
  );
}

part of 'main.dart';

class CachedPageEntry {
  final Map<String,dynamic> payload;
  final DateTime savedAt;

  const CachedPageEntry({required this.payload,required this.savedAt});

  Duration get age=>DateTime.now().difference(savedAt);
}

class AppPageCache {
  AppPageCache._();
  static final I=AppPageCache._();

  // Fresh cache is used immediately for faster page reopening.
  // When the network is unavailable, an older cached copy can be used
  // for up to 14 days.
  static const offlineMaxAge=Duration(days:14);

  static const _cacheableActions=<String>{
    'app_config',
    'home',
    'media',
    'media_detail',
    'genres',
    'people',
    'person',
    'channels',
    'search',
  };

  bool canCache(String action,String method){
    return method.toUpperCase()=='GET'&&_cacheableActions.contains(action);
  }

  Duration freshFor(String action){
    switch(action){
      case 'home':
      case 'search':
        return const Duration(minutes:10);
      case 'media':
      case 'channels':
        return const Duration(minutes:20);
      case 'media_detail':
        return const Duration(minutes:30);
      case 'app_config':
        return const Duration(hours:1);
      case 'genres':
      case 'people':
      case 'person':
        return const Duration(hours:12);
      default:
        return const Duration(minutes:20);
    }
  }

  Future<Directory> _root() async{
    final base=await getApplicationSupportDirectory();
    final dir=Directory('${base.path}/page_cache');
    if(!await dir.exists())await dir.create(recursive:true);
    return dir;
  }

  dynamic _stable(dynamic value){
    if(value is Map){
      final keys=value.keys.map((e)=>e.toString()).toList()..sort();
      return <String,dynamic>{
        for(final key in keys)key:_stable(value[key]),
      };
    }
    if(value is List)return value.map(_stable).toList();
    return value;
  }

  String _rawKey(String action,String locale,Map<String,dynamic>? query){
    return jsonEncode(<String,dynamic>{
      'action':action,
      'locale':locale,
      'query':_stable(query??const <String,dynamic>{}),
    });
  }

  String _hash(String input){
    // Deterministic FNV-1a 64-bit. Used only for filenames.
    var hash=0xcbf29ce484222325;
    for(final byte in utf8.encode(input)){
      hash^=byte;
      hash=(hash*0x100000001b3)&0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16,'0');
  }

  Future<File> _file(String action,String locale,Map<String,dynamic>? query) async{
    final root=await _root();
    final name='${action}_${_hash(_rawKey(action,locale,query))}.json';
    return File('${root.path}/$name');
  }

  Future<CachedPageEntry?> read(
    String action,
    String locale,
    Map<String,dynamic>? query, {
    Duration? maxAge,
  }) async{
    try{
      final file=await _file(action,locale,query);
      if(!await file.exists())return null;
      final decoded=jsonDecode(await file.readAsString());
      if(decoded is! Map)return null;
      final saved=DateTime.tryParse((decoded['saved_at']??'').toString());
      final payload=decoded['payload'];
      if(saved==null||payload is! Map)return null;
      final entry=CachedPageEntry(
        payload:Map<String,dynamic>.from(payload),
        savedAt:saved,
      );
      if(maxAge!=null&&entry.age>maxAge)return null;
      return entry;
    }catch(_){
      return null;
    }
  }

  Future<void> write(
    String action,
    String locale,
    Map<String,dynamic>? query,
    Map<String,dynamic> payload,
  ) async{
    try{
      final file=await _file(action,locale,query);
      final temp=File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode(<String,dynamic>{
          'saved_at':DateTime.now().toUtc().toIso8601String(),
          'payload':payload,
        }),
        flush:true,
      );
      if(await file.exists())await file.delete();
      await temp.rename(file.path);
    }catch(_){}
  }

  Map<String,dynamic> mark(
    CachedPageEntry entry, {
    required bool offline,
  }){
    final out=Map<String,dynamic>.from(entry.payload);
    out['_cache']=<String,dynamic>{
      'cached':true,
      'offline':offline,
      'saved_at':entry.savedAt.toIso8601String(),
      'age_seconds':entry.age.inSeconds,
    };
    return out;
  }

  Future<int> sizeBytes() async{
    var total=0;
    try{
      final root=await _root();
      await for(final entity in root.list()){
        if(entity is File){
          try{total+=await entity.length();}catch(_){}
        }
      }
    }catch(_){}
    return total;
  }

  Future<int> count() async{
    var total=0;
    try{
      final root=await _root();
      await for(final entity in root.list()){
        if(entity is File&&entity.path.endsWith('.json'))total++;
      }
    }catch(_){}
    return total;
  }

  Future<void> clear() async{
    try{
      final root=await _root();
      if(await root.exists()){
        await for(final entity in root.list()){
          if(entity is File){
            try{await entity.delete();}catch(_){}
          }
        }
      }
    }catch(_){}
  }

  Future<void> cleanup() async{
    try{
      final root=await _root();
      final now=DateTime.now();
      await for(final entity in root.list()){
        if(entity is! File||!entity.path.endsWith('.json'))continue;
        try{
          final stat=await entity.stat();
          if(now.difference(stat.modified)>offlineMaxAge){
            await entity.delete();
          }
        }catch(_){}
      }
    }catch(_){}
  }
}


class PageCacheSettingsPage extends StatefulWidget{
  const PageCacheSettingsPage({super.key});

  @override
  State<PageCacheSettingsPage> createState()=>_PageCacheSettingsPageState();
}

class _PageCacheSettingsPageState extends State<PageCacheSettingsPage>{
  late Future<({int count,int bytes})> future;

  @override
  void initState(){
    super.initState();
    future=_stats();
  }

  Future<({int count,int bytes})> _stats() async{
    final values=await Future.wait<int>([
      AppPageCache.I.count(),
      AppPageCache.I.sizeBytes(),
    ]);
    return (count:values[0],bytes:values[1]);
  }

  String _size(int bytes){
    if(bytes>=1024*1024)return '${(bytes/(1024*1024)).toStringAsFixed(1)} MB';
    if(bytes>=1024)return '${(bytes/1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<void> _clear() async{
    await AppPageCache.I.clear();
    if(!mounted)return;
    setState(()=>future=_stats());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:Text(
          Api.I.ar?'تم مسح كاش الصفحات. التنزيلات لم يتم حذفها.':'Page cache cleared. Downloads were not deleted.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(title:Text(Api.I.ar?'الصفحات المحفوظة':'Saved Pages')),
      body:FutureBuilder<({int count,int bytes})>(
        future:future,
        builder:(_,s){
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final stats=s.data!;
          return ListView(
            padding:const EdgeInsets.all(16),
            children:[
              Card(
                child:Padding(
                  padding:const EdgeInsets.all(18),
                  child:Column(
                    children:[
                      const Icon(Icons.offline_bolt_rounded,size:54),
                      const SizedBox(height:12),
                      Text(
                        Api.I.ar?'تصفح أسرع ووضع بدون إنترنت':'Faster browsing & offline pages',
                        textAlign:TextAlign.center,
                        style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900),
                      ),
                      const SizedBox(height:8),
                      Text(
                        Api.I.ar
                          ?'يعيد التطبيق استخدام الصفحات العامة التي فتحتها مؤخرًا. عند انقطاع الإنترنت يمكن استخدام آخر نسخة محفوظة لمدة تصل إلى 14 يومًا.'
                          :'Recently opened public pages are reused for faster loading. Offline fallback keeps the last saved copy for up to 14 days.',
                        textAlign:TextAlign.center,
                        style:const TextStyle(color:Colors.white60,height:1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height:12),
              Card(
                child:Column(
                  children:[
                    ListTile(
                      leading:const Icon(Icons.description_outlined),
                      title:Text(Api.I.ar?'عدد الصفحات المحفوظة':'Cached pages'),
                      trailing:Text(stats.count.toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
                    ),
                    const Divider(height:1),
                    ListTile(
                      leading:const Icon(Icons.storage_rounded),
                      title:Text(Api.I.ar?'مساحة الكاش':'Cache size'),
                      trailing:Text(_size(stats.bytes),style:const TextStyle(fontWeight:FontWeight.w900)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height:12),
              ListTile(
                leading:const Icon(Icons.security_rounded),
                title:Text(Api.I.ar?'الخصوصية':'Privacy'),
                subtitle:Text(
                  Api.I.ar
                    ?'بيانات الحساب ولوحة الإدارة وبيانات تسجيل الدخول لا يتم حفظها في كاش الصفحات.'
                    :'Account, admin and sign-in data are excluded from the page cache.',
                ),
              ),
              const SizedBox(height:8),
              OutlinedButton.icon(
                onPressed:stats.count==0?null:_clear,
                icon:const Icon(Icons.delete_sweep_outlined),
                label:Text(Api.I.ar?'مسح كاش الصفحات':'Clear page cache'),
              ),
            ],
          );
        },
      ),
    );
  }
}

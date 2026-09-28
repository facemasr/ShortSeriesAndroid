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

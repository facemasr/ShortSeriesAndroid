part of 'main.dart';

class OfflineMediaRecord {
  final String ownerType;
  final int ownerId;
  final String title;
  final String groupTitle;
  final String encryptedPath;
  final String extension;
  final int plainBytes;
  final DateTime createdAt;

  const OfflineMediaRecord({
    required this.ownerType,
    required this.ownerId,
    required this.title,
    this.groupTitle='',
    required this.encryptedPath,
    required this.extension,
    required this.plainBytes,
    required this.createdAt,
  });

  String get key => '$ownerType:$ownerId';

  Map<String,dynamic> toJson()=>({
    'owner_type':ownerType,
    'owner_id':ownerId,
    'title':title,
    'group_title':groupTitle,
    'encrypted_path':encryptedPath,
    'extension':extension,
    'plain_bytes':plainBytes,
    'created_at':createdAt.toIso8601String(),
  });

  factory OfflineMediaRecord.fromJson(Map<String,dynamic> json){
    return OfflineMediaRecord(
      ownerType:(json['owner_type']??'').toString(),
      ownerId:int.tryParse((json['owner_id']??'0').toString())??0,
      title:(json['title']??'').toString(),
      groupTitle:(json['group_title']??'').toString(),
      encryptedPath:(json['encrypted_path']??'').toString(),
      extension:(json['extension']??'.mp4').toString(),
      plainBytes:int.tryParse((json['plain_bytes']??'0').toString())??0,
      createdAt:DateTime.tryParse((json['created_at']??'').toString())??DateTime.now(),
    );
  }
}

class OfflineDownloads {
  OfflineDownloads._();
  static final I=OfflineDownloads._();

  static const _keyName='sstv_offline_master_key_v1';
  static const _magic='SSTVENC1';
  static const _nonceLength=12;
  static const _macLength=16;

  final FlutterSecureStorage _secure=const FlutterSecureStorage();
  final AesGcm _cipher=AesGcm.with256bits();
  final Dio _dio=Dio(BaseOptions(
    connectTimeout:const Duration(seconds:20),
    receiveTimeout:const Duration(minutes:15),
    followRedirects:true,
  ));

  final ValueNotifier<Map<String,double>> progress=ValueNotifier(<String,double>{});
  final ValueNotifier<Set<String>> active=ValueNotifier(<String>{});

  String keyFor(String type,int id)=>'$type:$id';

  Future<Directory> _root() async{
    final base=await getApplicationSupportDirectory();
    final dir=Directory('${base.path}/offline_media');
    if(!await dir.exists())await dir.create(recursive:true);
    return dir;
  }

  Future<File> _libraryFile() async{
    final root=await _root();
    return File('${root.path}/library.json');
  }

  Future<Map<String,OfflineMediaRecord>> _library() async{
    final file=await _libraryFile();
    if(!await file.exists())return <String,OfflineMediaRecord>{};
    try{
      final decoded=jsonDecode(await file.readAsString());
      if(decoded is! Map)return <String,OfflineMediaRecord>{};
      final out=<String,OfflineMediaRecord>{};
      for(final entry in decoded.entries){
        if(entry.value is! Map)continue;
        final record=OfflineMediaRecord.fromJson(
          Map<String,dynamic>.from(entry.value as Map),
        );
        if(record.ownerId>0&&record.ownerType.isNotEmpty){
          out[record.key]=record;
        }
      }
      return out;
    }catch(_){
      return <String,OfflineMediaRecord>{};
    }
  }

  Future<void> _saveLibrary(Map<String,OfflineMediaRecord> data) async{
    final file=await _libraryFile();
    final json=<String,dynamic>{};
    for(final entry in data.entries)json[entry.key]=entry.value.toJson();
    await file.writeAsString(jsonEncode(json),flush:true);
  }

  Future<SecretKey> _masterKey() async{
    final stored=await _secure.read(key:_keyName);
    if(stored!=null&&stored.isNotEmpty){
      try{return SecretKey(base64Decode(stored));}catch(_){}
    }
    final key=await _cipher.newSecretKey();
    final bytes=await key.extractBytes();
    await _secure.write(key:_keyName,value:base64Encode(bytes));
    return SecretKey(bytes);
  }

  Map<String,String> _headers(Map<String,dynamic> source){
    dynamic raw=source['headers']??source['headers_json'];
    Map<dynamic,dynamic>? decoded;
    if(raw is Map){
      decoded=raw;
    }else if(raw is String&&raw.trim().isNotEmpty){
      try{
        final value=jsonDecode(raw);
        if(value is Map)decoded=value;
      }catch(_){}
    }
    if(decoded==null)return const <String,String>{};

    const allowed=<String>{
      'referer','origin','user-agent','authorization','cookie',
      'accept','accept-language',
    };
    final out=<String,String>{};
    for(final entry in decoded.entries){
      final k=entry.key.toString().trim();
      final v=(entry.value??'').toString().trim();
      if(k.isEmpty||v.isEmpty||!allowed.contains(k.toLowerCase()))continue;
      out[k]=v;
    }
    return out;
  }

  bool _directDownloadable(Map<String,dynamic> source){
    final type=(source['source_type']??'').toString().toLowerCase();
    final url=Api.I.absoluteUrl(source['url']).toLowerCase();
    if(type.contains('hls')||type.contains('dash')||type.contains('embed'))return false;
    if(url.contains('.m3u8')||url.contains('.mpd'))return false;
    return url.startsWith('http://')||url.startsWith('https://');
  }

  String _extension(Map<String,dynamic> source){
    final uri=Uri.tryParse(Api.I.absoluteUrl(source['url']));
    final path=(uri?.path??'').toLowerCase();
    for(final ext in ['.mp4','.mkv','.webm','.mov','.m4v']){
      if(path.endsWith(ext))return ext;
    }
    final type=(source['source_type']??'').toString().toLowerCase();
    if(type.contains('mkv'))return '.mkv';
    if(type.contains('webm'))return '.webm';
    return '.mp4';
  }

  Future<Map<String,dynamic>> _playback(String type,int id) async{
    final result=await Api.I.call('playback',query:{
      'owner_type':type,
      'owner_id':id,
    });
    return Map<String,dynamic>.from(result['data'] as Map);
  }

  Map<String,dynamic>? _pickSource(Map<String,dynamic> playback){
    final rows=(playback['sources'] as List? ?? const[])
      .whereType<Map>()
      .map((e)=>Map<String,dynamic>.from(e))
      .toList();
    for(final source in rows){
      if(_directDownloadable(source))return source;
    }
    return null;
  }

  Future<Map<String,dynamic>?> _refreshSource(
    String type,
    int id,
    Map<String,dynamic> current,
  ) async{
    final sourceId=int.tryParse((current['id']??'0').toString())??0;
    if(sourceId<=0)return null;
    try{
      final result=await Api.I.call(
        'playback_refresh',
        method:'POST',
        data:{
          'owner_type':type,
          'owner_id':id,
          'source_id':sourceId,
        },
      );
      final data=Map<String,dynamic>.from(result['data'] as Map);
      return _pickSource(data);
    }catch(_){
      return null;
    }
  }

  Future<Map<String,dynamic>> _resolveSource(Map<String,dynamic> source) async{
    final current=Map<String,dynamic>.from(source);
    final uri=Uri.tryParse(Api.I.absoluteUrl(current['url']));
    String candidate='';

    if(uri!=null&&uri.path.contains('/embed4/')){
      candidate=(uri.queryParameters['url']??'').trim();
    }

    if(candidate.isEmpty){
      for(final key in ['source_url','origin_url','page_url','referrer_url']){
        final value=(current[key]??'').toString().trim();
        if(value.isNotEmpty){candidate=value;break;}
      }
    }

    if(candidate.isEmpty){
      final headers=_headers(current);
      for(final entry in headers.entries){
        if(entry.key.toLowerCase()=='referer'){
          candidate=entry.value;
          break;
        }
      }
    }

    if(candidate.isNotEmpty){
      final resolved=await Api.I.resolvePlaybackUrl(candidate);
      if(resolved.isNotEmpty){
        current['url']=resolved;
      }
    }
    return current;
  }

  void _setProgress(String key,double value){
    progress.value=<String,double>{
      ...progress.value,
      key:value.clamp(0.0,1.0).toDouble(),
    };
  }

  void _setActive(String key,bool value){
    final next=<String>{...active.value};
    if(value){next.add(key);}else{next.remove(key);}
    active.value=next;
  }

  Future<OfflineMediaRecord> downloadOwner(
    String type,
    int id,
    String title, {
    String groupTitle='',
    void Function(double value)? onProgress,
  }) async{
    if(type!='media'&&type!='episode'){
      throw Exception(Api.I.ar?'هذا النوع لا يدعم التنزيل':'This item cannot be downloaded');
    }

    final key=keyFor(type,id);
    final existing=await record(type,id);
    if(existing!=null)return existing;
    if(active.value.contains(key)){
      throw Exception(Api.I.ar?'التنزيل جارٍ بالفعل':'Download already in progress');
    }

    _setActive(key,true);
    _setProgress(key,0);

    File? plainTemp;
    try{
      var playback=await _playback(type,id);
      var source=_pickSource(playback);
      if(source==null){
        throw Exception(
          Api.I.ar
            ?'التنزيل دون إنترنت متاح حاليًا للمصادر المباشرة MP4/MKV/WebM فقط.'
            :'Offline download currently supports direct MP4/MKV/WebM sources only.',
        );
      }

      source=await _resolveSource(source);
      final root=await _root();
      final cache=await getTemporaryDirectory();
      final safe='${type}_$id';
      final ext=_extension(source);
      plainTemp=File('${cache.path}/sstv_download_$safe$ext');
      if(await plainTemp.exists())await plainTemp.delete();

      Future<void> fetch(Map<String,dynamic> s) async{
        final url=Api.I.absoluteUrl(s['url']);
        if(url.isEmpty)throw Exception(Api.I.ar?'رابط التحميل غير صالح':'Invalid download URL');
        await _dio.download(
          url,
          plainTemp!.path,
          options:Options(headers:_headers(s),followRedirects:true),
          deleteOnError:true,
          onReceiveProgress:(received,total){
            if(total>0){
              final p=received/total;
              _setProgress(key,p*.82);
              onProgress?.call(p*.82);
            }
          },
        );
      }

      try{
        await fetch(source);
      }on DioException catch(e){
        final status=e.response?.statusCode??0;
        if(status==401||status==403||status==404||status==410){
          final fresh=await _refreshSource(type,id,source);
          if(fresh==null)rethrow;
          source=await _resolveSource(fresh);
          await fetch(source);
        }else{
          rethrow;
        }
      }

      if(!await plainTemp.exists()||await plainTemp.length()<=0){
        throw Exception(Api.I.ar?'فشل تنزيل الملف':'Downloaded file is empty');
      }

      final plainBytes=await plainTemp.length();
      final encrypted=File('${root.path}/$safe.sstv');
      if(await encrypted.exists())await encrypted.delete();
      await _encryptFile(
        plainTemp,
        encrypted,
        onProgress:(p){
          final total=.82+(p*.18);
          _setProgress(key,total);
          onProgress?.call(total);
        },
      );

      final rec=OfflineMediaRecord(
        ownerType:type,
        ownerId:id,
        title:title,
        groupTitle:groupTitle,
        encryptedPath:encrypted.path,
        extension:ext,
        plainBytes:plainBytes,
        createdAt:DateTime.now(),
      );
      final lib=await _library();
      lib[key]=rec;
      await _saveLibrary(lib);
      _setProgress(key,1);
      onProgress?.call(1);
      return rec;
    }finally{
      try{
        if(plainTemp!=null&&await plainTemp.exists())await plainTemp.delete();
      }catch(_){}
      _setActive(key,false);
    }
  }

  Future<void> _encryptFile(
    File input,
    File output, {
    void Function(double value)? onProgress,
  }) async{
    final key=await _masterKey();
    final total=await input.length();
    var done=0;
    final sink=output.openWrite();
    sink.add(utf8.encode(_magic));

    try{
      await for(final chunk in input.openRead()){
        final bytes=Uint8List.fromList(chunk);
        final box=await _cipher.encrypt(bytes,secretKey:key);
        final length=ByteData(4)..setUint32(0,box.cipherText.length,Endian.big);
        sink.add(length.buffer.asUint8List());
        sink.add(box.nonce);
        sink.add(box.mac.bytes);
        sink.add(box.cipherText);
        done+=bytes.length;
        if(total>0)onProgress?.call(done/total);
      }
    }finally{
      await sink.flush();
      await sink.close();
    }
  }

  Future<void> _decryptFile(File input,File output) async{
    final key=await _masterKey();
    final raf=await input.open();
    final sink=output.openWrite();

    try{
      final magic=await raf.read(_magic.length);
      if(utf8.decode(magic,allowMalformed:true)!=_magic){
        throw Exception('Invalid offline media file');
      }

      final length=await raf.length();
      while(await raf.position()<length){
        final lenBytes=await raf.read(4);
        if(lenBytes.isEmpty)break;
        if(lenBytes.length!=4)throw Exception('Corrupted offline media');
        final cipherLength=ByteData.sublistView(Uint8List.fromList(lenBytes))
          .getUint32(0,Endian.big);
        final nonce=await raf.read(_nonceLength);
        final mac=await raf.read(_macLength);
        final cipherText=await raf.read(cipherLength);
        if(nonce.length!=_nonceLength||
           mac.length!=_macLength||
           cipherText.length!=cipherLength){
          throw Exception('Corrupted offline media');
        }
        final clear=await _cipher.decrypt(
          SecretBox(
            cipherText,
            nonce:nonce,
            mac:Mac(mac),
          ),
          secretKey:key,
        );
        sink.add(clear);
      }
    }finally{
      await raf.close();
      await sink.flush();
      await sink.close();
    }
  }

  Future<List<OfflineMediaRecord>> all() async{
    final lib=await _library();
    final out=<OfflineMediaRecord>[];
    var changed=false;
    for(final entry in lib.entries.toList()){
      if(await File(entry.value.encryptedPath).exists()){
        out.add(entry.value);
      }else{
        lib.remove(entry.key);
        changed=true;
      }
    }
    if(changed)await _saveLibrary(lib);
    out.sort((a,b)=>b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<OfflineMediaRecord?> record(String type,int id) async{
    final lib=await _library();
    final rec=lib[keyFor(type,id)];
    if(rec==null)return null;
    if(!await File(rec.encryptedPath).exists()){
      lib.remove(rec.key);
      await _saveLibrary(lib);
      return null;
    }
    return rec;
  }

  Future<bool> has(String type,int id) async=>(await record(type,id))!=null;

  Future<String?> preparePlayback(String type,int id) async{
    final rec=await record(type,id);
    if(rec==null)return null;

    final cache=await getTemporaryDirectory();
    final file=File('${cache.path}/sstv_play_${type}_$id${rec.extension}');
    if(await file.exists())await file.delete();
    await _decryptFile(File(rec.encryptedPath),file);
    return file.path;
  }

  Future<void> releasePlayback(String? path) async{
    if(path==null||path.isEmpty)return;
    try{
      final file=File(path);
      if(await file.exists())await file.delete();
    }catch(_){}
  }

  Future<void> delete(String type,int id) async{
    final lib=await _library();
    final key=keyFor(type,id);
    final rec=lib.remove(key);
    if(rec!=null){
      try{
        final file=File(rec.encryptedPath);
        if(await file.exists())await file.delete();
      }catch(_){}
      await _saveLibrary(lib);
    }
    final next=<String,double>{...progress.value}..remove(key);
    progress.value=next;
  }

  Future<void> cleanupPlaybackCache() async{
    try{
      final cache=await getTemporaryDirectory();
      await for(final entity in cache.list()){
        if(entity is File&&entity.path.contains('sstv_play_')){
          try{await entity.delete();}catch(_){}
        }
        if(entity is File&&entity.path.contains('sstv_download_')){
          try{await entity.delete();}catch(_){}
        }
      }
    }catch(_){}
  }
}

class OfflineLibraryPage extends StatefulWidget{
  final VoidCallback? onRetry;
  const OfflineLibraryPage({super.key,this.onRetry});

  @override
  State<OfflineLibraryPage> createState()=>_OfflineLibraryPageState();
}

class _OfflineLibraryPageState extends State<OfflineLibraryPage>{
  late Future<List<OfflineMediaRecord>> future;

  @override
  void initState(){
    super.initState();
    future=OfflineDownloads.I.all();
  }

  void reload()=>setState(()=>future=OfflineDownloads.I.all());

  String _size(int bytes){
    if(bytes>=1024*1024*1024)return '${(bytes/(1024*1024*1024)).toStringAsFixed(1)} GB';
    if(bytes>=1024*1024)return '${(bytes/(1024*1024)).toStringAsFixed(0)} MB';
    return '${(bytes/1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(
        title:Text(Api.I.ar?'التنزيلات':'Downloads'),
        actions:[
          if(widget.onRetry!=null)
            IconButton(
              tooltip:Api.I.ar?'إعادة الاتصال':'Retry connection',
              onPressed:widget.onRetry,
              icon:const Icon(Icons.wifi_rounded),
            ),
        ],
      ),
      body:FutureBuilder<List<OfflineMediaRecord>>(
        future:future,
        builder:(_,snapshot){
          if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
          final items=snapshot.data!;
          if(items.isEmpty){
            return Center(
              child:Padding(
                padding:const EdgeInsets.all(28),
                child:Column(
                  mainAxisSize:MainAxisSize.min,
                  children:[
                    const Icon(Icons.download_for_offline_outlined,size:70,color:Colors.white24),
                    const SizedBox(height:14),
                    Text(
                      Api.I.ar?'لا توجد تنزيلات بعد':'No downloads yet',
                      style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900),
                    ),
                    const SizedBox(height:7),
                    Text(
                      Api.I.ar
                        ?'حمّل فيلمًا أو حلقة وشاهدها دون إنترنت.'
                        :'Download a movie or episode to watch offline.',
                      textAlign:TextAlign.center,
                      style:const TextStyle(color:Colors.white54),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding:const EdgeInsets.all(12),
            itemCount:items.length,
            separatorBuilder:(_,__)=>const SizedBox(height:8),
            itemBuilder:(_,i){
              final item=items[i];
              return Card(
                child:ListTile(
                  leading:const CircleAvatar(
                    child:Icon(Icons.download_done_rounded),
                  ),
                  title:Text(item.title,maxLines:2,overflow:TextOverflow.ellipsis),
                  subtitle:Text(
                    '${item.ownerType=='episode'?(Api.I.ar?'حلقة':'Episode'):(Api.I.ar?'فيلم':'Movie')} • ${_size(item.plainBytes)}',
                  ),
                  onTap:(){
                    AppNavigator.open(
                      context,
                      ProPlayerPage(
                        ownerType:item.ownerType,
                        ownerId:item.ownerId,
                        title:item.title,
                      ),
                      key:'player/${item.ownerType}/${item.ownerId}',
                    );
                  },
                  trailing:IconButton(
                    tooltip:Api.I.ar?'حذف التنزيل':'Delete download',
                    onPressed:() async{
                      await OfflineDownloads.I.delete(item.ownerType,item.ownerId);
                      if(mounted)reload();
                    },
                    icon:const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'player_ads.dart';

const origin = 'https://egyshow.com';
const bridge = MethodChannel('com.egyshow.player/launch');
const red = Color(0xffe50914);
bool useArabic(String? saved, String deviceLanguage) =>
    saved == 'ar' || (saved != 'en' && deviceLanguage.toLowerCase() == 'ar');

final playerLocale = ValueNotifier<Locale>(const Locale('en'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final deviceLanguage = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  String? saved;
  try {
    saved = (await SharedPreferences.getInstance()).getString('player_language');
  } catch (_) {}
  playerLocale.value = Locale(useArabic(saved, deviceLanguage) ? 'ar' : 'en');
  runApp(ValueListenableBuilder<Locale>(
    valueListenable: playerLocale,
    builder: (context, locale, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EGY Player',
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xff09090c),
        colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark).copyWith(primary: red, onPrimary: Colors.white, secondary: red, surface: const Color(0xff141418))),
      home: const PlayerScreen(),
    ),
  ));
}
Map<String,dynamic> object(dynamic v) => v is Map ? Map<String,dynamic>.from(v) : {};
class PlayTarget {
  const PlayTarget(this.type,this.id,this.ar);
  final String type;
  final int id;
  final bool ar;
  static PlayTarget? parse(String? input) {
    final u=Uri.tryParse(input??'');
    if(u==null||u.scheme!='egyplayer'||u.host!='play'||u.path.isNotEmpty||
      u.userInfo.isNotEmpty||u.hasFragment) return null;
    final type=u.queryParameters['type'];
    final id=int.tryParse(u.queryParameters['id']??'');
    if(!['movie','episode'].contains(type)||id==null||id<1) return null;
    return PlayTarget(type!,id,u.queryParameters['lang']!='en');
  }
}
// Only direct HTTPS media or Android's permission-scoped content URIs.
Uri? parseDirectMedia(String? input) {
  final uri=Uri.tryParse((input??'').trim());
  if(uri==null||uri.scheme!='https'||uri.host.isEmpty||uri.userInfo.isNotEmpty||uri.hasFragment) return null;
  return uri;
}
Uri? parseLocalMedia(String? input) {
  final uri=Uri.tryParse(input??'');
  return uri!=null&&uri.scheme=='content'&&uri.host.isNotEmpty&&uri.userInfo.isEmpty?uri:null;
}
VideoFormat? formatFor(Uri uri) {
  final path=uri.path.toLowerCase();
  if(path.endsWith('.m3u8'))return VideoFormat.hls;
  if(path.endsWith('.mpd'))return VideoFormat.dash;
  return null; // let Media3 infer progressive media
}
// Probe authorized direct media without downloading the entire response.
Future<VideoFormat?> detectMediaFormat(http.Client client,Uri uri) async {
  final known=formatFor(uri);
  if(known!=null)return known;
  try {
    final response=await client.head(uri).timeout(const Duration(seconds:5));
    if(response.statusCode<200||response.statusCode>=300)return null;
    final mime=(response.headers['content-type']??'').split(';').first.trim().toLowerCase();
    if(mime.contains('mpegurl'))return VideoFormat.hls;
    if(mime=='application/dash+xml')return VideoFormat.dash;
    if(mime.startsWith('video/')||mime.startsWith('audio/'))return VideoFormat.other;
    if(mime=='text/html')throw const FormatException('html_not_media');
  } on FormatException {rethrow;} catch (_) {}
  return null;
}
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override State<PlayerScreen> createState()=>_PlayerScreenState();
}
class _PlayerScreenState extends State<PlayerScreen> {
  final client=http.Client();
  http.Client? metadataClient;
  http.Client? createMetadataClient(){
    if(!Platform.isAndroid)return null;
    try{return CronetClient.defaultCronetEngine();}catch(_){return null;}
  }
  bool transientStatus(int code)=>const {408,500,502,503,504}.contains(code);
  Future<http.Response> getMetadata(Uri uri) async {
    const headers={'Accept':'application/json'};
    final primary=metadataClient;
    if(primary!=null){
      try{
        final response=await primary.get(uri,headers:headers).timeout(const Duration(seconds:12));
        if(!transientStatus(response.statusCode))return response;
      } on TimeoutException { /* fallback for read-only metadata */ }
      on http.ClientException { /* fallback with normal TLS validation */ }
      on Exception { /* platform transport may be unavailable */ }
      if(!mounted)throw StateError('player closed');
    }
    return client.get(uri,headers:headers).timeout(const Duration(seconds:20));
  }
  final ads=PlayerAds();
  void onAdChanged(){if(mounted)setState((){});}
  PlayTarget? target;
  Uri? externalMedia;
  String externalName='';
  VideoPlayerController? video;
  List<Map<String,dynamic>> sources=[];
  int generation=0,index=-1;
  List<Map<String,dynamic>> episodes=[];
  bool autoNext=true, episodeTransition=false;
  Timer? nextEpisodeTimer;
  int nextEpisodeSeconds=0;
  double swipeDistance=0;
  void cancelNextEpisode({bool refresh=true}){
    nextEpisodeTimer?.cancel();nextEpisodeTimer=null;
    if(refresh&&mounted){setState(()=>nextEpisodeSeconds=0);}else{nextEpisodeSeconds=0;}
  }
  int get episodeIndex=>episodes.indexWhere((e)=>e['id']==target?.id);
  void goEpisode(int offset){final i=episodeIndex+offset;if(episodeIndex<0||i<0||i>=episodes.length||busy)return;cancelNextEpisode(); final id=episodes[i]['id']; unawaited(openTarget(Uri(scheme:'egyplayer',host:'play',queryParameters:{'type':'episode','id':'$id','lang':ar?'ar':'en'}).toString()));}
  void episodeEnded(){
    if(!mounted||episodeTransition||!autoNext||episodeIndex<0||episodeIndex+1>=episodes.length||video?.value.isCompleted!=true)return;
    episodeTransition=true;
    final completed=video, op=generation;
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(!mounted||generation!=op||video!=completed||video?.value.isCompleted!=true||!autoNext)return;
      setState(()=>nextEpisodeSeconds=5);
      nextEpisodeTimer=Timer.periodic(const Duration(seconds:1),(timer){
        if(!mounted||generation!=op||video!=completed||video?.value.isCompleted!=true||!autoNext){cancelNextEpisode();return;}
        if(nextEpisodeSeconds<=1){goEpisode(1);}else{setState(()=>nextEpisodeSeconds--);}
      });
    });
  }
  bool get ar => playerLocale.value.languageCode == 'ar';
  bool busy=false,full=false,locked=false,controls=true;
  double speed=1, volume=1;
  double? scrubPosition;
  VideoPlayerController? scrubController;
  bool fillVideo=false;
  double tapX=0, tapWidth=1;
  Future<void> restorePlayerPreferences() async {
    try {
      final p=await SharedPreferences.getInstance();
      if(!mounted)return;
      setState(()=>autoNext=p.getBool('player_auto_next')??true);
    }catch(_){}
  }
  void changeAutoNext(bool value){
    setState(()=>autoNext=value);
    if(!value)cancelNextEpisode();
    unawaited(SharedPreferences.getInstance().then((p)=>p.setBool('player_auto_next',value)).then<void>((_){}).catchError((Object _){}));
  }
  Future<void> chooseSpeed() async {
    final values=[0.5,0.75,1.0,1.25,1.5,2.0];
    final selected=await showModalBottomSheet<double>(context:context,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,children:[
      Padding(padding:const EdgeInsets.all(16),child:Text(t('سرعة التشغيل','Playback speed'),style:Theme.of(ctx).textTheme.titleLarge)),
      for(final value in values) ListTile(title:Text('${value}x'),trailing:value==speed?const Icon(Icons.check,color:red):null,onTap:()=>Navigator.pop(ctx,value)),
    ])));
    if(selected==null||!mounted)return;
    setState(()=>speed=selected);
    await video?.setPlaybackSpeed(selected);
    if(mounted)showControls();
  }
  Future<void> chooseVolume() async {
    await showModalBottomSheet<void>(context:context,builder:(ctx)=>SafeArea(child:StatefulBuilder(builder:(ctx,refresh)=>Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(t('مستوى الصوت','Volume'),style:Theme.of(ctx).textTheme.titleLarge),
      Row(children:[IconButton(tooltip:t('كتم الصوت','Mute'),onPressed:(){refresh(()=>volume=0);unawaited(video?.setVolume(0));},icon:const Icon(Icons.volume_off)),Expanded(child:Slider(value:volume,onChanged:(value){refresh(()=>volume=value);unawaited(video?.setVolume(value));})),Text('${(volume*100).round()}%')]),
    ])))));
    if(mounted)showControls();
  }
  Future<void> chooseEpisode() async {
    final current=target;
    final list=List<Map<String,dynamic>>.of(episodes);
    final selected=await showModalBottomSheet<int>(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:FractionallySizedBox(heightFactor:0.72,child:Column(children:[
      Padding(padding:const EdgeInsets.all(16),child:Text(t('الحلقات','Episodes'),style:Theme.of(ctx).textTheme.titleLarge)),
      Expanded(child:ListView.builder(itemCount:list.length,itemBuilder:(ctx,i){final e=list[i];return ListTile(leading:Icon(e['id']==current?.id?Icons.play_circle_fill:Icons.play_circle_outline,color:e['id']==current?.id?red:null),title:Text(t('الحلقة ${e['episode_number']??i+1}','Episode ${e['episode_number']??i+1}')),onTap:()=>Navigator.pop(ctx,i));})),
    ]))));
    if(!mounted||selected==null||target!=current||busy)return;
    final id=list[selected]['id'];
    if(id==current?.id)return;
    await openTarget(Uri(scheme:'egyplayer',host:'play',queryParameters:{'type':'episode','id':'$id','lang':ar?'ar':'en'}).toString());
  }
  Future<void> syncFullscreenOrientation() async {
    if(!full||!mounted)return;
    final ratio=video?.value.aspectRatio??16/9;
    try{await SystemChrome.setPreferredOrientations(ratio<1?[DeviceOrientation.portraitUp]:[DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]);}catch(_){}
  }
  String titleAr='', titleEn='';
  String errorAr='', errorEn='';
  String get title => (ar ? titleAr : titleEn).isNotEmpty
      ? (ar ? titleAr : titleEn)
      : ((ar ? titleEn : titleAr).isNotEmpty ? (ar ? titleEn : titleAr) : 'EGY Player');
  String get error => ar ? errorAr : errorEn;
  void clearError(){errorAr='';errorEn='';}
  void setError(String a,String e){errorAr=a;errorEn=e;}
  void setTitles(String a,String e){titleAr=a;titleEn=e;}
  Future<void> chooseLanguage() async {
    final choice=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(
      title:Text(t('اللغة','Language')),
      children:[
        SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'ar'),child:const Text('العربية')),
        SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'en'),child:const Text('English')),
      ],
    ));
    if(choice==null||!mounted)return;
    setState(()=>playerLocale.value=Locale(choice));
    try{await (await SharedPreferences.getInstance()).setString('player_language',choice);}catch(_){}
  }
  Timer? hideTimer, progressTimer;
  int recoveryAttempts=0;
  bool recovering=false;
  void recoverPlayback(VideoPlayerController controller){
    if(!mounted||busy||recovering||video!=controller||!controller.value.hasError||recoveryAttempts>=2)return;
    recovering=true;recoveryAttempts++;
    final op=generation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {if(mounted&&generation==op&&video==controller){await saveProgress();if(mounted&&generation==op)await retryCurrent();}} finally {recovering=false;}
    });
  }
  String? get progressKey => target==null?null:'resume_${target!.type}_${target!.id}';
  Future<void> saveProgress() async {final key=progressKey;final v=video?.value;if(key==null||v==null||!v.isInitialized)return;try{final p=await SharedPreferences.getInstance();if(v.isCompleted){await p.remove(key);}else if(v.position.inSeconds>=5){await p.setInt(key,v.position.inMilliseconds);}}catch(_){}}
  Future<Duration> savedProgress() async {final key=progressKey;if(key==null)return Duration.zero;try{return Duration(milliseconds:(await SharedPreferences.getInstance()).getInt(key)??0);}catch(_){return Duration.zero;}}
  String t(String a,String e)=>ar?a:e;
  @override void initState(){
    super.initState();
    metadataClient=createMetadataClient();
    unawaited(restorePlayerPreferences());
    progressTimer=Timer.periodic(const Duration(seconds:5),(_)=>unawaited(saveProgress()));
    ads.addListener(onAdChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)unawaited(ads.prepare());});
    bridge.setMethodCallHandler((call) async {
      if(call.method=='open') await dispatch(call.arguments as String?);
    });
    unawaited(bridge.invokeMethod<String>('initialLink').then((link)=>dispatch(link,initial:true))
      .catchError((Object e){}));
  }
  Future<void> dispatch(String? input,{bool initial=false}) async {
    if(PlayTarget.parse(input)!=null){await openTarget(input,initial:initial);return;}
    final uri=parseLocalMedia(input)??parseDirectMedia(input);
    if(uri!=null){await playExternal(uri,initial:initial);return;}
    if(initial)unawaited(ads.finishStartup());
  }
  Future<void> pickLocal() async {
    try {
      final raw=await bridge.invokeMethod<String>('pickVideo');
      final uri=parseLocalMedia(raw);
      if(uri!=null&&mounted)await playExternal(uri);
    } catch(_){if(mounted)setState(()=>setError('تعذر فتح ملف الفيديو','Unable to open video file'));}
  }
  Future<void> enterLink() async {
    String input='';
    final result=await showDialog<String>(context:context,builder:(ctx)=>Directionality(
      textDirection:ar?TextDirection.rtl:TextDirection.ltr,child:AlertDialog(
      title:Text(t('تشغيل رابط مباشر','Play a direct link')),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(autofocus:true,keyboardType:TextInputType.url,textDirection:TextDirection.ltr,
          autocorrect:false,enableSuggestions:false,
          decoration:const InputDecoration(hintText:'https://example.com/video.m3u8'),
          onChanged:(v)=>input=v,onSubmitted:(v)=>Navigator.pop(ctx,v)),
        const SizedBox(height:12),
        Text(t('أدخل رابط فيديو أو بث مباشر مصرح به، وليس رابط صفحة ويب.','Enter an authorized direct video or stream URL, not a web page.')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(t('إلغاء','Cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(ctx,input),child:Text(t('تشغيل','Play')))],
    )));
    if(result==null||!mounted)return;
    final uri=parseDirectMedia(result);
    if(uri==null){setState(()=>setError('أدخل رابط HTTPS مباشر صالحاً','Enter a valid direct HTTPS URL'));return;}
    await playExternal(uri);
  }
  Future<void> playExternal(Uri uri,{bool initial=false}) async {
    if(!mounted)return;
    if(!initial)unawaited(ads.finishStartup());
    unawaited(saveProgress());
    final op=++generation;
    final old=video;video=null;
    final local=uri.scheme=='content';
    cancelNextEpisode(refresh:false);episodes=[];episodeTransition=false;recoveryAttempts=0;scrubPosition=null;scrubController=null;
    String name='';
    setState((){target=null;externalMedia=uri;externalName=name;setTitles(local?'فيديو من الهاتف':'فيديو عبر الإنترنت',local?'Local video':'Network video');sources=[];index=-1;busy=true;clearError();locked=false;});
    await old?.dispose();
    VideoPlayerController? candidate;
    try{
      if(local){
        try{
          final display=await bridge.invokeMethod<String>('videoName',uri.toString());
          if(display!=null&&display.trim().isNotEmpty)name=display;
        }catch(_){}
      }
      if(!mounted||generation!=op)return;
      if(initial)ads.beginStartup();
      final detected=local?null:await detectMediaFormat(client,uri);
      if(!mounted||generation!=op)return;
      candidate=local?VideoPlayerController.contentUri(uri,viewType:VideoViewType.platformView):
        VideoPlayerController.networkUrl(uri,formatHint:detected,viewType:VideoViewType.platformView);
      await candidate.initialize().timeout(const Duration(seconds:25));
      if(!mounted||generation!=op){await candidate.dispose();return;}
      await candidate.setPlaybackSpeed(speed);
      await candidate.setVolume(volume);
      await ads.finishStartup();
      if(!mounted||generation!=op){await candidate.dispose();return;}
      await candidate.play();
      if(!mounted||generation!=op){await candidate.dispose();return;}
      setState((){video=candidate;if(name.isNotEmpty)setTitles(name,name);externalName=name;busy=false;});
      await syncFullscreenOrientation();
      if(mounted&&generation==op)showControls();
    }catch(e){
      await candidate?.dispose();
      unawaited(ads.finishStartup());
      if(mounted&&generation==op)setState((){busy=false;if(e is FormatException){setError('الرابط صفحة ويب وليس مصدر فيديو مباشر. استخدم رابط البث الرسمي.','This is a web page, not a direct media source. Use the official stream URL.');}else{setError('تعذر تشغيل الفيديو. تحقق من الرابط أو صيغة الملف.','Unable to play video. Check the URL or file format.');}});
    }
  }
  Future<void> retryCurrent() async {
    final uri=externalMedia;
    if(uri!=null){await playExternal(uri);return;}
    final current=target;
    if(current==null)return;
    if(sources.isNotEmpty){await select(index<0?0:index,automatic:true);return;}
    await openTarget(Uri(scheme:'egyplayer',host:'play',queryParameters:{
      'type':current.type,'id':current.id.toString(),'lang':ar?'ar':'en'}).toString());
  }
  Future<Map<String,dynamic>> request(String path,{Map<String,dynamic>? body}) async {
    final uri=Uri.parse(origin+path);
    // Keep lease issuance single-shot: never replay POST on transport failure.
    final response=body==null?await getMetadata(uri):await client.post(uri,
      headers:{'Accept':'application/json','Content-Type':'application/json'},body:jsonEncode(body))
      .timeout(const Duration(seconds:35));
    if(response.statusCode!=200)throw StateError('unavailable (${response.statusCode})');
    final data=object(jsonDecode(utf8.decode(response.bodyBytes)));
    if(data['ok']!=true)throw StateError('unavailable');
    return data;
  }
  Future<void> openTarget(String? input,{bool initial=false}) async {
    final next=PlayTarget.parse(input);
    if(next==null||!mounted){if(initial)unawaited(ads.finishStartup());return;}
    if(!initial)unawaited(ads.finishStartup());
    await saveProgress();
    if(!mounted)return;
    recoveryAttempts=0;
    final op=++generation;
    final old=video;video=null;
    cancelNextEpisode(refresh:false);scrubPosition=null;scrubController=null;
    setState((){target=next;episodes=[];episodeTransition=false;externalMedia=null;externalName='';setTitles('','');sources=[];index=-1;busy=true;clearError();locked=false;});
    await old?.dispose();
    try {
      final path='/api/v1/mobile/guest/player?type=${next.type}&id=${next.id}';
      final data=await request(path);
      if(!mounted||generation!=op)return;
      final items=(data['sources'] as List? ?? []).map(object).where((m)=>m['id'] is num).toList();
      setState((){setTitles((data['title_ar']??'').toString(),(data['title_en']??'').toString());sources=items;busy=false;});
      if(next.type=='episode'&&data['media_id'] is num){try{final detail=await request('/api/v1/mobile/guest/media/${data['media_id']}');if(!mounted||generation!=op)return;setState(()=>episodes=(object(detail['media'])['episodes'] as List? ?? []).map(object).toList());}catch(_){}}
      if(items.isEmpty){unawaited(ads.finishStartup());setState(()=>setError('لا توجد سيرفرات مشاهدة متاحة','No available servers'));return;}
      if(initial)ads.beginStartup();
      await select(0,automatic:true);
    }catch(_){unawaited(ads.finishStartup());if(mounted&&generation==op)setState((){busy=false;setError('تعذر تحميل بيانات المشاهدة','Unable to load playback data');});}
  }
  Future<void> select(int next,{bool automatic=false}) async {
    final current=target;
    if(current==null||next<0||next>=sources.length)return;
    final op=++generation;
    final old=video;
    final resume=old?.value.isInitialized==true?old!.value.position:await savedProgress();
    if(!mounted||generation!=op)return;
    video=null;
    cancelNextEpisode(refresh:false);episodeTransition=false;scrubPosition=null;scrubController=null;
    setState((){busy=true;index=next;clearError();controls=true;});
    await old?.dispose();
    final order=automatic?List<int>.generate(sources.length,(offset)=>(next+offset)%sources.length):[next];
    for(final i in order){
      VideoPlayerController? candidate;
      try{
        final data=await request('/api/v1/mobile/guest/player/lease',body:{
          'type':current.type,'id':current.id,'source_id':sources[i]['id']});
        if(!mounted||generation!=op)return;
        final uri=Uri.parse(origin).resolve(data['playUrl']?.toString()??'');
        if(uri.scheme!='https'||uri.host.isEmpty||uri.userInfo.isNotEmpty||
          data['playUrl']==null)throw StateError('invalid stream');
        final format=switch(data['type']){'hls'=>VideoFormat.hls,'dash'=>VideoFormat.dash,'video'=>VideoFormat.other,_=>throw StateError('unsupported stream')};
        candidate=VideoPlayerController.networkUrl(uri,formatHint:format,viewType:VideoViewType.platformView);
        await candidate.initialize().timeout(const Duration(seconds:25));
        if(!mounted||generation!=op){await candidate.dispose();return;}
        if(resume>Duration.zero&&resume<candidate.value.duration)await candidate.seekTo(resume);
        await candidate.setPlaybackSpeed(speed);
      await candidate.setVolume(volume);
        await ads.finishStartup();
        if(!mounted||generation!=op){await candidate.dispose();return;}
        await candidate.play();
        if(!mounted||generation!=op){await candidate.dispose();return;}
        setState((){video=candidate;index=i;busy=false;});
        await syncFullscreenOrientation();
        if(mounted&&generation==op)showControls();return;
      }catch(_){
        await candidate?.dispose();
        if(!mounted||generation!=op)return;
      }
    }
    await ads.finishStartup();
    if(mounted&&generation==op)setState((){busy=false;setError('تعذر تشغيل السيرفر. جرّب سيرفراً آخر.','Playback unavailable. Try another server.');});
  }
  void showControls(){
    if(!mounted)return;
    hideTimer?.cancel();
    setState(()=>controls=true);
    hideTimer=Timer(const Duration(seconds:5),(){
      if(mounted&&video?.value.isPlaying==true&&!locked)setState(()=>controls=false);
    });
  }
  Future<void> seek(int seconds) async {
    final v=video;if(v==null||!v.value.isInitialized)return;
    final position=(v.value.position.inMilliseconds+seconds*1000).clamp(0,v.value.duration.inMilliseconds).toInt();
    await v.seekTo(Duration(milliseconds:position));showControls();
  }
  Future<void> toggleFull() async {
    setState(()=>full=!full);
    await SystemChrome.setPreferredOrientations(full?(video?.value.aspectRatio != null && video!.value.aspectRatio < 1 ? [DeviceOrientation.portraitUp] : [DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]):[]);
    await SystemChrome.setEnabledSystemUIMode(full?SystemUiMode.immersiveSticky:SystemUiMode.edgeToEdge);
  }
  String stamp(Duration d)=>'${d.inHours>0?'${d.inHours}:':''}${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
  @override void dispose(){
    ads.removeListener(onAdChanged);ads.dispose();
    unawaited(saveProgress());progressTimer?.cancel();nextEpisodeTimer?.cancel();generation++;hideTimer?.cancel();bridge.setMethodCallHandler(null);video?.dispose();metadataClient?.close();client.close();
    SystemChrome.setPreferredOrientations([]);SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);super.dispose();
  }
  Widget surface(){
    final v=video;
    if(v==null)return ColoredBox(color:Colors.black,child:Center(child:busy?
      const CircularProgressIndicator(color:red):Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.play_circle_outline,size:58,color:red),
        if(error.isNotEmpty)Padding(padding:const EdgeInsets.all(16),child:Text(error,textAlign:TextAlign.center)),
        if((target!=null||externalMedia!=null)&&error.isNotEmpty)TextButton.icon(onPressed:retryCurrent,icon:const Icon(Icons.refresh),label:Text(t('إعادة المحاولة','Retry')))
      ])));
    return ValueListenableBuilder<VideoPlayerValue>(valueListenable:v,builder:(context,state,_){
      if(state.isCompleted)episodeEnded();
      if(!state.isCompleted&&nextEpisodeTimer==null&&episodeTransition)episodeTransition=false;
      if(state.hasError)recoverPlayback(v);
      final duration=state.duration.inMilliseconds;
      final position=(scrubController==v&&scrubPosition!=null?scrubPosition!:state.position.inMilliseconds.toDouble()).clamp(0.0,duration>0?duration.toDouble():0.0).toDouble();
      return LayoutBuilder(builder:(context,constraints)=>GestureDetector(onDoubleTapDown:(details){tapX=details.localPosition.dx;tapWidth=constraints.maxWidth;},onDoubleTap:(){if(!locked&&!state.hasError)unawaited(seek(tapX<tapWidth/2?-10:10));},
        onVerticalDragStart:full&&state.aspectRatio<1&&!locked&&episodeIndex>=0?(_)=>swipeDistance=0:null,
        onVerticalDragUpdate:full&&state.aspectRatio<1&&!locked&&episodeIndex>=0?(d)=>swipeDistance+=d.delta.dy:null,
        onVerticalDragEnd:full&&state.aspectRatio<1&&!locked&&episodeIndex>=0?(_){if(swipeDistance.abs()>60)goEpisode(swipeDistance<0?1:-1);swipeDistance=0;}:null,
        onTap:()=>locked?showControls():(controls?setState(()=>controls=false):showControls()),
        child:Stack(fit:StackFit.expand,children:[
          const ColoredBox(color:Colors.black),
          ClipRect(child:LayoutBuilder(builder:(context,space){final ratio=state.aspectRatio>0?state.aspectRatio:16/9;final boxRatio=space.maxWidth/space.maxHeight;final useWidth=fillVideo?boxRatio>ratio:boxRatio<ratio;final width=useWidth?space.maxWidth:space.maxHeight*ratio;final height=width/ratio;return Center(child:OverflowBox(minWidth:width,maxWidth:width,minHeight:height,maxHeight:height,child:VideoPlayer(v)));})),
          if(state.isBuffering)const Center(child:CircularProgressIndicator(color:red)),
          if(state.hasError)Center(child:FilledButton.icon(onPressed:recovering?null:(){recoveryAttempts=0;unawaited(retryCurrent());},icon:const Icon(Icons.refresh),label:Text(t('إعادة التشغيل','Retry playback')))),
          if(controls&&!state.hasError)DecoratedBox(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0x66000000),Colors.transparent,Color(0xaa000000)])),child:SafeArea(child:Column(children:[
            Row(children:[
              IconButton(tooltip:locked?t('إلغاء القفل','Unlock'):t('قفل الشاشة','Lock controls'),onPressed:()=>setState(()=>locked=!locked),icon:Icon(locked?Icons.lock:Icons.lock_open)),
              const Spacer(),
              if(!locked&&episodeIndex>0)IconButton(tooltip:t('الحلقة السابقة','Previous episode'),onPressed:()=>goEpisode(-1),icon:const Icon(Icons.skip_previous)),
              if(!locked&&episodeIndex>=0&&episodeIndex+1<episodes.length)IconButton(tooltip:t('الحلقة التالية','Next episode'),onPressed:()=>goEpisode(1),icon:const Icon(Icons.skip_next)),
              if(!locked)IconButton(tooltip:full?t('الخروج من ملء الشاشة','Exit fullscreen'):t('ملء الشاشة','Fullscreen'),onPressed:toggleFull,icon:Icon(full?Icons.fullscreen_exit:Icons.fullscreen)),
            ]),
            if(!locked&&constraints.maxHeight>=260)SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              IconButton(tooltip:t('سرعة التشغيل','Playback speed'),onPressed:chooseSpeed,icon:const Icon(Icons.speed)),
              IconButton(tooltip:t('الصوت','Volume'),onPressed:chooseVolume,icon:Icon(volume==0?Icons.volume_off:Icons.volume_up)),
              IconButton(tooltip:fillVideo?t('احتواء الفيديو','Fit video'):t('ملء المساحة','Fill video'),onPressed:(){setState(()=>fillVideo=!fillVideo);showControls();},icon:Icon(fillVideo?Icons.fit_screen:Icons.aspect_ratio)),
              if(episodes.isNotEmpty)IconButton(tooltip:t('قائمة الحلقات','Episodes'),onPressed:chooseEpisode,icon:const Icon(Icons.playlist_play)),
            ])),
            const Spacer(),
            if(!locked)Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              IconButton(tooltip:t('رجوع 10 ثوانٍ','Back 10 seconds'),iconSize:36,onPressed:()=>seek(-10),icon:const Icon(Icons.replay_10)),
              IconButton(tooltip:state.isPlaying?t('إيقاف مؤقت','Pause'):t('تشغيل','Play'),iconSize:56,onPressed:()async{state.isPlaying?await v.pause():await v.play();showControls();},icon:Icon(state.isPlaying?Icons.pause_circle_filled:Icons.play_circle_fill)),
              IconButton(tooltip:t('تقديم 10 ثوانٍ','Forward 10 seconds'),iconSize:36,onPressed:()=>seek(10),icon:const Icon(Icons.forward_10)),
            ]),
            const Spacer(),
            if(!locked&&duration>0)Slider(value:position,max:duration.toDouble(),activeColor:red,onChangeStart:(x){hideTimer?.cancel();setState((){scrubController=v;scrubPosition=x;});},onChanged:(x)=>setState(()=>scrubPosition=x),onChangeEnd:(x) async {setState((){scrubController=null;scrubPosition=null;});if(video==v)await v.seekTo(Duration(milliseconds:x.round()));if(mounted)showControls();}),
            if(!locked)Padding(padding:const EdgeInsets.fromLTRB(12,0,12,8),child:Row(children:[
              Text(stamp(Duration(milliseconds:position.round()))),const Spacer(),Text(stamp(state.duration)),
            ])),
          ]))),
          if(nextEpisodeSeconds>0&&!locked)Center(child:Card(color:const Color(0xee141418),child:Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(t('الحلقة التالية خلال $nextEpisodeSeconds ثوانٍ','Next episode in $nextEpisodeSeconds seconds')),Wrap(spacing:8,children:[TextButton(onPressed:()=>cancelNextEpisode(),child:Text(t('إلغاء','Cancel'))),FilledButton(onPressed:()=>goEpisode(1),child:Text(t('تشغيل الآن','Play now')))])])))),
        ])));
    });
  }
  @override Widget build(BuildContext context)=>Directionality(textDirection:ar?TextDirection.rtl:TextDirection.ltr,child:PopScope(canPop:!full,onPopInvokedWithResult:(didPop,_) {if(!didPop&&full)unawaited(toggleFull());},child:Scaffold(
    appBar:full?null:AppBar(title:Row(children:[Image.asset('assets/brand/logo-full.png',height:30,width:95,fit:BoxFit.contain),const SizedBox(width:8),Expanded(child:Text(title,maxLines:1,overflow:TextOverflow.ellipsis))]),actions:[
      IconButton(tooltip:t('اللغة','Language'),icon:const Icon(Icons.translate),onPressed:chooseLanguage),
      if(ads.privacyRequired)IconButton(tooltip:t('خصوصية الإعلانات','Ad privacy'),icon:const Icon(Icons.privacy_tip_outlined),onPressed:ads.privacyOptions),
    ]),
    body:full?surface():SafeArea(child:ListView(children:[
      AspectRatio(aspectRatio:video?.value.isInitialized==true ? video!.value.aspectRatio.clamp(0.5,2.4).toDouble() : 16/9,child:surface()),
      if(target==null) Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        if(target==null&&externalMedia==null)Text(t('مشغل الفيديو الخاص بك','Your video player'),style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
        if(target==null&&externalMedia==null)Padding(padding:const EdgeInsets.only(top:8,bottom:16),child:Text(t('شغّل الفيديوهات من هاتفك أو عبر رابط مباشر.','Play videos from your phone or a direct link.'))),
        FilledButton.icon(onPressed:enterLink,icon:const Icon(Icons.link),label:Text(t('فتح رابط فيديو','Open video URL'))),
        const SizedBox(height:8),
        OutlinedButton.icon(onPressed:pickLocal,icon:const Icon(Icons.folder_open),label:Text(t('فيديوهات الهاتف','Browse phone videos'))),
      ])),
      if(externalMedia!=null)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[
        const Icon(Icons.speed),const SizedBox(width:8),Text(t('سرعة التشغيل','Playback speed')),const Spacer(),
        DropdownButton<double>(value:speed,items:[0.5,0.75,1.0,1.25,1.5,2.0].map((v)=>DropdownMenuItem(value:v,child:Text('${v}x'))).toList(),onChanged:(v){if(v!=null){setState(()=>speed=v);video?.setPlaybackSpeed(v);}})
      ])),
      if(target!=null)Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:12),
        Row(children:[Text(t('سرعة التشغيل','Playback speed')),const Spacer(),DropdownButton<double>(value:speed,items:[0.5,0.75,1.0,1.25,1.5,2.0].map((v)=>DropdownMenuItem(value:v,child:Text('${v}x'))).toList(),onChanged:(v){if(v!=null){setState(()=>speed=v);video?.setPlaybackSpeed(v);}})]),
        if(episodeIndex>=0) ...[Row(children:[IconButton(onPressed:episodeIndex>0&&!busy?()=>goEpisode(-1):null,icon:const Icon(Icons.skip_previous)),Expanded(child:Text(t('الحلقة ${episodes[episodeIndex]['episode_number']}','Episode ${episodes[episodeIndex]['episode_number']}'),textAlign:TextAlign.center)),IconButton(onPressed:episodeIndex+1<episodes.length&&!busy?()=>goEpisode(1):null,icon:const Icon(Icons.skip_next))]),SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(t('التشغيل التلقائي','Autoplay next episode')),value:autoNext,onChanged:changeAutoNext),OutlinedButton.icon(onPressed:busy?null:chooseEpisode,icon:const Icon(Icons.playlist_play),label:Text(t('كل الحلقات','All episodes'))),],
        const SizedBox(height:12),Text(t('سيرفرات المشاهدة','Playback servers'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        Wrap(spacing:8,runSpacing:8,children:List.generate(sources.length,(i)=>ChoiceChip(label:Text(t('سيرفر ${i+1}','Server ${i+1}')),selected:index==i,onSelected:busy?null:(_)=>select(i)))),
        if(error.isNotEmpty)Padding(padding:const EdgeInsets.only(top:16),child:Text(error,style:const TextStyle(color:Colors.orangeAccent))),
      ])),
      if((target!=null || externalMedia!=null) && video?.value.isInitialized==true) PlayerNativeAd(ads:ads,ar:ar),
    ])),
  )));
}

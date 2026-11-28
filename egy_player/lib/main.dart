import 'dart:async';
import 'dart:convert';
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
        colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark)),
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
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override State<PlayerScreen> createState()=>_PlayerScreenState();
}
class _PlayerScreenState extends State<PlayerScreen> {
  final client=http.Client();
  final ads=PlayerAds();
  void onAdChanged(){if(mounted)setState((){});}
  PlayTarget? target;
  Uri? externalMedia;
  String externalName='';
  VideoPlayerController? video;
  List<Map<String,dynamic>> sources=[];
  int generation=0,index=-1;
  bool get ar => playerLocale.value.languageCode == 'ar';
  bool busy=false,full=false,locked=false,controls=true;
  double speed=1;
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
  Timer? hideTimer;
  String t(String a,String e)=>ar?a:e;
  @override void initState(){
    super.initState();
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
    final op=++generation;
    final old=video;video=null;
    final local=uri.scheme=='content';
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
      candidate=local?VideoPlayerController.contentUri(uri,viewType:VideoViewType.platformView):
        VideoPlayerController.networkUrl(uri,formatHint:formatFor(uri),viewType:VideoViewType.platformView);
      await candidate.initialize().timeout(const Duration(seconds:25));
      if(!mounted||generation!=op){await candidate.dispose();return;}
      await candidate.setPlaybackSpeed(speed);
      await ads.finishStartup();
      if(!mounted||generation!=op){await candidate.dispose();return;}
      await candidate.play();
      if(!mounted||generation!=op){await candidate.dispose();return;}
      setState((){video=candidate;if(name.isNotEmpty)setTitles(name,name);externalName=name;busy=false;});
      showControls();
    }catch(_){
      await candidate?.dispose();
      unawaited(ads.finishStartup());
      if(mounted&&generation==op)setState((){busy=false;setError('تعذر تشغيل الفيديو. تحقق من الرابط أو صيغة الملف.','Unable to play video. Check the URL or file format.');});
    }
  }
  Future<void> retryCurrent() async {
    final uri=externalMedia;
    if(uri!=null){await playExternal(uri);return;}
    final current=target;
    if(current==null)return;
    if(sources.isNotEmpty){await select(index<0?0:index);return;}
    await openTarget(Uri(scheme:'egyplayer',host:'play',queryParameters:{
      'type':current.type,'id':current.id.toString(),'lang':ar?'ar':'en'}).toString());
  }
  Future<Map<String,dynamic>> request(String path,{Map<String,dynamic>? body}) async {
    final uri=Uri.parse(origin+path);
    final response=await (body==null?client.get(uri,headers:{'Accept':'application/json'}):
      client.post(uri,headers:{'Accept':'application/json','Content-Type':'application/json'},body:jsonEncode(body)))
      .timeout(const Duration(seconds:35));
    final data=object(jsonDecode(utf8.decode(response.bodyBytes)));
    if(response.statusCode!=200||data['ok']!=true) throw StateError('unavailable');
    return data;
  }
  Future<void> openTarget(String? input,{bool initial=false}) async {
    final next=PlayTarget.parse(input);
    if(next==null||!mounted){if(initial)unawaited(ads.finishStartup());return;}
    if(!initial)unawaited(ads.finishStartup());
    final op=++generation;
    final old=video;video=null;
    setState((){target=next;externalMedia=null;externalName='';setTitles('','');sources=[];index=-1;busy=true;clearError();locked=false;});
    await old?.dispose();
    try {
      final path='/api/v1/mobile/guest/player?type=${next.type}&id=${next.id}';
      final data=await request(path);
      if(!mounted||generation!=op)return;
      final items=(data['sources'] as List? ?? []).map(object).where((m)=>m['id'] is num).toList();
      setState((){setTitles((data['title_ar']??'').toString(),(data['title_en']??'').toString());sources=items;busy=false;});
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
    final resume=old?.value.isInitialized==true?old!.value.position:Duration.zero;
    video=null;
    setState((){busy=true;index=next;clearError();controls=true;});
    await old?.dispose();
    final end=automatic?(next+3).clamp(0,sources.length).toInt():next+1;
    for(var i=next;i<end;i++){
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
        await ads.finishStartup();
        if(!mounted||generation!=op){await candidate.dispose();return;}
        await candidate.play();
        if(!mounted||generation!=op){await candidate.dispose();return;}
        setState((){video=candidate;index=i;busy=false;});
        showControls();return;
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
    generation++;hideTimer?.cancel();bridge.setMethodCallHandler(null);video?.dispose();client.close();
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
      final duration=state.duration.inMilliseconds;
      final position=state.position.inMilliseconds.clamp(0,duration>0?duration:0).toDouble();
      return GestureDetector(onTap:()=>locked?showControls():(controls?setState(()=>controls=false):showControls()),
        child:Stack(fit:StackFit.expand,children:[
          const ColoredBox(color:Colors.black),
          Center(child:AspectRatio(aspectRatio:state.aspectRatio>0?state.aspectRatio:16/9,child:VideoPlayer(v))),
          if(state.isBuffering)const Center(child:CircularProgressIndicator(color:red)),
          if(state.hasError)Center(child:FilledButton.icon(onPressed:retryCurrent,icon:const Icon(Icons.refresh),label:Text(t('إعادة التشغيل','Retry playback')))),
          if(controls&&!state.hasError)DecoratedBox(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0x66000000),Colors.transparent,Color(0xaa000000)])),child:Column(children:[
            Row(children:[
              IconButton(tooltip:locked?t('إلغاء القفل','Unlock'):t('قفل الشاشة','Lock controls'),onPressed:()=>setState(()=>locked=!locked),icon:Icon(locked?Icons.lock:Icons.lock_open)),
              const Spacer(),
              if(!locked)IconButton(tooltip:full?t('الخروج من ملء الشاشة','Exit fullscreen'):t('ملء الشاشة','Fullscreen'),onPressed:toggleFull,icon:Icon(full?Icons.fullscreen_exit:Icons.fullscreen)),
            ]),
            const Spacer(),
            if(!locked)Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              IconButton(tooltip:t('رجوع 10 ثوانٍ','Back 10 seconds'),iconSize:36,onPressed:()=>seek(-10),icon:const Icon(Icons.replay_10)),
              IconButton(tooltip:state.isPlaying?t('إيقاف مؤقت','Pause'):t('تشغيل','Play'),iconSize:56,onPressed:()async{state.isPlaying?await v.pause():await v.play();showControls();},icon:Icon(state.isPlaying?Icons.pause_circle_filled:Icons.play_circle_fill)),
              IconButton(tooltip:t('تقديم 10 ثوانٍ','Forward 10 seconds'),iconSize:36,onPressed:()=>seek(10),icon:const Icon(Icons.forward_10)),
            ]),
            const Spacer(),
            if(!locked&&duration>0)Slider(value:position,max:duration.toDouble(),activeColor:red,onChanged:(x)=>v.seekTo(Duration(milliseconds:x.round()))),
            if(!locked)Padding(padding:const EdgeInsets.fromLTRB(12,0,12,8),child:Row(children:[
              Text(stamp(state.position)),const Spacer(),Text(stamp(state.duration)),
            ])),
          ]))
        ]));
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
        const SizedBox(height:12),Text(t('سيرفرات المشاهدة','Playback servers'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        Wrap(spacing:8,runSpacing:8,children:List.generate(sources.length,(i)=>ChoiceChip(label:Text(t('سيرفر ${i+1}','Server ${i+1}')),selected:index==i,onSelected:busy?null:(_)=>select(i)))),
        if(error.isNotEmpty)Padding(padding:const EdgeInsets.only(top:16),child:Text(error,style:const TextStyle(color:Colors.orangeAccent))),
      ])),
      if((target!=null || externalMedia!=null) && video?.value.isInitialized==true) PlayerNativeAd(ads:ads,ar:ar),
    ])),
  )));
}

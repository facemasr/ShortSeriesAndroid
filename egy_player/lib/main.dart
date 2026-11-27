import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'player_ads.dart';

const origin = 'https://egyshow.com';
const bridge = MethodChannel('com.egyshow.player/launch');
const red = Color(0xffe50914);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(debugShowCheckedModeBanner: false, title: 'EGY Player',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff09090c),
      colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark)),
    home: const PlayerScreen()));
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
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override State<PlayerScreen> createState()=>_PlayerScreenState();
}
class _PlayerScreenState extends State<PlayerScreen> {
  final client=http.Client();
  final ads=PlayerAds();
  void onAdChanged(){if(mounted)setState((){});}
  PlayTarget? target;
  VideoPlayerController? video;
  List<Map<String,dynamic>> sources=[];
  int generation=0,index=-1;
  bool ar=true,busy=false,full=false,locked=false,controls=true;
  double speed=1;
  String title='EGY Player',error='';
  Timer? hideTimer;
  String t(String a,String e)=>ar?a:e;
  @override void initState(){
    super.initState();
    ads.addListener(onAdChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)unawaited(ads.prepare());});
    bridge.setMethodCallHandler((call) async {
      if(call.method=='open') await openTarget(call.arguments as String?);
    });
    unawaited(bridge.invokeMethod<String>('initialLink').then(openTarget)
      .catchError((Object e){}));
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
  Future<void> openTarget(String? input) async {
    final next=PlayTarget.parse(input);
    if(next==null||!mounted)return;
    final op=++generation;
    final old=video;video=null;
    setState((){target=next;ar=next.ar;title='EGY Player';sources=[];index=-1;busy=true;error='';locked=false;});
    await old?.dispose();
    try {
      final path='/api/v1/mobile/guest/player?type=${next.type}&id=${next.id}';
      final data=await request(path);
      if(!mounted||generation!=op)return;
      final items=(data['sources'] as List? ?? []).map(object).where((m)=>m['id'] is num).toList();
      setState((){title=(data[ar?'title_ar':'title_en']??data[ar?'title_en':'title_ar']??'EGY Player').toString();sources=items;busy=false;});
      if(items.isEmpty){setState(()=>error=t('لا توجد سيرفرات مشاهدة متاحة','No available servers'));return;}
      await select(0,automatic:true);
    }catch(_){if(mounted&&generation==op)setState((){busy=false;error=t('تعذر تحميل بيانات المشاهدة','Unable to load playback data');});}
  }
  Future<void> select(int next,{bool automatic=false}) async {
    final current=target;
    if(current==null||next<0||next>=sources.length)return;
    final op=++generation;
    final old=video;
    final resume=old?.value.isInitialized==true?old!.value.position:Duration.zero;
    video=null;
    setState((){busy=true;index=next;error='';controls=true;});
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
        candidate=VideoPlayerController.networkUrl(uri,formatHint:format);
        await candidate.initialize().timeout(const Duration(seconds:25));
        if(!mounted||generation!=op){await candidate.dispose();return;}
        if(resume>Duration.zero&&resume<candidate.value.duration)await candidate.seekTo(resume);
        await candidate.setPlaybackSpeed(speed);
        await candidate.play();
        if(!mounted||generation!=op){await candidate.dispose();return;}
        setState((){video=candidate;index=i;busy=false;});
        showControls();return;
      }catch(_){
        await candidate?.dispose();
        if(!mounted||generation!=op)return;
      }
    }
    if(mounted&&generation==op)setState((){busy=false;error=t('تعذر تشغيل السيرفر. جرّب سيرفراً آخر.','Playback unavailable. Try another server.');});
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
    await SystemChrome.setPreferredOrientations(full?[DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]:[]);
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
        if(target!=null&&error.isNotEmpty)TextButton.icon(onPressed:()=>sources.isEmpty?
          openTarget(Uri(scheme:'egyplayer',host:'play',queryParameters:{'type':target!.type,'id':'${target!.id}','lang':ar?'ar':'en'}).toString()):select(index<0?0:index),icon:const Icon(Icons.refresh),label:Text(t('إعادة المحاولة','Retry')))
      ])));
    return ValueListenableBuilder<VideoPlayerValue>(valueListenable:v,builder:(context,state,_){
      final duration=state.duration.inMilliseconds;
      final position=state.position.inMilliseconds.clamp(0,duration>0?duration:0).toDouble();
      return GestureDetector(onTap:()=>locked?showControls():(controls?setState(()=>controls=false):showControls()),
        child:Stack(fit:StackFit.expand,children:[
          const ColoredBox(color:Colors.black),
          Center(child:AspectRatio(aspectRatio:state.aspectRatio>0?state.aspectRatio:16/9,child:VideoPlayer(v))),
          if(state.isBuffering)const Center(child:CircularProgressIndicator(color:red)),
          if(state.hasError)Center(child:FilledButton.icon(onPressed:()=>select(index<0?0:index),icon:const Icon(Icons.refresh),label:Text(t('إعادة تشغيل السيرفر','Retry server')))),
          if(controls&&!state.hasError)DecoratedBox(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0x66000000),Colors.transparent,Color(0xaa000000)])),child:Column(children:[
            Row(children:[
              IconButton(onPressed:()=>setState(()=>locked=!locked),icon:Icon(locked?Icons.lock:Icons.lock_open)),
              const Spacer(),
              if(!locked)IconButton(onPressed:toggleFull,icon:Icon(full?Icons.fullscreen_exit:Icons.fullscreen)),
            ]),
            const Spacer(),
            if(!locked)Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              IconButton(iconSize:36,onPressed:()=>seek(-10),icon:const Icon(Icons.replay_10)),
              IconButton(iconSize:56,onPressed:()async{state.isPlaying?await v.pause():await v.play();showControls();},icon:Icon(state.isPlaying?Icons.pause_circle_filled:Icons.play_circle_fill)),
              IconButton(iconSize:36,onPressed:()=>seek(10),icon:const Icon(Icons.forward_10)),
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
    appBar:full?null:AppBar(title:Text(title,maxLines:1,overflow:TextOverflow.ellipsis),actions:[
      if(ads.privacyRequired)IconButton(tooltip:t('خصوصية الإعلانات','Ad privacy'),icon:const Icon(Icons.privacy_tip_outlined),onPressed:ads.privacyOptions),
    ]),
    body:full?surface():SafeArea(child:ListView(children:[
      AspectRatio(aspectRatio:16/9,child:surface()),
      if(target==null)Padding(padding:const EdgeInsets.all(28),child:Text(t('افتح فيلماً أو حلقة من تطبيق EGYSHOW للبدء.','Open a movie or episode in EGYSHOW to start.'),textAlign:TextAlign.center)),
      if(target!=null)Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:12),
        Row(children:[Text(t('سرعة التشغيل','Playback speed')),const Spacer(),DropdownButton<double>(value:speed,items:[0.5,0.75,1.0,1.25,1.5,2.0].map((v)=>DropdownMenuItem(value:v,child:Text('${v}x'))).toList(),onChanged:(v){if(v!=null){setState(()=>speed=v);video?.setPlaybackSpeed(v);}})]),
        const SizedBox(height:12),Text(t('سيرفرات المشاهدة','Playback servers'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        Wrap(spacing:8,runSpacing:8,children:List.generate(sources.length,(i)=>ChoiceChip(label:Text(t('سيرفر ${i+1}','Server ${i+1}')),selected:index==i,onSelected:busy?null:(_)=>select(i)))),
        if(error.isNotEmpty)Padding(padding:const EdgeInsets.only(top:16),child:Text(error,style:const TextStyle(color:Colors.orangeAccent))),
      ])),
      if(target!=null && video?.value.isInitialized==true) PlayerNativeAd(ads:ads,ar:ar),
    ])),
  )));
}

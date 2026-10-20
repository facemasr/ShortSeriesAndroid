import 'package:flutter/material.dart';
import 'native_api.dart';
import 'native_sections.dart';

const accentRed = Color(0xFFE50914);
const slate = Color(0xFF17171C);

/// Native rails matching the actual sections on EGYSHOW's website.
/// These consume public JSON endpoints; no site WebView is embedded here.
class HomeExtras extends StatefulWidget {
  const HomeExtras({super.key, required this.api, required this.ar,
    required this.openMedia, required this.play, required this.openTab});
  final EgyApi api;
  final bool ar;
  final void Function(Media) openMedia;
  final void Function(String, int, String, [String]) play;
  final void Function(int) openTab;
  @override State<HomeExtras> createState() => _HomeExtrasState();
}

class _HomeExtrasState extends State<HomeExtras> {
  List<Media> movies = [], series = [], shorts = [];
  List<MatchInfo> matches = [];
  List<LiveChannel> channels = [];
  List<Map<String,dynamic>> latestEpisodes = [];
  List<YoutubeClip> youtube = [];
  bool loading = true;

  @override void initState() { super.initState(); _fetch(); }
  @override void didUpdateWidget(covariant HomeExtras old) {
    super.didUpdateWidget(old);
    if (old.ar != widget.ar) _fetchYoutube();
  }
  String t(String ar, String en) => widget.ar ? ar : en;

  Future<void> _fetchYoutube() async {
    try {
      final j = await widget.api.call('/api/v1/youtube/discover?lang='
          + (widget.ar ? 'ar' : 'en') + '&category=music');
      if (mounted) setState(() => youtube = asList(j['items'])
          .map((v) => YoutubeClip(asMap(v))).take(10).toList());
    } catch (_) {}
  }

  Future<void> _fetch() async {
    final tasks = <Future<void>>[
      () async {try {movies = await widget.api.catalog('movie');} catch (_){}}(),
      () async {try {series = await widget.api.catalog('series');} catch (_){}}(),
      () async {try {shorts = await widget.api.catalog('short_series');} catch (_){}}(),
      () async {
        try {channels = await widget.api.live();} catch (_){}
      }(),
      () async {
        try {
          final j = await widget.api.call('/matches/api?day=today');
          matches = asList(j['matches']).map((v) => MatchInfo(asMap(v)))
              .take(12).toList();
        } catch (_) {}
      }(),
      () async {
        try {
          final j = await widget.api.call('/api/v1/home');
          latestEpisodes = asList(j['latestEpisodes']).map(asMap)
              .take(12).toList();
        } catch (_) {}
      }(),
      _fetchYoutube(),
    ];
    await Future.wait(tasks);
    if (mounted) setState(() => loading = false);
  }

  Widget _image(String url, {BoxFit fit = BoxFit.cover}) =>
      url.startsWith('https://') ? Image.network(url, fit: fit,
        errorBuilder: (_, __, ___) => const ColoredBox(color: slate,
          child: Center(child: Icon(Icons.movie_outlined, color: Colors.white30)))) :
      const ColoredBox(color: slate,
        child: Center(child: Icon(Icons.movie_outlined, color: Colors.white30)));

  Widget _heading(String title, int section, {IconData? icon}) =>
    Padding(padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, color: accentRed, size: 19),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(title, style:
          const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => widget.openTab(section),
          child: Text(t('عرض الكل', 'See all'))),
      ]));

  Widget _posters(String label, int section, List<Media> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
      _heading(label, section),
      SizedBox(height: 218,child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: list.length > 14 ? 14 : list.length,
        separatorBuilder: (_,__) => const SizedBox(width: 10),
        itemBuilder: (_,i) {
          final m=list[i];
          return GestureDetector(onTap: () => widget.openMedia(m),
            child: SizedBox(width: 119, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(width: double.infinity, child: _image(m.poster)))),
                const SizedBox(height: 6),
                Text(m.title(widget.ar),maxLines:1,overflow:TextOverflow.ellipsis,
                  style: const TextStyle(fontSize:12.5,fontWeight: FontWeight.w700)),
              ])));
        },
      )),
    ]);
  }

  Widget _matchRail() {
    if (matches.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      _heading('⚽ ' + t('المباريات', 'Matches'),5),
      SizedBox(height: 138,child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: matches.length,
        separatorBuilder: (_,__) => const SizedBox(width: 9),
        itemBuilder: (ctx,i) {
          final m=matches[i];
          return InkWell(
            onTap: () => Navigator.push(context,MaterialPageRoute(
              builder: (_) => SiteWatch(title:m.title,
                path:'/app?match_day=today&match_id='+
                  Uri.encodeComponent(m.id)))),
            child: Container(width: 260, padding:const EdgeInsets.all(12),
              decoration:BoxDecoration(color:slate,
                borderRadius:BorderRadius.circular(12)),
              child: Column(children: [
                Row(children: [
                  Expanded(child:Text(m.home,textAlign:TextAlign.center,maxLines:2,
                      overflow:TextOverflow.ellipsis)),
                  Padding(padding:const EdgeInsets.symmetric(horizontal:7),
                    child: Text(m.score.isEmpty?'VS':m.score,
                      style:const TextStyle(color:accentRed,
                        fontWeight:FontWeight.bold))),
                  Expanded(child:Text(m.away,textAlign:TextAlign.center,maxLines:2,
                      overflow:TextOverflow.ellipsis)),
                ]),
                const Spacer(),
                Text(m.time+'  •  '+m.state,
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style: const TextStyle(fontSize:12,color:Colors.white70)),
                const SizedBox(height:10),
                const Icon(Icons.play_circle_outline,color:accentRed),
              ])));
        },
      )),
    ]);
  }

  Widget _episodes() {
    if (latestEpisodes.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      _heading(t('أحدث الحلقات','Latest episodes'),2,icon:Icons.video_library_outlined),
      SizedBox(height:172,child:ListView.separated(
        scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:12),
        itemCount:latestEpisodes.length,
        separatorBuilder:(_,__)=>const SizedBox(width:10),
        itemBuilder:(ctx,i) {
          final item=latestEpisodes[i];
          final id=numId(item['id']);
          final mediaId=numId(item['media_id']);
          final title=txt(item[widget.ar?'media_title_ar':'media_title_en']);
          final ep=numId(item['episode_number']);
          final image=txt(item['still_path']).isNotEmpty
            ? txt(item['still_path']):txt(item['poster_path']);
          return InkWell(
            onTap:()=>widget.play('episode',id,title,mediaId.toString()),
            child:SizedBox(width:190,child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                ClipRRect(borderRadius:BorderRadius.circular(9),
                  child:SizedBox(width:190,height:108,child:_image(image))),
                const SizedBox(height:6),
                Text(title,maxLines:1,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontWeight:FontWeight.bold)),
                Text(t('الحلقة ','Episode ')+ep.toString(),
                  style:const TextStyle(color:Colors.white60,fontSize:12)),
              ])));
        },
      )),
    ]);
  }

  Widget _live() {
    if(channels.isEmpty) return const SizedBox.shrink();
    return Column(children:[
      _heading(t('القنوات المباشرة','Live TV'),4,icon:Icons.live_tv),
      SizedBox(height:140,child:ListView.separated(
        scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:12),
        itemCount:channels.length > 15 ? 15 : channels.length,
        separatorBuilder:(_,__)=>const SizedBox(width:9),
        itemBuilder:(ctx,i) {
          final ch=channels[i];
          return InkWell(onTap:()=>widget.play('channel',ch.id,ch.title(widget.ar)),
            child:Container(width:145,padding:const EdgeInsets.all(9),
              decoration:BoxDecoration(color:slate,
                borderRadius:BorderRadius.circular(12)),
              child:Column(children:[
                Expanded(child:_image(ch.logo,fit:BoxFit.contain)),
                Text(ch.title(widget.ar),maxLines:1,
                  overflow:TextOverflow.ellipsis),
              ])));
        },
      )),
    ]);
  }

  Widget _youtube() {
    if(youtube.isEmpty) return const SizedBox.shrink();
    return Column(children:[
      _heading('YouTube',6,icon:Icons.smart_display_outlined),
      SizedBox(height:180,child:ListView.separated(
        scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:12),
        itemCount:youtube.length,
        separatorBuilder:(_,__)=>const SizedBox(width:9),
        itemBuilder:(ctx,i) {
          final v=youtube[i];
          return InkWell(onTap:()=>Navigator.push(context,
            MaterialPageRoute(builder:(_)=>
              SiteWatch(title:v.title,path:v.path))),
            child:SizedBox(width:210,child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                ClipRRect(borderRadius:BorderRadius.circular(9),
                  child:SizedBox(height:119,width:210,child:_image(v.picture))),
                const SizedBox(height:5),
                Text(v.title,maxLines:2,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontWeight:FontWeight.w600,fontSize:12)),
              ])));
        },
      )),
    ]);
  }

  @override Widget build(BuildContext context) {
    if(loading) return const Padding(padding:EdgeInsets.all(22),
      child:Center(child:CircularProgressIndicator(color:accentRed)));
    return Column(children:[
      _matchRail(),
      _posters(t('الأفلام','Movies'),1,movies),
      _posters(t('المسلسلات','Series'),2,series),
      _episodes(),
      _posters(t('المسلسلات القصيرة','Short series'),3,shorts),
      _live(),
      _youtube(),
    ]);
  }
}

part of 'main.dart';

/// Central AdMob controller for SHORT SERIES TV.
///
/// Production IDs can come from GitHub Actions --dart-define values or from
/// app_config.admob. When no production ID is configured, Google demo ad units
/// are used so development builds never generate invalid traffic.
class AdMobService {
  AdMobService._();
  static final I=AdMobService._();

  static const _testBanner='ca-app-pub-3940256099942544/9214589741';
  static const _testInterstitial='ca-app-pub-3940256099942544/1033173712';

  static const _defineBanner=String.fromEnvironment('ADMOB_BANNER_ID');
  static const _defineInterstitial=String.fromEnvironment('ADMOB_INTERSTITIAL_ID');
  static const _defineEnabled=String.fromEnvironment('ADMOB_ENABLED');

  InterstitialAd? _interstitial;
  bool _loadingInterstitial=false;
  bool _showingInterstitial=false;
  bool _initialized=false;
  int _playStarts=0;
  int _episodeTransitions=0;

  Map<String,dynamic> get _config{
    final raw=Api.I.config['admob'];
    return raw is Map?Map<String,dynamic>.from(raw):<String,dynamic>{};
  }

  bool _asBool(dynamic value,bool fallback){
    if(value==null)return fallback;
    if(value is bool)return value;
    final v=value.toString().trim().toLowerCase();
    if(const {'1','true','yes','on','enabled'}.contains(v))return true;
    if(const {'0','false','no','off','disabled'}.contains(v))return false;
    return fallback;
  }

  int _asInt(dynamic value,int fallback){
    if(value is num)return value.toInt();
    return int.tryParse((value??'').toString())??fallback;
  }

  bool get enabled{
    final remote=_config['enabled'];
    if(remote!=null)return _asBool(remote,true);
    if(_defineEnabled.trim().isNotEmpty)return _asBool(_defineEnabled,true);
    return true;
  }

  bool get testMode{
    final remote=_config['test_mode'];
    if(remote!=null)return _asBool(remote,true);
    final hasProductionId=
        _defineBanner.trim().startsWith('ca-app-pub-')||
        _defineInterstitial.trim().startsWith('ca-app-pub-');
    return !hasProductionId;
  }

  String get bannerId{
    final remote=(_config['banner_id_android']??_config['banner_id']??'')
        .toString().trim();
    if(!testMode&&remote.startsWith('ca-app-pub-'))return remote;
    if(!testMode&&_defineBanner.trim().startsWith('ca-app-pub-')){
      return _defineBanner.trim();
    }
    return _testBanner;
  }

  String get interstitialId{
    final remote=(_config['interstitial_id_android']??_config['interstitial_id']??'')
        .toString().trim();
    if(!testMode&&remote.startsWith('ca-app-pub-'))return remote;
    if(!testMode&&_defineInterstitial.trim().startsWith('ca-app-pub-')){
      return _defineInterstitial.trim();
    }
    return _testInterstitial;
  }

  int get minIntervalSeconds=>
      _asInt(_config['interstitial_min_interval_seconds'],420).clamp(60,3600);

  int get playbackEvery=>
      _asInt(_config['playback_every'],1).clamp(1,20);

  int get episodeEvery=>
      _asInt(_config['episode_every'],2).clamp(1,20);

  Future<void> initialize() async{
    if(_initialized||!Platform.isAndroid)return;
    _initialized=true;
    await MobileAds.instance.initialize();
    unawaited(preloadInterstitial());
  }

  Future<void> preloadInterstitial() async{
    if(!Platform.isAndroid||!enabled||_loadingInterstitial||
       _interstitial!=null||_showingInterstitial)return;

    _loadingInterstitial=true;
    InterstitialAd.load(
      adUnitId:interstitialId,
      request:const AdRequest(),
      adLoadCallback:InterstitialAdLoadCallback(
        onAdLoaded:(ad){
          _loadingInterstitial=false;
          _interstitial=ad;
        },
        onAdFailedToLoad:(error){
          _loadingInterstitial=false;
          _interstitial=null;
        },
      ),
    );
  }

  Future<bool> _intervalAllows() async{
    final raw=await Api.I.store.read(key:'admob_last_interstitial_ms');
    final last=int.tryParse(raw??'')??0;
    if(last<=0)return true;
    final elapsed=DateTime.now().millisecondsSinceEpoch-last;
    return elapsed>=minIntervalSeconds*1000;
  }

  Future<void> _markShown() async{
    await Api.I.store.write(
      key:'admob_last_interstitial_ms',
      value:DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<bool> maybeShowPlaybackInterstitial({
    required bool betweenEpisodes,
  }) async{
    if(!Platform.isAndroid||!enabled||_showingInterstitial)return false;

    if(betweenEpisodes){
      _episodeTransitions++;
      if(_episodeTransitions%episodeEvery!=0){
        unawaited(preloadInterstitial());
        return false;
      }
    }else{
      _playStarts++;
      if(_playStarts%playbackEvery!=0){
        unawaited(preloadInterstitial());
        return false;
      }
    }

    if(!await _intervalAllows()){
      unawaited(preloadInterstitial());
      return false;
    }

    final ad=_interstitial;
    if(ad==null){
      unawaited(preloadInterstitial());
      return false;
    }

    _interstitial=null;
    _showingInterstitial=true;
    final done=Completer<bool>();

    ad.fullScreenContentCallback=FullScreenContentCallback(
      onAdShowedFullScreenContent:(_){
        unawaited(_markShown());
      },
      onAdDismissedFullScreenContent:(shownAd){
        shownAd.dispose();
        _showingInterstitial=false;
        if(!done.isCompleted)done.complete(true);
        unawaited(preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent:(failedAd,error){
        failedAd.dispose();
        _showingInterstitial=false;
        if(!done.isCompleted)done.complete(false);
        unawaited(preloadInterstitial());
      },
    );

    ad.show();
    return done.future;
  }
}

class AdMobBanner extends StatefulWidget {
  final String placement;
  final bool compact;

  const AdMobBanner({
    super.key,
    required this.placement,
    this.compact=false,
  });

  @override
  State<AdMobBanner> createState()=>_AdMobBannerState();
}

class _AdMobBannerState extends State<AdMobBanner>{
  BannerAd? _ad;
  int _loadedWidth=0;
  bool _loading=false;

  Future<void> _load(int width) async{
    if(!Platform.isAndroid||!AdMobService.I.enabled||width<=0||
       _loading||(_ad!=null&&_loadedWidth==width))return;

    _loading=true;
    final old=_ad;
    _ad=null;
    old?.dispose();

    final AdSize? size=widget.compact
      ?AdSize.banner
      :await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);

    if(size==null){
      _loading=false;
      return;
    }

    final banner=BannerAd(
      adUnitId:AdMobService.I.bannerId,
      request:const AdRequest(),
      size:size,
      listener:BannerAdListener(
        onAdLoaded:(ad){
          if(!mounted){
            ad.dispose();
            return;
          }
          setState((){
            _ad=ad as BannerAd;
            _loadedWidth=width;
            _loading=false;
          });
        },
        onAdFailedToLoad:(ad,error){
          ad.dispose();
          if(mounted)setState(()=>_loading=false);
        },
      ),
    );
    banner.load();
  }

  @override
  void dispose(){
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    if(!Platform.isAndroid||!AdMobService.I.enabled){
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder:(context,constraints){
        final screen=MediaQuery.sizeOf(context).width;
        final width=(constraints.maxWidth.isFinite?constraints.maxWidth:screen)
            .floor()
            .clamp(1,screen.floor());

        if(_ad==null&& !_loading){
          WidgetsBinding.instance.addPostFrameCallback((_){
            if(mounted)unawaited(_load(width));
          });
        }

        final ad=_ad;
        if(ad==null)return const SizedBox.shrink();

        return Semantics(
          label:Api.I.ar?'إعلان':'Advertisement',
          child:Padding(
            padding:const EdgeInsets.symmetric(vertical:8),
            child:Column(
              mainAxisSize:MainAxisSize.min,
              children:[
                Text(
                  Api.I.ar?'إعلان':'Ad',
                  style:const TextStyle(
                    color:Colors.white38,
                    fontSize:10,
                    fontWeight:FontWeight.w700,
                  ),
                ),
                const SizedBox(height:4),
                SizedBox(
                  width:ad.size.width.toDouble(),
                  height:ad.size.height.toDouble(),
                  child:AdWidget(ad:ad),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

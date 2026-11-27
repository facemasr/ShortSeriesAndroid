import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const productionUnit = 'ca-app-pub-8994881827340014/8826073622';
const testUnit = 'ca-app-pub-3940256099942544/2247696110';
const liveAds = bool.fromEnvironment('EGY_LIVE_ADS', defaultValue: false);
String get playerAdUnit => kReleaseMode && liveAds ? productionUnit : testUnit;

const productionOpenUnit = 'ca-app-pub-8994881827340014/6863748552';
const testOpenUnit = 'ca-app-pub-3940256099942544/9257395921';
String get playerOpenUnit => kReleaseMode && liveAds ? productionOpenUnit : testOpenUnit;

class PlayerAds extends ChangeNotifier {
  AppOpenAd? _openAd;
  DateTime? _openLoadedAt;
  bool _openRequested = false, _startupWindow = false, _startupClosed = false;
  Completer<void>? _openShowing;
  int _openEpoch = 0;

  // Only the initial launch may open this window, while a real stream loads.
  void beginStartup() {
    if (_closed || _startupClosed) return;
    _startupWindow = true;
    _tryShowOpen();
  }

  Future<void> finishStartup() async {
    _startupWindow = false;
    _startupClosed = true;
    _openEpoch++;
    _openAd?.dispose();
    _openAd = null;
    final showing = _openShowing;
    if (showing != null) await showing.future;
  }

  void _loadOpen() {
    if (_closed || _startupClosed || _openRequested) return;
    _openRequested = true;
    final epoch = _openEpoch;
    unawaited(AppOpenAd.load(
      adUnitId: playerOpenUnit,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (loaded) {
          if (_closed || _startupClosed || epoch != _openEpoch) {
            loaded.dispose();
            return;
          }
          _openAd = loaded;
          _openLoadedAt = DateTime.now();
          _tryShowOpen();
        },
        onAdFailedToLoad: (_) {},
      ),
    ).catchError((Object _) {}));
  }

  void _tryShowOpen() {
    final loaded = _openAd;
    final time = _openLoadedAt;
    if (_closed || _startupClosed || !_startupWindow ||
        _openShowing != null || loaded == null || time == null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (DateTime.now().difference(time) >= const Duration(hours: 4)) {
      _openAd = null;
      loaded.dispose();
      return;
    }
    _openAd = null;
    _startupClosed = true;
    _startupWindow = false;
    final showing = Completer<void>();
    _openShowing = showing;
    bool completed = false;
    void complete() {
      if (completed) return;
      completed = true;
      loaded.dispose();
      _openShowing = null;
      if (!showing.isCompleted) showing.complete();
    }
    loaded.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (_) => complete(),
      onAdFailedToShowFullScreenContent: (_, __) => complete(),
    );
    unawaited(loaded.show().catchError((Object _) { complete(); }));
  }

  NativeAd? ad;
  bool ready = false, privacyRequired = false, _closed = false, _loading = false;
  bool _initialized = false;
  int _generation = 0;
  Future<void> prepare() async {
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          ConsentForm.loadAndShowConsentFormIfRequired((_) {
            if (!done.isCompleted) done.complete();
          });
        },
        (_) { if (!done.isCompleted) done.complete(); },
      );
      await done.future.timeout(const Duration(seconds: 45));
      await _applyConsent();
    } catch (_) {
      // Ads must never prevent playback.
    }
  }
  Future<void> _applyConsent() async {
    if (_closed) return;
    final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    if (_closed) return;
    privacyRequired = status == PrivacyOptionsRequirementStatus.required;
    final permitted = await ConsentInformation.instance.canRequestAds();
    if (_closed) return;
    if (!permitted) {
      unawaited(finishStartup());
      _generation++;
      final old = ad;
      ad = null; ready = false; _loading = false;
      notifyListeners();
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      return;
    }
    notifyListeners();
    if (!_initialized) {
      await MobileAds.instance.initialize();
      if (_closed) return;
      _initialized = true;
    }
    _loadOpen();
    if (ad != null || _loading) return;
    _loading = true;
    final op = ++_generation;
    try {
      final request = NativeAd(
        adUnitId: playerAdUnit,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
          mainBackgroundColor: const Color(0xff17171c),
          cornerRadius: 12,
        ),
        listener: NativeAdListener(
          onAdLoaded: (loaded) {
            if (_closed || op != _generation) { loaded.dispose(); return; }
            _loading = false; ad = loaded as NativeAd; ready = true;
            notifyListeners();
          },
          onAdFailedToLoad: (failed, error) {
            failed.dispose();
            if (!_closed && op == _generation) { _loading = false; }
          },
        ),
      );
      await request.load();
    } catch (_) { if (!_closed && op == _generation) _loading = false; }
  }
  void privacyOptions() {
    ConsentForm.showPrivacyOptionsForm((error) {
      if (_closed || error != null) return;
      unawaited(finishStartup());
      final old = ad;
      _generation++;
      ad = null; ready = false; _loading = false;
      notifyListeners();
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      unawaited(_applyConsent().catchError((Object _) {}));
    });
  }
  @override void dispose() {
    _closed = true; _generation++;
    unawaited(finishStartup());
    ad?.dispose(); ad = null;
    super.dispose();
  }
}

class PlayerNativeAd extends StatelessWidget {
  const PlayerNativeAd({super.key, required this.ads, required this.ar});
  final PlayerAds ads;
  final bool ar;
  @override Widget build(BuildContext context) {
    final ad = ads.ad;
    if (!ads.ready || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16,24,16,24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'إعلان' : 'Advertisement',
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SizedBox(height: 320, width: double.infinity,
            child: AdWidget(ad: ad)),
        )),
      ]),
    );
  }
}

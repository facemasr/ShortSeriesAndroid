part of 'main.dart';

enum AdAgeGroup { child, teen, adult, unknown }

enum AdMembershipTier { free, premium, vip }

enum AdSourceType {
  none,
  admobBanner,
  admobNative,
  admobInterstitial,
  admobRewarded,
  appOpen,
  privateImage,
  privateVideo,
  vast,
  vmap,
}

class AgePolicy {
  const AgePolicy._();

  static AdAgeGroup classify(DateTime birthDate, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final current = DateTime(today.year, today.month, today.day);
    final birth = DateTime(birthDate.year, birthDate.month, birthDate.day);
    if (birth.isAfter(current)) {
      throw ArgumentError.value(
        birthDate,
        'birthDate',
        'Birth date cannot be in the future',
      );
    }

    var age = current.year - birth.year;
    final birthdayReached = current.month > birth.month ||
        (current.month == birth.month && current.day >= birth.day);
    if (!birthdayReached) age--;

    if (age < 13) return AdAgeGroup.child;
    if (age < 18) return AdAgeGroup.teen;
    return AdAgeGroup.adult;
  }
}

class AdProfileStore {
  AdProfileStore._({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<void> Function(String key) delete,
  })  : _read = read,
        _write = write,
        _delete = delete;

  static final AdProfileStore I = AdProfileStore._(
    read: (key) => Api.I.store.read(key: key),
    write: (key, value) => Api.I.store.write(key: key, value: value),
    delete: (key) => Api.I.store.delete(key: key),
  );

  factory AdProfileStore.memory(Map<String, String> values) {
    return AdProfileStore._(
      read: (key) async => values[key],
      write: (key, value) async {
        values[key] = value;
      },
      delete: (key) async {
        values.remove(key);
      },
    );
  }

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;

  Future<AdAgeGroup> readAgeGroup() async {
    switch ((await _read('ad_age_group') ?? '').trim().toLowerCase()) {
      case 'child':
        return AdAgeGroup.child;
      case 'teen':
        return AdAgeGroup.teen;
      case 'adult':
        return AdAgeGroup.adult;
      default:
        return AdAgeGroup.unknown;
    }
  }

  Future<void> writeAgeGroup(AdAgeGroup group) async {
    if (group == AdAgeGroup.unknown) {
      await clearAgeGroup();
      return;
    }
    await _write('ad_age_group', group.name);
    await _write(
      'ad_age_verified_at',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> clearAgeGroup() async {
    await _delete('ad_age_group');
    await _delete('ad_age_verified_at');
  }

  Future<AdMembershipTier> readMembershipTier() async {
    switch ((await _read('ad_membership_tier') ?? '').trim().toLowerCase()) {
      case 'premium':
        return AdMembershipTier.premium;
      case 'vip':
        return AdMembershipTier.vip;
      case 'free':
      default:
        return AdMembershipTier.free;
    }
  }

  Future<void> writeMembershipTier(AdMembershipTier tier) =>
      _write('ad_membership_tier', tier.name);
}

AdSourceType _adSourceTypeFrom(dynamic value) {
  switch ((value ?? '').toString().trim().toLowerCase()) {
    case 'admob_banner':
    case 'banner':
      return AdSourceType.admobBanner;
    case 'admob_native':
    case 'native':
      return AdSourceType.admobNative;
    case 'admob_interstitial':
    case 'interstitial':
      return AdSourceType.admobInterstitial;
    case 'admob_rewarded':
    case 'rewarded':
      return AdSourceType.admobRewarded;
    case 'app_open':
    case 'appopen':
      return AdSourceType.appOpen;
    case 'private_image':
    case 'image':
      return AdSourceType.privateImage;
    case 'private_video':
    case 'video':
      return AdSourceType.privateVideo;
    case 'vast':
      return AdSourceType.vast;
    case 'vmap':
      return AdSourceType.vmap;
    default:
      return AdSourceType.none;
  }
}

bool _adBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = (value ?? '').toString().trim().toLowerCase();
  if (const {'1', 'true', 'yes', 'on'}.contains(normalized)) return true;
  if (const {'0', 'false', 'no', 'off', ''}.contains(normalized)) return false;
  return fallback;
}

int? _adNullableInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString());
}

class AdRequestContext {
  final String placement;
  final String platform;
  final String appVersion;
  final AdMembershipTier membershipTier;
  final AdAgeGroup ageGroup;
  final String locale;
  final String contentType;
  final int? contentId;
  final List<int> genreIds;
  final String sessionId;

  const AdRequestContext({
    required this.placement,
    required this.platform,
    required this.appVersion,
    required this.membershipTier,
    required this.ageGroup,
    required this.locale,
    this.contentType = '',
    this.contentId,
    this.genreIds = const <int>[],
    this.sessionId = '',
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'placement': placement,
        'platform': platform,
        'app_version': appVersion,
        'user_tier': membershipTier.name,
        'age_group': ageGroup.name,
        'locale': locale,
        if (contentType.isNotEmpty) 'content_type': contentType,
        if (contentId != null) 'content_id': contentId,
        if (genreIds.isNotEmpty) 'genre_ids': genreIds,
        if (sessionId.isNotEmpty) 'session_id': sessionId,
      };
}

class AdCreative {
  final AdSourceType sourceType;
  final String mediaUrl;
  final String clickUrl;
  final String vastUrl;
  final String vmapUrl;
  final String cta;
  final int? skipSeconds;
  final Map<String, dynamic> metadata;

  const AdCreative({
    this.sourceType = AdSourceType.none,
    this.mediaUrl = '',
    this.clickUrl = '',
    this.vastUrl = '',
    this.vmapUrl = '',
    this.cta = '',
    this.skipSeconds,
    this.metadata = const <String, dynamic>{},
  });

  factory AdCreative.fromJson(
    dynamic raw, {
    dynamic sourceType,
  }) {
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return AdCreative(
      sourceType: _adSourceTypeFrom(sourceType ?? map['type']),
      mediaUrl: (map['src'] ??
              map['media_url'] ??
              map['image_url'] ??
              map['video_url'] ??
              '')
          .toString()
          .trim(),
      clickUrl: (map['click_url'] ?? map['url'] ?? '').toString().trim(),
      vastUrl: (map['vast_url'] ?? '').toString().trim(),
      vmapUrl: (map['vmap_url'] ?? '').toString().trim(),
      cta: (map['cta'] ?? map['cta_label'] ?? '').toString().trim(),
      skipSeconds: _adNullableInt(map['skip_after'] ?? map['skip_seconds']),
      metadata: Map<String, dynamic>.from(map),
    );
  }
}

class AdDecision {
  final bool showAd;
  final String decisionId;
  final String placement;
  final AdCreative creative;
  final String trackingToken;

  const AdDecision({
    required this.showAd,
    this.decisionId = '',
    this.placement = '',
    this.creative = const AdCreative(),
    this.trackingToken = '',
  });

  const AdDecision.noAd({String placement = ''})
      : showAd = false,
        decisionId = '',
        placement = placement,
        creative = const AdCreative(),
        trackingToken = '';

  factory AdDecision.fromJson(Map<String, dynamic> json) {
    final show = _adBool(json['show_ad']);
    final tracking = json['tracking'];
    final trackingMap = tracking is Map
        ? Map<String, dynamic>.from(tracking)
        : const <String, dynamic>{};
    final creative = AdCreative.fromJson(
      json['creative'],
      sourceType: json['type'],
    );
    return AdDecision(
      showAd: show,
      decisionId: (json['decision_id'] ?? '').toString(),
      placement: (json['placement'] ?? '').toString(),
      creative: show ? creative : const AdCreative(),
      trackingToken:
          (trackingMap['token'] ?? json['tracking_token'] ?? '').toString(),
    );
  }
}

class AdEvent {
  final String type;
  final String decisionId;
  final String token;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  AdEvent({
    required this.type,
    required this.decisionId,
    required this.token,
    DateTime? timestamp,
    this.metadata = const <String, dynamic>{},
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'decision_id': decisionId,
        'token': token,
        'timestamp': timestamp.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}

typedef AdApiTransport = Future<Map<String, dynamic>> Function(
  String action,
  Map<String, dynamic> data,
);

Future<Map<String, dynamic>> _productionAdTransport(
  String action,
  Map<String, dynamic> data,
) =>
    Api.I.call(action, method: 'POST', data: data);

class AdDecisionClient {
  final AdApiTransport transport;
  final Duration timeout;

  AdDecisionClient({
    required this.transport,
    this.timeout = const Duration(milliseconds: 2500),
  });

  factory AdDecisionClient.production() => AdDecisionClient(
        transport: _productionAdTransport,
      );

  static final AdDecisionClient I = AdDecisionClient.production();

  Future<AdDecision> decide(AdRequestContext context) async {
    if (context.membershipTier == AdMembershipTier.vip) {
      return AdDecision.noAd(placement: context.placement);
    }
    try {
      final raw = await transport(
        'ads_decision',
        context.toJson(),
      ).timeout(timeout);
      final nested = raw['data'];
      final payload = nested is Map
          ? Map<String, dynamic>.from(nested)
          : Map<String, dynamic>.from(raw);
      if (!payload.containsKey('show_ad')) {
        return AdDecision.noAd(placement: context.placement);
      }
      final decision = AdDecision.fromJson(payload);
      if (!decision.showAd) {
        return AdDecision.noAd(placement: context.placement);
      }
      return decision;
    } catch (_) {
      return AdDecision.noAd(placement: context.placement);
    }
  }
}

class AdTrackingQueue {
  final AdApiTransport transport;
  final int capacity;
  final List<AdEvent> _pending = <AdEvent>[];
  bool _flushing = false;

  AdTrackingQueue({
    required this.transport,
    this.capacity = 100,
  }) : assert(capacity > 0);

  factory AdTrackingQueue.production() => AdTrackingQueue(
        transport: _productionAdTransport,
      );

  static final AdTrackingQueue I = AdTrackingQueue.production();

  int get pendingCount => _pending.length;

  static const Set<String> _criticalTypes = <String>{
    'impression',
    'click',
    'complete',
  };

  bool _isCritical(AdEvent event) =>
      _criticalTypes.contains(event.type.trim().toLowerCase());

  void enqueue(AdEvent event) {
    if (_pending.length >= capacity) {
      final removable = _pending.indexWhere((item) => !_isCritical(item));
      if (removable >= 0) {
        _pending.removeAt(removable);
      } else if (!_isCritical(event)) {
        return;
      } else {
        _pending.removeAt(0);
      }
    }
    _pending.add(event);
  }

  Future<bool> flush() async {
    if (_pending.isEmpty) return true;
    if (_flushing) return false;
    _flushing = true;
    final snapshot = List<AdEvent>.from(_pending);
    try {
      await transport(
        'ads_events',
        <String, dynamic>{
          'events': snapshot.map((event) => event.toJson()).toList(),
        },
      );
      final removeCount = snapshot.length.clamp(0, _pending.length);
      _pending.removeRange(0, removeCount);
      return true;
    } catch (_) {
      return false;
    } finally {
      _flushing = false;
    }
  }
}

class AgeGatePage extends StatefulWidget {
  final AdProfileStore? store;

  const AgeGatePage({
    super.key,
    this.store,
  });

  @override
  State<AgeGatePage> createState() => _AgeGatePageState();
}

class _AgeGatePageState extends State<AgeGatePage> {
  DateTime? _birthDate;
  bool _saving = false;

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: Api.I.ar ? 'اختر تاريخ الميلاد' : 'Select date of birth',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  Future<void> _continue() async {
    final birthDate = _birthDate;
    if (birthDate == null || _saving) return;
    setState(() => _saving = true);
    try {
      final group = AgePolicy.classify(birthDate);
      await (widget.store ?? AdProfileStore.I).writeAgeGroup(group);
      if (mounted) Navigator.of(context).pop(group);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Api.I.ar;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(ar ? 'الفئة العمرية' : 'Age check'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.shield_outlined, size: 54),
                        const SizedBox(height: 16),
                        Text(
                          ar ? 'أدخل تاريخ ميلادك' : 'Enter your date of birth',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          ar
                              ? 'نستخدم تاريخ الميلاد مرة واحدة فقط لحساب الفئة العمرية. لا يتم حفظ تاريخ الميلاد نفسه.'
                              : 'Your date of birth is used once to calculate an age group. The birth date itself is not stored.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _chooseDate,
                          icon: const Icon(Icons.calendar_month_rounded),
                          label: Text(
                            _birthDate == null
                                ? (ar
                                    ? 'اختيار تاريخ الميلاد'
                                    : 'Choose date of birth')
                                : _formatDate(_birthDate!),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed:
                              _birthDate == null || _saving ? null : _continue,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(ar ? 'متابعة' : 'Continue'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdMobRequestPolicy {
  final bool nonPersonalized;
  final AgeRestrictedTreatment ageTreatment;

  const AdMobRequestPolicy({
    required this.nonPersonalized,
    required this.ageTreatment,
  });

  factory AdMobRequestPolicy.forAge(AdAgeGroup ageGroup) {
    switch (ageGroup) {
      case AdAgeGroup.child:
        return const AdMobRequestPolicy(
          nonPersonalized: true,
          ageTreatment: AgeRestrictedTreatment.child,
        );
      case AdAgeGroup.teen:
        return const AdMobRequestPolicy(
          nonPersonalized: true,
          ageTreatment: AgeRestrictedTreatment.teen,
        );
      case AdAgeGroup.adult:
        return const AdMobRequestPolicy(
          nonPersonalized: false,
          ageTreatment: AgeRestrictedTreatment.unspecified,
        );
      case AdAgeGroup.unknown:
        return const AdMobRequestPolicy(
          nonPersonalized: true,
          ageTreatment: AgeRestrictedTreatment.child,
        );
    }
  }

  AdRequest toAdRequest() => AdRequest(
        nonPersonalizedAds: nonPersonalized,
      );

  RequestConfiguration toRequestConfiguration() => RequestConfiguration(
        ageRestrictedTreatment: ageTreatment,
      );
}

/// Central AdMob controller for SHORT SERIES TV.
///
/// Production IDs can come from GitHub Actions --dart-define values or from
/// app_config.admob. When no production ID is configured, Google demo ad units
/// are used so development builds never generate invalid traffic.
class AdMobService {
  AdMobService._();
  static final I = AdMobService._();

  static const _testBanner = 'ca-app-pub-3940256099942544/9214589741';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testNative = 'ca-app-pub-3940256099942544/2247696110';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const _testAppOpen = 'ca-app-pub-3940256099942544/9257395921';

  static const _productionBannerFallback =
      'ca-app-pub-3494213319779695/7715973870';
  static const _productionInterstitialFallback =
      'ca-app-pub-3494213319779695/7842123070';
  static const _productionNativeHomeFallback =
      'ca-app-pub-3494213319779695/2307559512';
  static const _productionNativeDetailsFallback =
      'ca-app-pub-3494213319779695/6190964204';

  static const _defineBanner = String.fromEnvironment('ADMOB_BANNER_ID');
  static const _defineInterstitial =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID');
  static const _defineNativeHome =
      String.fromEnvironment('ADMOB_NATIVE_HOME_ID');
  static const _defineNativeDetails =
      String.fromEnvironment('ADMOB_NATIVE_DETAILS_ID');
  static const _defineRewarded = String.fromEnvironment('ADMOB_REWARDED_ID');
  static const _defineAppOpen = String.fromEnvironment('ADMOB_APP_OPEN_ID');
  static const _defineEnabled = String.fromEnvironment('ADMOB_ENABLED');

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;
  bool _showingInterstitial = false;
  bool _initialized = false;
  bool _initializing = false;
  int _playStarts = 0;
  int _episodeTransitions = 0;
  AdAgeGroup _ageGroup = AdAgeGroup.unknown;
  AdMembershipTier _membershipTier = AdMembershipTier.free;
  final ValueNotifier<int> policyRevision = ValueNotifier<int>(0);

  AdAgeGroup get ageGroup => _ageGroup;
  AdMembershipTier get membershipTier => _membershipTier;
  bool get policyAllowsAds =>
      _ageGroup != AdAgeGroup.unknown &&
      _membershipTier != AdMembershipTier.vip;

  Map<String, dynamic> get _config {
    final raw = Api.I.config['admob'];
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
  }

  bool _asBool(dynamic value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final v = value.toString().trim().toLowerCase();
    if (const {'1', 'true', 'yes', 'on', 'enabled'}.contains(v)) return true;
    if (const {'0', 'false', 'no', 'off', 'disabled'}.contains(v)) return false;
    return fallback;
  }

  int _asInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  bool get enabled {
    if (!policyAllowsAds) return false;
    final remote = _config['enabled'];
    if (remote != null) return _asBool(remote, true);
    if (_defineEnabled.trim().isNotEmpty) return _asBool(_defineEnabled, true);
    return true;
  }

  bool get testMode {
    final remote = _config['test_mode'];
    if (remote != null) return _asBool(remote, true);
    final hasProductionId =
        _defineBanner.trim().startsWith('ca-app-pub-') ||
            _defineInterstitial.trim().startsWith('ca-app-pub-') ||
            _defineNativeHome.trim().startsWith('ca-app-pub-') ||
            _defineNativeDetails.trim().startsWith('ca-app-pub-') ||
            _productionBannerFallback.startsWith('ca-app-pub-') ||
            _productionInterstitialFallback.startsWith('ca-app-pub-') ||
            _productionNativeHomeFallback.startsWith('ca-app-pub-') ||
            _productionNativeDetailsFallback.startsWith('ca-app-pub-');
    return !hasProductionId;
  }

  String get bannerId {
    final remote = (_config['banner_id_android'] ?? _config['banner_id'] ?? '')
        .toString()
        .trim();
    if (!testMode && remote.startsWith('ca-app-pub-')) return remote;
    if (!testMode && _defineBanner.trim().startsWith('ca-app-pub-')) {
      return _defineBanner.trim();
    }
    if (!testMode && _productionBannerFallback.startsWith('ca-app-pub-')) {
      return _productionBannerFallback;
    }
    return _testBanner;
  }

  String nativeId(String placement) {
    final details = placement == 'details';
    final remote = (details
                ? (_config['native_details_id_android'] ??
                    _config['native_details_id'])
                : (_config['native_home_id_android'] ??
                    _config['native_home_id']))
            ?.toString()
            .trim() ??
        '';

    if (testMode) return _testNative;
    if (remote.startsWith('ca-app-pub-')) return remote;

    final defined =
        details ? _defineNativeDetails.trim() : _defineNativeHome.trim();
    if (defined.startsWith('ca-app-pub-')) return defined;

    return details
        ? _productionNativeDetailsFallback
        : _productionNativeHomeFallback;
  }

  String get interstitialId {
    final remote =
        (_config['interstitial_id_android'] ?? _config['interstitial_id'] ?? '')
            .toString()
            .trim();
    if (!testMode && remote.startsWith('ca-app-pub-')) return remote;
    if (!testMode && _defineInterstitial.trim().startsWith('ca-app-pub-')) {
      return _defineInterstitial.trim();
    }
    if (!testMode &&
        _productionInterstitialFallback.startsWith('ca-app-pub-')) {
      return _productionInterstitialFallback;
    }
    return _testInterstitial;
  }

  String get rewardedId {
  if (testMode) return _testRewarded;
  final remote = (_config['rewarded_id_android'] ?? _config['rewarded_id'] ?? '')
      .toString()
      .trim();
  if (remote.startsWith('ca-app-pub-')) return remote;
  final defined = _defineRewarded.trim();
  if (defined.startsWith('ca-app-pub-')) return defined;
  return '';
}

String get appOpenId {
  if (testMode) return _testAppOpen;
  final remote = (_config['app_open_id_android'] ?? _config['app_open_id'] ?? '')
      .toString()
      .trim();
  if (remote.startsWith('ca-app-pub-')) return remote;
  final defined = _defineAppOpen.trim();
  if (defined.startsWith('ca-app-pub-')) return defined;
  return '';
}

bool get rewardedEnabled =>
    policyAllowsAds &&
    rewardedId.isNotEmpty &&
    _asBool(_config['rewarded_enabled'], true);

bool get appOpenEnabled =>
    policyAllowsAds &&
    appOpenId.isNotEmpty &&
    _asBool(_config['app_open_enabled'], true);

AdRequest get adRequest =>
    AdMobRequestPolicy.forAge(_ageGroup).toAdRequest();

  int get minIntervalSeconds =>
      _asInt(_config['interstitial_min_interval_seconds'], 420).clamp(60, 3600);

  int get playbackEvery => _asInt(_config['playback_every'], 1).clamp(1, 20);

  int get episodeEvery => _asInt(_config['episode_every'], 2).clamp(1, 20);

  Future<AdAgeGroup> _requestAgeGate() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final navigator = appRouteObserver.navigator;
      if (navigator != null) {
        final result = await navigator.push<AdAgeGroup>(
          MaterialPageRoute<AdAgeGroup>(
            fullscreenDialog: true,
            settings: const RouteSettings(name: '/shortseries/age-gate'),
            builder: (_) => const AgeGatePage(),
          ),
        );
        return result ?? AdAgeGroup.unknown;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return AdAgeGroup.unknown;
  }

  Future<void> initialize() async {
    if (_initialized || _initializing || !Platform.isAndroid) return;
    _initializing = true;
    try {
      var group = await AdProfileStore.I.readAgeGroup();
      if (group == AdAgeGroup.unknown) {
        group = await _requestAgeGate();
      }
      final tier = await AdProfileStore.I.readMembershipTier();
      await initializeFor(ageGroup: group, membershipTier: tier);
    } finally {
      _initializing = false;
    }
  }

  Future<void> initializeFor({
    required AdAgeGroup ageGroup,
    required AdMembershipTier membershipTier,
  }) async {
    _ageGroup = ageGroup;
    _membershipTier = membershipTier;
    policyRevision.value++;
    if (_initialized ||
      !Platform.isAndroid ||
      ageGroup == AdAgeGroup.unknown ||
      membershipTier == AdMembershipTier.vip) {
    return;
  }
  _initialized = true;
  final requestPolicy = AdMobRequestPolicy.forAge(ageGroup);
  await MobileAds.instance.updateRequestConfiguration(
    requestPolicy.toRequestConfiguration(),
  );
  await MobileAds.instance.initialize();
  unawaited(preloadInterstitial());
}

  Future<void> preloadInterstitial() async {
    if (!Platform.isAndroid ||
        !enabled ||
        _loadingInterstitial ||
        _interstitial != null ||
        _showingInterstitial) {
      return;
    }

    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialId,
      request: AdMobService.I.adRequest,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          _interstitial = null;
        },
      ),
    );
  }

  Future<bool> _intervalAllows() async {
    final raw = await Api.I.store.read(key: 'admob_last_interstitial_ms');
    final last = int.tryParse(raw ?? '') ?? 0;
    if (last <= 0) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= minIntervalSeconds * 1000;
  }

  Future<void> _markShown() async {
    await Api.I.store.write(
      key: 'admob_last_interstitial_ms',
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<bool> maybeShowPlaybackInterstitial({
    required bool betweenEpisodes,
  }) async {
    if (!Platform.isAndroid || !enabled || _showingInterstitial) return false;

    if (betweenEpisodes) {
      _episodeTransitions++;
      if (_episodeTransitions % episodeEvery != 0) {
        unawaited(preloadInterstitial());
        return false;
      }
    } else {
      _playStarts++;
      if (_playStarts % playbackEvery != 0) {
        unawaited(preloadInterstitial());
        return false;
      }
    }

    if (!await _intervalAllows()) {
      unawaited(preloadInterstitial());
      return false;
    }

    final ad = _interstitial;
    if (ad == null) {
      unawaited(preloadInterstitial());
      return false;
    }

    _interstitial = null;
    _showingInterstitial = true;
    final done = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        unawaited(_markShown());
      },
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _showingInterstitial = false;
        if (!done.isCompleted) done.complete(true);
        unawaited(preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        failedAd.dispose();
        _showingInterstitial = false;
        if (!done.isCompleted) done.complete(false);
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
    this.compact = false,
  });

  @override
  State<AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<AdMobBanner> {
  BannerAd? _ad;
  int _loadedWidth = 0;
  bool _loading = false;

  Future<void> _load(int width) async {
    if (!Platform.isAndroid ||
        !AdMobService.I.enabled ||
        width <= 0 ||
        _loading ||
        (_ad != null && _loadedWidth == width)) {
      return;
    }

    _loading = true;
    final old = _ad;
    _ad = null;
    old?.dispose();

    final AdSize? size = widget.compact
        ? AdSize.banner
        : await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);

    if (size == null) {
      _loading = false;
      return;
    }

    final banner = BannerAd(
      adUnitId: AdMobService.I.bannerId,
      request: AdMobService.I.adRequest,
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as BannerAd;
            _loadedWidth = width;
            _loading = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _loading = false);
        },
      ),
    );
    banner.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Widget _buildAd(BuildContext context) {
    if (!Platform.isAndroid || !AdMobService.I.enabled) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context).width;
        final width =
            (constraints.maxWidth.isFinite ? constraints.maxWidth : screen)
                .floor()
                .clamp(1, screen.floor());

        if (_ad == null && !_loading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_load(width));
          });
        }

        final ad = _ad;
        if (ad == null) return const SizedBox.shrink();

        return Semantics(
          label: Api.I.ar ? 'إعلان' : 'Advertisement',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Api.I.ar ? 'إعلان' : 'Ad',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: ad.size.width.toDouble(),
                  height: ad.size.height.toDouble(),
                  child: AdWidget(ad: ad),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AdMobService.I.policyRevision,
      builder: (_, __, ___) => _buildAd(context),
    );
  }
}

class AdMobNativeCard extends StatefulWidget {
  final String placement;

  const AdMobNativeCard({
    super.key,
    required this.placement,
  });

  @override
  State<AdMobNativeCard> createState() => _AdMobNativeCardState();
}

class _AdMobNativeCardState extends State<AdMobNativeCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _loading = false;

  Future<void> _load() async {
    if (!Platform.isAndroid ||
        !AdMobService.I.enabled ||
        _loading ||
        _loaded) {
      return;
    }

    _loading = true;
    final ad = NativeAd(
      adUnitId: AdMobService.I.nativeId(widget.placement),
      factoryId: 'shortSeriesNative',
      request: AdMobService.I.adRequest,
      listener: NativeAdListener(
        onAdLoaded: (loadedAd) {
          if (!mounted) {
            loadedAd.dispose();
            return;
          }
          setState(() {
            _ad = loadedAd as NativeAd;
            _loaded = true;
            _loading = false;
          });
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (mounted) setState(() => _loading = false);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Widget _buildAd(BuildContext context) {
    final ad = _ad;
    if (!Platform.isAndroid ||
        !AdMobService.I.enabled ||
        !_loaded ||
        ad == null) {
      if (!_loading && !_loaded && AdMobService.I.enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_load());
        });
      }
      return const SizedBox.shrink();
    }

    return Semantics(
      label: Api.I.ar ? 'إعلان مدمج' : 'Native advertisement',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 292,
            width: double.infinity,
            child: AdWidget(ad: ad),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AdMobService.I.policyRevision,
      builder: (_, __, ___) => _buildAd(context),
    );
  }
}

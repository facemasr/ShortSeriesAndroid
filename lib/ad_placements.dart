part of 'main.dart';

class RemoteAdPlacement extends StatefulWidget {
  final String placement;
  final String contentType;
  final int? contentId;
  final List<int> genreIds;
  final Widget? legacyFallback;
  final AdDecisionClient? client;
  final AdTrackingQueue? tracking;
  final bool? remoteEnabledOverride;
  final AdAgeGroup? ageGroupOverride;
  final AdMembershipTier? membershipTierOverride;
  final String? appVersionOverride;
  final String? platformOverride;

  const RemoteAdPlacement({
    super.key,
    required this.placement,
    this.contentType = '',
    this.contentId,
    this.genreIds = const <int>[],
    this.legacyFallback,
    this.client,
    this.tracking,
    this.remoteEnabledOverride,
    this.ageGroupOverride,
    this.membershipTierOverride,
    this.appVersionOverride,
    this.platformOverride,
  });

  @override
  State<RemoteAdPlacement> createState() => _RemoteAdPlacementState();
}

class _RemoteAdPlacementState extends State<RemoteAdPlacement> {
  AdDecision? _decision;
  bool _useLegacy = false;
  bool _started = false;
  int _loadGeneration = 0;

  AdDecisionClient get _client => widget.client ?? AdDecisionClient.I;
  AdTrackingQueue get _tracking => widget.tracking ?? AdTrackingQueue.I;
  AdAgeGroup get _ageGroup =>
      widget.ageGroupOverride ?? AdMobService.I.ageGroup;
  AdMembershipTier get _membershipTier =>
      widget.membershipTierOverride ?? AdMobService.I.membershipTier;

  bool get _remoteEnabled {
    final override = widget.remoteEnabledOverride;
    if (override != null) return override;
    final raw = Api.I.config['ad_platform'];
    if (raw is! Map) return false;
    final config = Map<String, dynamic>.from(raw);
    return _adBool(config['enabled']);
  }

  @override
  void initState() {
    super.initState();
    AdMobService.I.policyRevision.addListener(_onPolicyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  @override
  void didUpdateWidget(covariant RemoteAdPlacement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement ||
        oldWidget.contentType != widget.contentType ||
        oldWidget.contentId != widget.contentId ||
        oldWidget.remoteEnabledOverride != widget.remoteEnabledOverride ||
        oldWidget.ageGroupOverride != widget.ageGroupOverride ||
        oldWidget.membershipTierOverride != widget.membershipTierOverride) {
      _resetAndReload();
    }
  }

  @override
  void dispose() {
    AdMobService.I.policyRevision.removeListener(_onPolicyChanged);
    super.dispose();
  }

  void _onPolicyChanged() {
    if (widget.ageGroupOverride != null || widget.membershipTierOverride != null) {
      return;
    }
    _resetAndReload();
  }

  void _resetAndReload() {
    _loadGeneration++;
    _started = false;
    _decision = null;
    _useLegacy = false;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  Future<String> _resolveAppVersion() async {
    final override = widget.appVersionOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '';
    }
  }

  String get _platform {
    final override = widget.platformOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  Future<void> _ensureLoaded() async {
    if (!mounted || _started) return;
    _started = true;
    final generation = _loadGeneration;

    if (_membershipTier == AdMembershipTier.vip ||
        _ageGroup == AdAgeGroup.unknown) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _decision = AdDecision.noAd(placement: widget.placement));
      }
      return;
    }

    if (!_remoteEnabled) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _useLegacy = true);
      }
      return;
    }

    final version = await _resolveAppVersion();
    final decision = await _client.decide(
      AdRequestContext(
        placement: widget.placement,
        platform: _platform,
        appVersion: version,
        membershipTier: _membershipTier,
        ageGroup: _ageGroup,
        locale: Api.I.locale,
        contentType: widget.contentType,
        contentId: widget.contentId,
        genreIds: widget.genreIds,
        sessionId: 'app-${DateTime.now().millisecondsSinceEpoch}',
      ),
    );

    if (!mounted || generation != _loadGeneration) return;

    if (decision.showAd && !_isSupported(decision.creative.sourceType)) {
      _enqueueError(decision, 'unsupported_source');
      setState(() => _decision = AdDecision.noAd(placement: widget.placement));
      return;
    }

    if (decision.showAd &&
        decision.creative.sourceType == AdSourceType.privateImage &&
        decision.creative.mediaUrl.trim().isEmpty) {
      _enqueueError(decision, 'missing_private_image_url');
      setState(() => _decision = AdDecision.noAd(placement: widget.placement));
      return;
    }

    setState(() => _decision = decision);
  }

  bool _isSupported(AdSourceType type) => const <AdSourceType>{
        AdSourceType.none,
        AdSourceType.admobBanner,
        AdSourceType.admobNative,
        AdSourceType.privateImage,
      }.contains(type);

  void _enqueueError(AdDecision decision, String code) {
    if (decision.decisionId.isEmpty || decision.trackingToken.isEmpty) return;
    _tracking.enqueue(
      AdEvent(
        type: 'error',
        decisionId: decision.decisionId,
        token: decision.trackingToken,
        metadata: <String, dynamic>{
          'placement': widget.placement,
          'code': code,
        },
      ),
    );
    unawaited(_tracking.flush());
  }

  @override
  Widget build(BuildContext context) {
    if (_membershipTier == AdMembershipTier.vip ||
        _ageGroup == AdAgeGroup.unknown) {
      return const SizedBox.shrink();
    }

    if (_useLegacy) return widget.legacyFallback ?? const SizedBox.shrink();

    final decision = _decision;
    if (decision == null || !decision.showAd) {
      return const SizedBox.shrink();
    }

    switch (decision.creative.sourceType) {
      case AdSourceType.admobBanner:
        return AdMobBanner(placement: _legacyAdMobPlacement);
      case AdSourceType.admobNative:
        return AdMobNativeCard(placement: _legacyAdMobPlacement);
      case AdSourceType.privateImage:
        return _PrivateImageAdCard(
          decision: decision,
          tracking: _tracking,
        );
      case AdSourceType.none:
      case AdSourceType.admobInterstitial:
      case AdSourceType.admobRewarded:
      case AdSourceType.appOpen:
      case AdSourceType.privateVideo:
      case AdSourceType.vast:
      case AdSourceType.vmap:
        return const SizedBox.shrink();
    }
  }

  String get _legacyAdMobPlacement =>
      widget.placement == 'details' ? 'details' : 'home';
}

class _PrivateImageAdCard extends StatefulWidget {
  final AdDecision decision;
  final AdTrackingQueue tracking;

  const _PrivateImageAdCard({
    required this.decision,
    required this.tracking,
  });

  @override
  State<_PrivateImageAdCard> createState() => _PrivateImageAdCardState();
}

class _PrivateImageAdCardState extends State<_PrivateImageAdCard> {
  bool _impressionSent = false;

  void _track(String type) {
    final decision = widget.decision;
    if (decision.decisionId.isEmpty || decision.trackingToken.isEmpty) return;
    widget.tracking.enqueue(
      AdEvent(
        type: type,
        decisionId: decision.decisionId,
        token: decision.trackingToken,
      ),
    );
    unawaited(widget.tracking.flush());
  }

  void _markVisible() {
    if (_impressionSent) return;
    _impressionSent = true;
    _track('impression');
  }

  Future<void> _openClick() async {
    _track('click');
    final raw = widget.decision.creative.clickUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final creative = widget.decision.creative;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Semantics(
        label: Api.I.ar ? 'إعلان' : 'Advertisement',
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: creative.clickUrl.trim().isEmpty ? null : _openClick,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 5,
                  child: CachedNetworkImage(
                    imageUrl: creative.mediaUrl,
                    fit: BoxFit.cover,
                    imageBuilder: (context, provider) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _markVisible();
                      });
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          image: DecorationImage(image: provider, fit: BoxFit.cover),
                        ),
                      );
                    },
                    placeholder: (_, __) => Container(color: Colors.white10),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                if (creative.cta.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    color: const Color(0xB0000000),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            creative.cta,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const Icon(Icons.open_in_new_rounded, size: 17),
                      ],
                    ),
                  ),
                PositionedDirectional(
                  top: 7,
                  start: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xAA000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      Api.I.ar ? 'إعلان' : 'Ad',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

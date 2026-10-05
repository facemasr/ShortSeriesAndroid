part of 'main.dart';

typedef PlayerInterstitialLauncher = Future<bool> Function({
  required bool betweenEpisodes,
});

class PlayerAdCoordinator {
  final AdDecisionClient decisionClient;
  final PlayerInterstitialLauncher showInterstitial;
  final AdAgeGroup ageGroup;
  final AdMembershipTier membershipTier;
  final bool remoteEnabled;
  final bool offline;
  final String platform;
  final String appVersion;
  final String locale;

  bool _inFlight = false;

  PlayerAdCoordinator({
    required this.decisionClient,
    required this.showInterstitial,
    required this.ageGroup,
    required this.membershipTier,
    required this.remoteEnabled,
    this.offline = false,
    this.platform = 'android',
    this.appVersion = '',
    this.locale = 'ar',
  });

  Future<bool> maybeShow({
    required bool betweenEpisodes,
    String contentType = '',
    int? contentId,
    List<int> genreIds = const <int>[],
  }) async {
    if (_inFlight ||
        offline ||
        ageGroup == AdAgeGroup.unknown ||
        membershipTier == AdMembershipTier.vip) {
      return false;
    }

    _inFlight = true;
    try {
      if (!remoteEnabled) {
        return await showInterstitial(betweenEpisodes: betweenEpisodes);
      }

      final placement = betweenEpisodes ? 'between_episodes' : 'player_preroll';
      final decision = await decisionClient.decide(
        AdRequestContext(
          placement: placement,
          platform: platform,
          appVersion: appVersion,
          membershipTier: membershipTier,
          ageGroup: ageGroup,
          locale: locale,
          contentType: contentType,
          contentId: contentId,
          genreIds: genreIds,
          sessionId: 'player-${DateTime.now().millisecondsSinceEpoch}',
        ),
      );

      if (!decision.showAd ||
          decision.creative.sourceType != AdSourceType.admobInterstitial) {
        return false;
      }

      try {
        return await showInterstitial(betweenEpisodes: betweenEpisodes);
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    } finally {
      _inFlight = false;
    }
  }
}

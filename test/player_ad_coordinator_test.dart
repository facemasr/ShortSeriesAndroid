import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shortseris_app/main.dart';

AdDecisionClient _client(
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>) transport, {
  Duration timeout = const Duration(milliseconds: 100),
}) =>
    AdDecisionClient(transport: transport, timeout: timeout);

void main() {
  group('PlayerAdCoordinator', () {
    test('VIP skips remote request and interstitial', () async {
      var requests = 0;
      var shows = 0;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, __) async {
          requests++;
          return {'show_ad': true, 'type': 'admob_interstitial'};
        }),
        showInterstitial: ({required betweenEpisodes}) async {
          shows++;
          return true;
        },
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.vip,
        remoteEnabled: true,
      );

      expect(await coordinator.maybeShow(betweenEpisodes: false), isFalse);
      expect(requests, 0);
      expect(shows, 0);
    });

    test('offline playback skips remote request', () async {
      var requests = 0;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, __) async {
          requests++;
          return {'show_ad': true, 'type': 'admob_interstitial'};
        }),
        showInterstitial: ({required betweenEpisodes}) async => true,
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: true,
        offline: true,
      );

      expect(await coordinator.maybeShow(betweenEpisodes: false), isFalse);
      expect(requests, 0);
    });

    test('remote disabled preserves legacy interstitial path', () async {
      var requests = 0;
      var shows = 0;
      bool? transition;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, __) async {
          requests++;
          return {'show_ad': false};
        }),
        showInterstitial: ({required betweenEpisodes}) async {
          shows++;
          transition = betweenEpisodes;
          return true;
        },
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: false,
      );

      expect(await coordinator.maybeShow(betweenEpisodes: true), isTrue);
      expect(requests, 0);
      expect(shows, 1);
      expect(transition, isTrue);
    });

    test('preroll maps to player_preroll placement and shows AdMob', () async {
      Map<String, dynamic>? payload;
      var shows = 0;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, data) async {
          payload = data;
          return {
            'show_ad': true,
            'decision_id': 'd1',
            'placement': 'player_preroll',
            'type': 'admob_interstitial',
          };
        }),
        showInterstitial: ({required betweenEpisodes}) async {
          shows++;
          expect(betweenEpisodes, isFalse);
          return true;
        },
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: true,
      );

      expect(
        await coordinator.maybeShow(
          betweenEpisodes: false,
          contentType: 'episode',
          contentId: 44,
        ),
        isTrue,
      );
      expect(payload?['placement'], 'player_preroll');
      expect(payload?['content_type'], 'episode');
      expect(payload?['content_id'], 44);
      expect(shows, 1);
    });

    test('episode transition maps to between_episodes', () async {
      String? placement;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, data) async {
          placement = data['placement']?.toString();
          return {'show_ad': false};
        }),
        showInterstitial: ({required betweenEpisodes}) async => true,
        ageGroup: AdAgeGroup.teen,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: true,
      );

      expect(await coordinator.maybeShow(betweenEpisodes: true), isFalse);
      expect(placement, 'between_episodes');
    });

    test('no-ad decision never invokes interstitial', () async {
      var shows = 0;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, __) async => {'show_ad': false}),
        showInterstitial: ({required betweenEpisodes}) async {
          shows++;
          return true;
        },
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: true,
      );

      expect(await coordinator.maybeShow(betweenEpisodes: false), isFalse);
      expect(shows, 0);
    });

    test('unsupported player source fails open', () async {
      var shows = 0;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, __) async => {
          'show_ad': true,
          'type': 'private_video',
          'creative': {'src': 'https://example.invalid/ad.mp4'},
        }),
        showInterstitial: ({required betweenEpisodes}) async {
          shows++;
          return true;
        },
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: true,
      );

      expect(await coordinator.maybeShow(betweenEpisodes: false), isFalse);
      expect(shows, 0);
    });

    test('decision timeout returns quickly and does not show', () async {
      var shows = 0;
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client(
          (_, __) => Completer<Map<String, dynamic>>().future,
          timeout: const Duration(milliseconds: 20),
        ),
        showInterstitial: ({required betweenEpisodes}) async {
          shows++;
          return true;
        },
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: true,
      );

      final watch = Stopwatch()..start();
      final result = await coordinator.maybeShow(betweenEpisodes: false);
      watch.stop();

      expect(result, isFalse);
      expect(shows, 0);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('concurrent calls allow only one request in flight', () async {
      var requests = 0;
      final gate = Completer<Map<String, dynamic>>();
      final coordinator = PlayerAdCoordinator(
        decisionClient: _client((_, __) {
          requests++;
          return gate.future;
        }),
        showInterstitial: ({required betweenEpisodes}) async => true,
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.free,
        remoteEnabled: true,
      );

      final first = coordinator.maybeShow(betweenEpisodes: false);
      final second = await coordinator.maybeShow(betweenEpisodes: false);
      expect(second, isFalse);
      expect(requests, 1);

      gate.complete({'show_ad': false});
      expect(await first, isFalse);
    });
  });
}

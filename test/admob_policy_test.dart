import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shortseris_app/main.dart';

void main() {
  tearDown(() {
    Api.I.config = <String, dynamic>{};
  });

  group('AdMobRequestPolicy', () {
    test('child requests use child treatment and non-personalized ads', () {
      final policy = AdMobRequestPolicy.forAge(AdAgeGroup.child);

      expect(policy.nonPersonalized, isTrue);
      expect(policy.ageTreatment, AgeRestrictedTreatment.child);
      expect(policy.toAdRequest().nonPersonalizedAds, isTrue);
      expect(
        policy.toRequestConfiguration().ageRestrictedTreatment,
        AgeRestrictedTreatment.child,
      );
    });

    test('teen requests use teen treatment and non-personalized ads', () {
      final policy = AdMobRequestPolicy.forAge(AdAgeGroup.teen);

      expect(policy.nonPersonalized, isTrue);
      expect(policy.ageTreatment, AgeRestrictedTreatment.teen);
    });

    test('adult requests use unspecified treatment by default', () {
      final policy = AdMobRequestPolicy.forAge(AdAgeGroup.adult);

      expect(policy.nonPersonalized, isFalse);
      expect(policy.ageTreatment, AgeRestrictedTreatment.unspecified);
    });

    test('unknown age falls back to child treatment', () {
      final policy = AdMobRequestPolicy.forAge(AdAgeGroup.unknown);

      expect(policy.nonPersonalized, isTrue);
      expect(policy.ageTreatment, AgeRestrictedTreatment.child);
    });
  });

  group('AdMobService policy', () {
    test('VIP disables ads', () async {
      await AdMobService.I.initializeFor(
        ageGroup: AdAgeGroup.adult,
        membershipTier: AdMembershipTier.vip,
      );
      expect(AdMobService.I.policyAllowsAds, isFalse);
    });

    test('unknown age disables ads even for free tier', () async {
      await AdMobService.I.initializeFor(
        ageGroup: AdAgeGroup.unknown,
        membershipTier: AdMembershipTier.free,
      );
      expect(AdMobService.I.policyAllowsAds, isFalse);
    });

    test('known free user is eligible for ads', () async {
      await AdMobService.I.initializeFor(
        ageGroup: AdAgeGroup.teen,
        membershipTier: AdMembershipTier.free,
      );
      expect(AdMobService.I.policyAllowsAds, isTrue);
    });
  });

  group('AdMob rewarded and app-open IDs', () {
    test('remote production IDs are used when configured', () {
      Api.I.config = {
        'admob': {
          'test_mode': false,
          'rewarded_id_android': 'ca-app-pub-1000000000000000/1111111111',
          'app_open_id_android': 'ca-app-pub-1000000000000000/2222222222',
        },
      };

      expect(
        AdMobService.I.rewardedId,
        'ca-app-pub-1000000000000000/1111111111',
      );
      expect(
        AdMobService.I.appOpenId,
        'ca-app-pub-1000000000000000/2222222222',
      );
    });

    test('test mode uses Google demo rewarded and app-open IDs', () {
      Api.I.config = {
        'admob': {'test_mode': true},
      };

      expect(
        AdMobService.I.rewardedId,
        'ca-app-pub-3940256099942544/5224354917',
      );
      expect(
        AdMobService.I.appOpenId,
        'ca-app-pub-3940256099942544/9257395921',
      );
    });

    test('production mode leaves unconfigured new units disabled', () {
      Api.I.config = {
        'admob': {'test_mode': false},
      };

      expect(AdMobService.I.rewardedId, isEmpty);
      expect(AdMobService.I.appOpenId, isEmpty);
      expect(AdMobService.I.rewardedEnabled, isFalse);
      expect(AdMobService.I.appOpenEnabled, isFalse);
    });
  });
}

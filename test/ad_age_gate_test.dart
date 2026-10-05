import 'package:flutter_test/flutter_test.dart';
import 'package:shortseris_app/main.dart';

void main() {
  group('AgePolicy.classify', () {
    final now = DateTime(2026, 10, 5);

    test('child one day before thirteenth birthday', () {
      expect(
        AgePolicy.classify(DateTime(2013, 10, 6), now: now),
        AdAgeGroup.child,
      );
    });

    test('teen on thirteenth birthday', () {
      expect(
        AgePolicy.classify(DateTime(2013, 10, 5), now: now),
        AdAgeGroup.teen,
      );
    });

    test('teen one day before eighteenth birthday', () {
      expect(
        AgePolicy.classify(DateTime(2008, 10, 6), now: now),
        AdAgeGroup.teen,
      );
    });

    test('adult on eighteenth birthday', () {
      expect(
        AgePolicy.classify(DateTime(2008, 10, 5), now: now),
        AdAgeGroup.adult,
      );
    });

    test('handles leap-day birthday on a leap-year boundary', () {
      expect(
        AgePolicy.classify(
          DateTime(2012, 2, 29),
          now: DateTime(2028, 2, 29),
        ),
        AdAgeGroup.teen,
      );
    });

    test('rejects a future birth date', () {
      expect(
        () => AgePolicy.classify(DateTime(2026, 10, 6), now: now),
        throwsArgumentError,
      );
    });
  });

  group('AdProfileStore', () {
    test('corrupt age value returns unknown', () async {
      final values = <String, String>{'ad_age_group': 'not-valid'};
      final store = AdProfileStore.memory(values);

      expect(await store.readAgeGroup(), AdAgeGroup.unknown);
    });

    test('persists only coarse group and verification timestamp', () async {
      final values = <String, String>{};
      final store = AdProfileStore.memory(values);

      await store.writeAgeGroup(AdAgeGroup.teen);

      expect(values['ad_age_group'], 'teen');
      expect(values['ad_age_verified_at'], isNotEmpty);
      expect(
        values.keys.where((key) => key.contains('birth') || key.contains('dob')),
        isEmpty,
      );
    });

    test('unknown membership defaults to free', () async {
      final store = AdProfileStore.memory(
        <String, String>{'ad_membership_tier': 'invalid'},
      );
      expect(await store.readMembershipTier(), AdMembershipTier.free);
    });

    test('clear age removes age group and verification timestamp', () async {
      final values = <String, String>{
        'ad_age_group': 'adult',
        'ad_age_verified_at': '2026-10-05T00:00:00Z',
      };
      final store = AdProfileStore.memory(values);

      await store.clearAgeGroup();

      expect(values.containsKey('ad_age_group'), isFalse);
      expect(values.containsKey('ad_age_verified_at'), isFalse);
    });
  });
}

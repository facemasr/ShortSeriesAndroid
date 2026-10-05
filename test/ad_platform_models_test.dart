import 'package:flutter_test/flutter_test.dart';
import 'package:shortseris_app/main.dart';

void main() {
  group('AdDecision.fromJson', () {
    test('parses valid VAST decision', () {
      final decision = AdDecision.fromJson({
        'ok': true,
        'show_ad': true,
        'decision_id': 'dec_123',
        'placement': 'player_preroll',
        'type': 'vast',
        'creative': {
          'vast_url': 'https://ads.example/vast.xml',
          'click_url': 'https://ads.example/click',
          'cta': 'Visit',
          'skip_after': 5,
        },
        'tracking': {'token': 'tok_123'},
      });

      expect(decision.showAd, isTrue);
      expect(decision.decisionId, 'dec_123');
      expect(decision.placement, 'player_preroll');
      expect(decision.creative.sourceType, AdSourceType.vast);
      expect(decision.creative.vastUrl, 'https://ads.example/vast.xml');
      expect(decision.creative.skipSeconds, 5);
      expect(decision.trackingToken, 'tok_123');
    });

    test('parses no-ad response', () {
      final decision = AdDecision.fromJson({'ok': true, 'show_ad': false});
      expect(decision.showAd, isFalse);
      expect(decision.creative.sourceType, AdSourceType.none);
    });

    test('unknown source type degrades to none', () {
      final decision = AdDecision.fromJson({
        'show_ad': true,
        'type': 'future_format',
        'creative': {'src': 'https://example.invalid/ad.bin'},
      });
      expect(decision.creative.sourceType, AdSourceType.none);
    });

    test('missing optional creative fields are safe defaults', () {
      final decision = AdDecision.fromJson({
        'show_ad': true,
        'type': 'private_image',
        'creative': <String, dynamic>{},
      });
      expect(decision.creative.mediaUrl, isEmpty);
      expect(decision.creative.clickUrl, isEmpty);
      expect(decision.creative.cta, isEmpty);
      expect(decision.creative.skipSeconds, isNull);
      expect(decision.creative.metadata, isA<Map<String, dynamic>>());
    });

    test('malformed values do not throw', () {
      expect(
        () => AdDecision.fromJson({
          'show_ad': 'definitely',
          'creative': 'not-a-map',
          'tracking': 42,
          'decision_id': null,
        }),
        returnsNormally,
      );
    });
  });
}

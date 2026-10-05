import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shortseris_app/main.dart';

AdRequestContext _context({
  AdMembershipTier tier = AdMembershipTier.free,
}) {
  return AdRequestContext(
    placement: 'player_preroll',
    platform: 'android',
    appVersion: '1.13.3',
    membershipTier: tier,
    ageGroup: AdAgeGroup.adult,
    locale: 'ar',
    contentType: 'episode',
    contentId: 42,
    genreIds: const [18],
    sessionId: 'session-1',
  );
}

void main() {
  group('AdDecisionClient', () {
    test('parses a successful wrapped server decision', () async {
      var calls = 0;
      String? action;
      Map<String, dynamic>? payload;
      final client = AdDecisionClient(
        transport: (nextAction, data) async {
          calls++;
          action = nextAction;
          payload = data;
          return {
            'ok': true,
            'data': {
              'show_ad': true,
              'decision_id': 'dec-1',
              'placement': 'player_preroll',
              'type': 'private_image',
              'creative': {
                'src': 'https://shortseris.online/ad.jpg',
                'click_url': 'https://shortseris.online/',
              },
              'tracking': {'token': 'tok-1'},
            },
          };
        },
      );

      final decision = await client.decide(_context());

      expect(calls, 1);
      expect(action, 'ads_decision');
      expect(payload?['placement'], 'player_preroll');
      expect(payload?['content_id'], 42);
      expect(payload?['age_group'], 'adult');
      expect(decision.showAd, isTrue);
      expect(decision.decisionId, 'dec-1');
      expect(decision.creative.sourceType, AdSourceType.privateImage);
    });

    test('supports direct decision response', () async {
      final client = AdDecisionClient(
        transport: (_, __) async => {
          'show_ad': true,
          'decision_id': 'direct',
          'type': 'admob_interstitial',
        },
      );

      final decision = await client.decide(_context());
      expect(decision.showAd, isTrue);
      expect(decision.decisionId, 'direct');
      expect(decision.creative.sourceType, AdSourceType.admobInterstitial);
    });

    test('timeout fails open without throwing', () async {
      final client = AdDecisionClient(
        timeout: const Duration(milliseconds: 20),
        transport: (_, __) => Completer<Map<String, dynamic>>().future,
      );

      final stopwatch = Stopwatch()..start();
      final decision = await client.decide(_context());
      stopwatch.stop();

      expect(decision.showAd, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('transport error fails open', () async {
      final client = AdDecisionClient(
        transport: (_, __) async => throw StateError('offline'),
      );

      final decision = await client.decide(_context());
      expect(decision.showAd, isFalse);
    });

    test('malformed response fails open', () async {
      final client = AdDecisionClient(
        transport: (_, __) async => {
          'ok': true,
          'data': {'unexpected': 'shape'},
        },
      );

      final decision = await client.decide(_context());
      expect(decision.showAd, isFalse);
    });

    test('VIP returns no ad without calling transport', () async {
      var calls = 0;
      final client = AdDecisionClient(
        transport: (_, __) async {
          calls++;
          return {'show_ad': true};
        },
      );

      final decision = await client.decide(
        _context(tier: AdMembershipTier.vip),
      );

      expect(calls, 0);
      expect(decision.showAd, isFalse);
    });

    test('makes exactly one transport call per decision', () async {
      var calls = 0;
      final client = AdDecisionClient(
        transport: (_, __) async {
          calls++;
          return {'show_ad': false};
        },
      );

      await client.decide(_context());
      expect(calls, 1);
    });
  });

  group('AdTrackingQueue', () {
    AdEvent event(String type, String id) => AdEvent(
          type: type,
          decisionId: id,
          token: 'token-$id',
          timestamp: DateTime.utc(2026, 10, 5, 10),
        );

    test('flush preserves event order and sends one batch', () async {
      var calls = 0;
      String? action;
      Map<String, dynamic>? payload;
      final queue = AdTrackingQueue(
        transport: (nextAction, data) async {
          calls++;
          action = nextAction;
          payload = data;
          return {'ok': true};
        },
      );

      queue.enqueue(event('request', 'd1'));
      queue.enqueue(event('impression', 'd2'));
      queue.enqueue(event('click', 'd3'));

      final ok = await queue.flush();

      expect(ok, isTrue);
      expect(calls, 1);
      expect(action, 'ads_events');
      final events = payload?['events'] as List;
      expect(events.map((e) => (e as Map)['decision_id']).toList(), [
        'd1',
        'd2',
        'd3',
      ]);
      expect(queue.pendingCount, 0);
    });

    test('transport failure retains pending events', () async {
      final queue = AdTrackingQueue(
        transport: (_, __) async => throw StateError('offline'),
      );
      queue.enqueue(event('impression', 'd1'));
      queue.enqueue(event('click', 'd2'));

      final ok = await queue.flush();

      expect(ok, isFalse);
      expect(queue.pendingCount, 2);
    });

    test('queue capacity drops oldest non-critical event first', () async {
      Map<String, dynamic>? payload;
      final queue = AdTrackingQueue(
        capacity: 3,
        transport: (_, data) async {
          payload = data;
          return {'ok': true};
        },
      );

      queue.enqueue(event('request', 'non-critical-oldest'));
      queue.enqueue(event('impression', 'critical-1'));
      queue.enqueue(event('click', 'critical-2'));
      queue.enqueue(event('complete', 'critical-3'));

      expect(queue.pendingCount, 3);
      await queue.flush();
      final events = payload?['events'] as List;
      expect(
        events.map((e) => (e as Map)['decision_id']).toList(),
        ['critical-1', 'critical-2', 'critical-3'],
      );
    });

    test('new non-critical event is dropped when full of critical events', () async {
      Map<String, dynamic>? payload;
      final queue = AdTrackingQueue(
        capacity: 2,
        transport: (_, data) async {
          payload = data;
          return {'ok': true};
        },
      );

      queue.enqueue(event('impression', 'keep-1'));
      queue.enqueue(event('click', 'keep-2'));
      queue.enqueue(event('request', 'drop-me'));

      expect(queue.pendingCount, 2);
      await queue.flush();
      final events = payload?['events'] as List;
      expect(
        events.map((e) => (e as Map)['decision_id']).toList(),
        ['keep-1', 'keep-2'],
      );
    });

    test('flush of empty queue is successful without transport call', () async {
      var calls = 0;
      final queue = AdTrackingQueue(
        transport: (_, __) async {
          calls++;
          return {'ok': true};
        },
      );

      expect(await queue.flush(), isTrue);
      expect(calls, 0);
    });
  });
}

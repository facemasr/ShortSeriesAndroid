import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shortseris_app/main.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('feature disabled renders legacy fallback without remote call',
      (tester) async {
    var calls = 0;
    final client = AdDecisionClient(
      transport: (_, __) async {
        calls++;
        return {'show_ad': false};
      },
    );

    await tester.pumpWidget(_host(RemoteAdPlacement(
      placement: 'home_top',
      client: client,
      remoteEnabledOverride: false,
      legacyFallback: const Text('legacy-ad'),
      ageGroupOverride: AdAgeGroup.adult,
      membershipTierOverride: AdMembershipTier.free,
    )));
    await tester.pump();

    expect(find.text('legacy-ad'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('no-ad decision renders no remote creative', (tester) async {
    final client = AdDecisionClient(
      transport: (_, __) async => {'show_ad': false},
    );

    await tester.pumpWidget(_host(RemoteAdPlacement(
      placement: 'home_feed',
      client: client,
      remoteEnabledOverride: true,
      ageGroupOverride: AdAgeGroup.adult,
      membershipTierOverride: AdMembershipTier.free,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('VIP never requests remote ads', (tester) async {
    var calls = 0;
    final client = AdDecisionClient(
      transport: (_, __) async {
        calls++;
        return {'show_ad': true, 'type': 'private_image'};
      },
    );

    await tester.pumpWidget(_host(RemoteAdPlacement(
      placement: 'details',
      client: client,
      remoteEnabledOverride: true,
      ageGroupOverride: AdAgeGroup.adult,
      membershipTierOverride: AdMembershipTier.vip,
    )));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('private image uses returned creative URL and CTA',
      (tester) async {
    final client = AdDecisionClient(
      transport: (_, __) async => {
        'show_ad': true,
        'decision_id': 'dec-image',
        'placement': 'details',
        'type': 'private_image',
        'creative': {
          'src': 'https://shortseris.online/uploads/ads/demo.jpg',
          'click_url': 'https://shortseris.online/',
          'cta': 'شاهد الآن',
        },
        'tracking': {'token': 'tok-image'},
      },
    );

    await tester.pumpWidget(_host(RemoteAdPlacement(
      placement: 'details',
      client: client,
      remoteEnabledOverride: true,
      ageGroupOverride: AdAgeGroup.adult,
      membershipTierOverride: AdMembershipTier.free,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, 'https://shortseris.online/uploads/ads/demo.jpg');
    expect(find.text('شاهد الآن'), findsOneWidget);
  });

  testWidgets('malformed private image renders nothing', (tester) async {
    final client = AdDecisionClient(
      transport: (_, __) async => {
        'show_ad': true,
        'decision_id': 'bad-image',
        'type': 'private_image',
        'creative': {'src': ''},
      },
    );

    await tester.pumpWidget(_host(RemoteAdPlacement(
      placement: 'details',
      client: client,
      remoteEnabledOverride: true,
      ageGroupOverride: AdAgeGroup.adult,
      membershipTierOverride: AdMembershipTier.free,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('decision timeout never leaves a spinner', (tester) async {
    final client = AdDecisionClient(
      timeout: const Duration(milliseconds: 20),
      transport: (_, __) => Completer<Map<String, dynamic>>().future,
    );

    await tester.pumpWidget(_host(RemoteAdPlacement(
      placement: 'home_top',
      client: client,
      remoteEnabledOverride: true,
      ageGroupOverride: AdAgeGroup.adult,
      membershipTierOverride: AdMembershipTier.free,
    )));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

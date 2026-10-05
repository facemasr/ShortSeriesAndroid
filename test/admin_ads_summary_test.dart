import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shortseris_app/main.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: child,
    );

void main() {
  setUp(() {
    Api.I.locale = 'en';
    Api.I.config = <String, dynamic>{};
  });

  testWidgets('summary cards render from server data', (tester) async {
    await tester.pumpWidget(_host(AdminAdsSummaryPage(
      summaryLoader: () async => <String, dynamic>{
        'data': <String, dynamic>{
          'enabled': true,
          'active_campaigns': 3,
          'impressions_today': 1200,
          'clicks_today': 48,
          'errors_today': 2,
        },
      },
    )));
    await tester.pumpAndSettle();

    expect(find.text('Ads Studio'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('unsupported server summary falls back without crashing',
      (tester) async {
    Api.I.config = <String, dynamic>{
      'admob': <String, dynamic>{
        'enabled': true,
        'test_mode': false,
      },
    };

    await tester.pumpWidget(_host(AdminAdsSummaryPage(
      summaryLoader: () async => throw Exception('404 unsupported action'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Ads Studio API is not deployed yet.'), findsOneWidget);
    expect(find.text('Enabled'), findsWidgets);
  });

  testWidgets('full management action is wired to canonical ads path',
      (tester) async {
    var opened = false;

    await tester.pumpWidget(_host(AdminAdsSummaryPage(
      summaryLoader: () async => <String, dynamic>{
        'data': <String, dynamic>{'enabled': true},
      },
      onOpenFullManagement: () => opened = true,
    )));
    await tester.pumpAndSettle();

    expect(AdminAdsSummaryPage.fullManagementPath, '/admin/ads');
    await tester.tap(find.byKey(const Key('open-full-ads-studio')));
    await tester.pump();
    expect(opened, isTrue);
  });
}

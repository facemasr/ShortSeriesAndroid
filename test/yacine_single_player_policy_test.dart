import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the guest catalog and separate player.
void main() {
  test('catalog exposes only the approved content navigation and local list', () {
    final code = File('lib/main.dart').readAsStringSync();
    for (final removed in [
      'EGY TV SPORT', 'EGY TV Sport', 'EgyTvSportHub',
      'DirectYacineChannelPlayer(', '_loadLive', '_openLiveGroup',
      'WebsiteSection(', '_navItem(5,', '_navItem(6,',
      'kind: tab == 5', '_navItem(7, Icons.person_outline',
    ]) {
      expect(code, isNot(contains(removed)), reason: removed);
    }
    for (final item in [
      '_navItem(0, Icons.home_outlined',
      '_navItem(1, Icons.movie_outlined',
      '_navItem(2, Icons.tv_outlined',
      '_navItem(3, Icons.smart_display_outlined',
      '_navItem(7, Icons.favorite_outline',
    ]) {
      expect(code, contains(item), reason: item);
    }
  });
  test('watch actions open the separate player rather than an account page', () {
    final code = File('lib/main.dart').readAsStringSync();
    expect(code, contains("Uri(scheme: 'egyplayer', host: 'play'"));
    expect(code, contains("package: 'com.egyshow.player'"));
    expect(code, contains('await intent.launch()'));
    expect(code, isNot(contains('NativePlayer(')));
    expect(code, isNot(contains('LoginDialog(')));
  });
}

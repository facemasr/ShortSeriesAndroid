import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the EGYSHOW app shell after removing live-TV channels.
void main() {
  test('the app no longer exposes EGY TV Sport or live-channel navigation', () {
    final code = File('lib/main.dart').readAsStringSync();
    expect(code, isNot(contains('EGY TV SPORT')));
    expect(code, isNot(contains('EGY TV Sport')));
    expect(code, isNot(contains('EgyTvSportHub')));
    expect(code, isNot(contains('DirectYacineChannelPlayer(')));
    expect(code, isNot(contains('_loadLive')));
    expect(code, isNot(contains('_openLiveGroup')));
    expect(code, contains("kind: tab == 5 ? 'matches' : 'youtube'"));
    expect(code, contains("_navItem(7, Icons.person_outline"));
  });
}

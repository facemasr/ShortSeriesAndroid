import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Guard the TV app's single internal playback route. These source checks
/// complement runtime unit tests; they do not establish live-provider access.
void main() {
  test('channel navigation only opens the internal Media3 player', () {
    final code = File('lib/main.dart').readAsStringSync();
    final tvHub = File('lib/egy_tv_sport_hub.dart').readAsStringSync();
    expect(code, contains('DirectYacineChannelPlayer('));
    expect(code, isNot(contains('YacineExternalPlayer.open(')));
    expect(code, isNot(contains('_openLiveExternal(')));
    expect(tvHub, isNot(contains('onOpenExternal')));
    expect(tvHub, isNot(contains('preferYtvPro')));
  });

  test('Media3 player never switches engines or launches external apps', () {
    final code = File('lib/yacine_direct_player.dart').readAsStringSync();
    final settings = File('lib/yacine_playback_settings.dart').readAsStringSync();
    expect(code, contains('VideoPlayerController.networkUrl('));
    expect(code, contains('_refreshSources()'));
    expect(code, isNot(contains('YacineVlcChannelPlayer(')));
    expect(code, isNot(contains('yacineShouldUseDesktopVlc(')));
    expect(code, isNot(contains('_switchToVlc(')));
    expect(code, isNot(contains('YacineExternalPlayer.open(')));
    expect(settings, isNot(contains('VLC for Android')));
    expect(settings, isNot(contains('YTV Player Pro')));
    expect(settings, isNot(contains('Open in external player')));
  });
}

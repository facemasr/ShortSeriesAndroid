import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';
import 'package:egyshow_mobile/yacine_external_player.dart';

YacinePlaybackSource source(String url,
    {Object? mode = 3, Map<String, String> headers = const {}}) =>
    YacinePlaybackSource(Uri.parse(url), headers, 'HD', mode);

void main() {
  test('target explicit package IDs remain correct and chooser is unforced', () {
    expect(YacineExternalPlayer.targetPackage(YacineExternalTarget.ytvPro),
        'com.ytv.pronew');
    expect(YacineExternalPlayer.targetPackage(YacineExternalTarget.vlc),
        'org.videolan.vlc');
    expect(YacineExternalPlayer.targetPackage(YacineExternalTarget.choose),
        isNull);
  });


  test('Android chooser recognizes HLS, DASH and progressive sources', () {
    expect(YacineExternalPlayer.mediaMimeType(
        source('https://example.org/live/index.m3u8')),
        'application/vnd.apple.mpegurl');
    expect(YacineExternalPlayer.mediaMimeType(
        source('https://example.org/live?token=short', mode: 3)),
        'application/vnd.apple.mpegurl');
    expect(YacineExternalPlayer.mediaMimeType(
        source('https://example.org/live.mpd', mode: 2)),
        'application/dash+xml');
    expect(YacineExternalPlayer.mediaMimeType(
        source('https://example.org/clip.mp4', mode: 1)),
        'video/*');
  });

  test('public provider UA/Referer may be handed to an external player', () {
    expect(YacineExternalPlayer.isExternalCompatible(source(
      'https://example.org/live.m3u8',
      headers: {'User-Agent': 'Provided-Agent', 'Referer': 'https://example.org/'},
    )), isTrue);
  });

  test('private session credentials never leak into external chooser', () {
    for (final name in ['Cookie', 'Authorization', 'X-Auth-Token']) {
      expect(YacineExternalPlayer.isExternalCompatible(source(
        'https://example.org/live.m3u8',
        headers: {name: 'sensitive-provider-token'},
      )), isFalse);
    }
  });
  test('YTV PRO v15.0 direct intent targets the exported player activity', () {
    final s = source('https://example.org/live/stream.m3u8?e=1999999999',
        headers: {'User-Agent': 'EGYSHOW-Test/1.0'});
    final intent = YacineExternalPlayer.ytvDirectIntent(s);

    expect(intent.action, 'android.intent.action.VIEW');
    expect(intent.package, 'com.ytv.pronew');
    expect(intent.componentName,
        'dev.google.ytvclib.ui.main.PlayerActivity');
    expect(intent.data, s.uri.toString());
    expect(intent.arguments?['type'], 3);
    expect(intent.arguments?['ua'], 'EGYSHOW-Test/1.0');
    expect(intent.arguments?.containsKey('id'), isFalse);
    expect(intent.arguments?.containsKey('http-user-agent'), isFalse);
  });

  test('YTV direct mode cannot carry Referer or private session headers', () {
    final basic = source('https://example.org/live.m3u8',
        headers: {'User-Agent': 'EGYSHOW-Test/1.0'});
    expect(YacineExternalPlayer.isYtvDirectCompatible(basic), isTrue);
    for (final header in ['Referer', 'Cookie', 'Authorization',
                          'X-Auth-Token', 'Origin', 'cookie']) {
      expect(YacineExternalPlayer.isYtvDirectCompatible(
          source('https://example.org/live.m3u8',
              headers: {header: 'session-data'})), isFalse);
    }
  });


}

import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';
import 'package:egyshow_mobile/yacine_external_player.dart';

YacinePlaybackSource source(String url,
    {Object? mode = 3, Map<String, String> headers = const {}}) =>
    YacinePlaybackSource(Uri.parse(url), headers, 'HD', mode);

void main() {
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
}

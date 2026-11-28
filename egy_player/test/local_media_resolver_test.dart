import 'package:flutter_test/flutter_test.dart';
import 'package:player/local_media_resolver.dart';
import 'package:video_player/video_player.dart';

void main() {
  final page = Uri.parse('https://egyshow.com/video/demo');
  test('declared HLS and DASH sources resolve in document order', () {
    final sources = declaredVideoSources(page, '''
      <video><source src="/streams/master.m3u8" type="application/vnd.apple.mpegurl">
      <source src="/streams/manifest.mpd" type="application/dash+xml"></video>
    ''');
    expect(sources.map((s) => s.format), [VideoFormat.hls, VideoFormat.dash]);
    expect(sources.first.uri.toString(), 'https://egyshow.com/streams/master.m3u8');
  });
  test('direct progressive source is accepted and deduplicated', () {
    final sources = declaredVideoSources(page, '''
      <video src="/demo.mp4"><source src="/demo.mp4"></video>
    ''');
    expect(sources.length, 1);
    expect(sources.first.format, VideoFormat.other);
  });
  test('ignore scripts, frames, third-party and non-HTTPS sources', () {
    expect(declaredVideoSources(page, '''
      <script>var url = "/example.mp4";</script>
      <iframe src="/example.mp4"></iframe>
      <video><source src="https://example.org/demo.mp4">
      <source src="http://egyshow.com/demo.mp4">
      <source src="javascript:alert(1)" type="video/mp4"></video>
    '''), isEmpty);
    expect(declaredVideoSources(Uri.parse('https://example.org/'), '<video src="/demo.mp4">'), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:egyshow_mobile/yacine_media_format.dart';

void main() {
  test('detects HLS DASH and direct media with query parameters', () {
    expect(yacineMediaFormat(Uri.parse('https://example.org/live.m3u8?e=123')), VideoFormat.hls);
    expect(yacineMediaFormat(Uri.parse('https://example.org/manifest.mpd')), VideoFormat.dash);
    expect(yacineMediaFormat(Uri.parse('http://example.org/chunk.ts')), VideoFormat.other);
    expect(yacineMediaFormat(Uri.parse('https://example.org/video.mp4')), VideoFormat.other);
  });
  test('respects stream metadata for extensionless URLs', () {
    final url = Uri.parse('https://example.org/play?channel=42');
    expect(yacineIsMediaSource(url, providerMode: 3), isTrue);
    expect(yacineMediaFormat(url, providerMode: 3), VideoFormat.hls);
    expect(yacineIsMediaSource(url, providerMode: 4), isFalse);
    expect(yacineMediaFormat(url, providerMode: 1), isNull);
  });
  test('rejects HTML descriptors', () {
    expect(yacineIsMediaSource(
      Uri.parse('https://example.org/embed.html'), providerMode: 4), isFalse);
    expect(yacineIsMediaSource(
      Uri.parse('https://example.org/main.m3u8'), providerMode: 4), isTrue);
  });
}

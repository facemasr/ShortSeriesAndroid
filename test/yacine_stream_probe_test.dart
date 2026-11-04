import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/yacine_stream_probe.dart';

void main() {
  final base = Uri.parse('https://cdn.example/live/master.m3u8');

  test('accepts false/zero DRM markers but rejects encrypted descriptors', () {
    for (final value in <Object?>[null, false, 0, '0', 'false', 'null', '']) {
      expect(yacineDescriptorHasDrm(value), isFalse, reason: '$value');
    }
    for (final value in <Object?>[true, 1, '1', 'widevine', 'clearkey']) {
      expect(yacineDescriptorHasDrm(value), isTrue, reason: '$value');
    }
  });


  test('resolves the first actual variant from an HLS master', () {
    const manifest =
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2500000\nvariant/720p.m3u8\n';
    final inspected = inspectYacineHls(manifest, base);
    expect(inspected.variant.toString(),
        'https://cdn.example/live/variant/720p.m3u8');
    expect(inspected.segment, isNull);
    expect(inspected.encrypted, isFalse);
  });

  test('resolves a relative media segment, not a manifest tag', () {
    const media =
        '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:3\n#EXTINF:3.0,\nsegment-3.ts\n';
    final inspected = inspectYacineHls(media, base);
    expect(inspected.segment.toString(),
        'https://cdn.example/live/segment-3.ts');
  });

  test('does not probe HLS encrypted with a key', () {
    const media =
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
        '#EXTINF:3.0,\nsegment.ts\n';
    expect(inspectYacineHls(media, base).encrypted, isTrue);
  });

  test('accepts METHOD=NONE without treating it as encrypted', () {
    const media =
        '#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n'
        '#EXTINF:3.0,\nsegment.ts\n';
    expect(inspectYacineHls(media, base).encrypted, isFalse);
  });

  test('distinguishes a manifest from a reachable video segment', () async {
    final visited = <String>[];
    final client = MockClient((request) async {
      visited.add(request.url.path);
      expect(request.headers['User-Agent'], 'media-agent-test');
      expect(request.headers['Referer'], 'https://referrer.example/');
      if (request.url.path.endsWith('master.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nmedia.m3u8',
          200, headers: {'content-type': 'application/vnd.apple.mpegurl'});
      }
      if (request.url.path.endsWith('media.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXTINF:2.0,\nsegment.ts', 200,
          headers: {'content-type': 'application/vnd.apple.mpegurl'});
      }
      expect(request.headers['Range'], 'bytes=0-1023');
      return http.Response('VIDEO_SEGMENT_SAMPLE', 206,
          headers: {'content-type': 'video/mp2t'});
    });
    addTearDown(client.close);
    final result = await YacineMediaProbe(client).verifyHls(base, const {
      'User-Agent': 'media-agent-test',
      'Referer': 'https://referrer.example/',
    });
    expect(result, YacineMediaStatus.segmentReachable);
    expect(visited, [
      '/live/master.m3u8', '/live/media.m3u8', '/live/segment.ts',
    ]);
  });

  test('reports provider 403 rather than claiming a playable source', () async {
    final client = MockClient((_) async => http.Response('Access denied', 403));
    addTearDown(client.close);
    expect(
      YacineMediaProbe(client).verifyHls(base, const {}),
      throwsA(isA<YacineProbeFailure>().having(
          (e) => e.code, 'code', 'source_http_403')),
    );
  });

  test('reports manifest-only when it has no identifiable segment', () async {
    final client = MockClient((_) async => http.Response(
      '#EXTM3U\n#EXT-X-TARGETDURATION:6\n',
      200, headers: {'content-type': 'application/vnd.apple.mpegurl'}));
    addTearDown(client.close);
    expect(await YacineMediaProbe(client).verifyHls(base, const {}),
        YacineMediaStatus.manifestOnly);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:egyshow_mobile/yacine_channel_resolver.dart';
import 'package:egyshow_mobile/yacine_local_relay.dart';

void main() {
  test('local VLC URL stays fixed while signed HLS sources rotate', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var seenHeaders = 0;
    origin.listen((request) async {
      if (request.headers.value('user-agent') == 'Playback/4' &&
          request.headers.value('origin') == 'https://player.example' &&
          request.headers.value('cookie') == 'session=provider') {
        seenHeaders++;
      }
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.text;
      if (path.endsWith('/master.m3u8')) {
        request.response.write('#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=800000\nchild/index.m3u8?version=' +
            (request.uri.queryParameters['version'] ?? '1') + '\n');
      } else if (path.endsWith('/child/index.m3u8')) {
        final n = request.uri.queryParameters['version'] ?? '1';
        request.response.write('#EXTM3U\n'
            '#EXT-X-MEDIA-SEQUENCE:10\n'
            '#EXTINF:4.0,\nsegment.ts?version=' + n + '\n');
      } else if (path.endsWith('/child/segment.ts')) {
        request.response.write('segment ' +
            (request.uri.queryParameters['version'] ?? '1'));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    // The fake provider is deliberately loopback-only for this unit test.
    final relay = YacineLocalRelay(allowLoopbackForTests: true);
    await relay.start();
    final client = http.Client();
    final headers = {
      'User-Agent': 'Playback/4',
      'Origin': 'https://player.example',
      'Cookie': 'session=provider',
    };
    Uri uri(String version) => Uri.parse(
        'http://127.0.0.1:' + origin.port.toString() +
        '/live/master.m3u8?version=' + version);
    try {
      relay.setSource(YacinePlaybackSource(uri('1'), headers, 'HD', 3));
      expect(YacineLocalRelay.needsRelay(
          YacinePlaybackSource(uri('1'), headers, 'HD', 3)), isTrue);
      final fixed = relay.playlistUri;

      Future<String> firstSegment() async {
        final master = await client.get(fixed);
        expect(master.statusCode, 200);
        final variantUrl = master.body.split('\n').firstWhere(
            (s) => s.startsWith('http://127.0.0.1'));
        final child = await client.get(Uri.parse(variantUrl));
        expect(child.statusCode, 200);
        final segmentUrl = child.body.split('\n').firstWhere(
            (s) => s.startsWith('http://127.0.0.1'));
        final media = await client.get(Uri.parse(segmentUrl));
        expect(media.statusCode, 200);
        return media.body;
      }
      expect(await firstSegment(), 'segment 1');
      relay.setSource(YacinePlaybackSource(uri('2'), headers, 'HD', 3));
      expect(relay.playlistUri, fixed);
      expect(await firstSegment(), 'segment 2');
      expect(seenHeaders, greaterThanOrEqualTo(6));
    } finally {
      client.close();
      await relay.close();
      await origin.close(force: true);
    }
  });

  test('provider-encrypted HLS is rejected by the local relay', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      request.response.write('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="key.txt"\n'
          '#EXTINF:5,\nseg.ts\n');
      await request.response.close();
    });
    final relay = YacineLocalRelay(allowLoopbackForTests: true);
    await relay.start();
    final client = http.Client();
    try {
      relay.setSource(YacinePlaybackSource(
          Uri.parse('http://127.0.0.1:' + origin.port.toString() +
              '/live/index.m3u8'),
          {'Origin': 'https://player.example'}, 'HD', 3));
      final response = await client.get(relay.playlistUri);
      expect(response.statusCode, 503);
    } finally {
      client.close();
      await relay.close();
      await origin.close(force: true);
    }
  });
}

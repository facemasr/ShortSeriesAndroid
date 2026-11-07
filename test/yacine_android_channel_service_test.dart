import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/yacine_android_channel_service.dart';

void main() {
  test('Windows-style channel source selection checks actual HLS segments',
      () async {
    final requests = <String>[];
    final client = MockClient((r) async {
      requests.add(r.url.toString());
      if (r.url.path == '/api/channel/307979867285616141') {
        return http.Response(jsonEncode({'data': [
          {'url': 'https://media.example/unavailable.m3u8',
            'url_type': 3, 'name': 'Server 1', 'drm': false},
          {'url': 'https://media.example/live.m3u8',
            'url_type': 3, 'name': 'Server 2', 'drm': false},
        ]}), 200);
      }
      if (r.url.path == '/unavailable.m3u8') return http.Response('', 403);
      if (r.url.path == '/live.m3u8') {
        return http.Response('#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:10\n'
            '#EXTINF:4,\npiece.ts\n', 200,
            headers: {'content-type': 'application/vnd.apple.mpegurl'});
      }
      if (r.url.path == '/piece.ts') {
        return http.Response('real-media-segment', 206,
            headers: {'content-type': 'video/mp2t'});
      }
      return http.Response('', 404);
    });
    final choice = await EgyTvAndroidChannelService(client).choose(
        '307979867285616141', quickCheck: true);
    expect(choice.index, 1);
    expect(choice.status, EgyTvProbeStatus.segmentReachable);
    expect(choice.selected.label, 'Server 2');
    expect(requests.any((x) => x.contains('/piece.ts')), isTrue);
    client.close();
  });

  test('probe failure never prevents decoder from trying provider URL',
      () async {
    final client = MockClient((r) async {
      if (r.url.path.startsWith('/api/channel/')) {
        return http.Response(jsonEncode({'data': [
          {'url': 'https://blocked.example/live.m3u8',
            'url_type': 3, 'name': 'HD'}
        ]}), 200);
      }
      return http.Response('', 403);
    });
    final choice = await EgyTvAndroidChannelService(client).choose(
        '123456789012', quickCheck: true);
    expect(choice.sources, hasLength(1));
    expect(choice.index, 0);
    expect(choice.status, EgyTvProbeStatus.unavailable);
    expect(choice.reason, 'source_http_403');
    client.close();
  });

  test('background refresh follows same source label, not expired URI',
      () async {
    final client = MockClient((r) async =>
        http.Response(jsonEncode({'data': [
          {'url': 'https://media.example/hd.m3u8?e=1999999999',
            'url_type': 3, 'name': 'HD'},
          {'url': 'https://media.example/sd.m3u8?e=1999999999',
            'url_type': 3, 'name': 'SD'},
        ]}), 200));
    final service = EgyTvAndroidChannelService(client);
    final choice = await service.refresh(
        '307979867285616141', currentLabel: 'SD', currentIndex: 0);
    expect(choice.index, 1);
    expect(choice.selected.label, 'SD');
    client.close();
  });
}

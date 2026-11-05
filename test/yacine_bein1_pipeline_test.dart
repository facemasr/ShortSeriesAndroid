import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';
import 'package:egyshow_mobile/yacine_stream_diagnostics.dart';
import 'package:egyshow_mobile/yacine_vlc_options.dart';

void main() {
  const originalReferer =
      'http://yacinneeee.live\u2060\u200D\u2060\u3164\u200C\u2060\u200D\u2060';
  const encodedReferer =
      'http://yacinneeee.live'
      '%E2%81%A0%E2%80%8D%E2%81%A0%E3%85%A4'
      '%E2%80%8C%E2%81%A0%E2%80%8D%E2%81%A0';

  test('beIN SPORTS 1 / ID 1424: API response becomes desktop-matching VLC headers', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/channel/1424');
      expect(request.headers['User-Agent'], 'okhttp/4.12.0');
      return http.Response(jsonEncode(<String, dynamic>{'data': [
        <String, dynamic>{
          'url': 'http://stream.example/live/1424/index.m3u8?t=SAMPLE&e=1999999999',
          'name': 'beIN SPORTS 1 1080P',
          'url_type': 3,
          'user_agent': 'Mozilla/5.0 Chrome/150.0.0.0',
          'referer': originalReferer,
          'drm': false,
        },
      ]}), 200, headers: {'content-type':'application/json'});
    });
    final sources=await YacineChannelResolver(client).resolve('1424');
    expect(sources, hasLength(1));
    final source=sources.single;
    expect(source.uri.path,'/live/1424/index.m3u8');
    expect(source.headers['Referer'], encodedReferer);
    final vlc=yacineVlcOptions(source.headers);
    expect(vlc.http!.options.join(' '), contains(encodedReferer));
    expect(vlc.http!.options.join(' '), contains('Chrome/150'));
    client.close();
  });

  test('beIN SPORTS 1 diagnostics distinguish provider HTTP 403 from API success', () async {
    final source=YacinePlaybackSource(
      Uri.parse('http://stream.example/live/1424/index.m3u8?t=SAMPLE'),
      const {'User-Agent':'Mozilla/5.0 Chrome/150','Referer':encodedReferer},
      'beIN SPORTS 1', 3);
    final client=MockClient((request) async {
      expect(request.url.path, '/live/1424/index.m3u8');
      expect(request.headers['Referer'], encodedReferer);
      expect(request.headers['Range'], 'bytes=0-1023');
      return http.Response('Access forbidden',403);
    });
    final result=await checkYacineManifest(client,source);
    expect(result.httpStatus,403);
    expect(result.denied,isTrue);
    expect(result.accepted,isFalse);
    expect(result.reason,'source_denied');
    client.close();
  });

  test('beIN SPORTS 1 diagnostics recognize a successful manifest response', () async {
    final source=YacinePlaybackSource(
      Uri.parse('http://stream.example/live/1424/index.m3u8'),
      const {'Referer':encodedReferer},'beIN SPORTS 1',3);
    final client=MockClient((_) async => http.Response('#EXTM3U\\n',200));
    final result=await checkYacineManifest(client,source);
    expect(result.accepted,isTrue);
    expect(result.httpStatus,200);
    client.close();
  });
}

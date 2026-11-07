import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';

void main() {
  const agent = 'Mozilla/5.0 Chrome/150.0.0.0';

  test('each channel resolves on the device, without using site server', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      expect(request.url.host, 'def001.ycnapi.com');
      expect(request.headers['User-Agent'], 'okhttp/4.12.0');
      final channel = request.url.pathSegments.last;
      return http.Response(jsonEncode({'data': [
        {'url': 'http://media.example/$channel/index.m3u8?t=NOW&e=1999999999',
         'name': 'HD', 'url_type': 3, 'user_agent': agent,
         'referer': 'http://yacinneeee.live\u2060\u200D\u3164', 'drm': false}
      ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final resolver = YacineChannelResolver(client);
    final first = (await resolver.resolve('4897977498791654610')).single;
    final second = (await resolver.resolve('4897977498790841235')).single;
    expect(requested, hasLength(2));
    expect(requested[0], isNot(requested[1]));
    expect(first.uri.path, contains('4897977498791654610'));
    expect(second.uri.path, contains('4897977498790841235'));
    expect(first.headers['User-Agent'], agent);
    expect(second.headers['Referer'],
      'http://yacinneeee.live%E2%81%A0%E2%80%8D%E3%85%A4');
    expect(first.providerMode, 3);
    // The desktop libVLC option uses the original provider-declared Referer,
    // whereas Media3 and the RAM relay must use the ASCII-safe version.
    expect(second.vlcPlaylistHeaders['Referer'],
        'http://yacinneeee.live\u2060\u200D\u3164');
    expect(first.vlcPlaylistHeaders['User-Agent'], agent);
    client.close();
  });

  test('desktop VLC headers reject invalid or injected original Referer', () {
    final safe = <String, String>{
      'User-Agent': 'okhttp/4.12.0',
      'Referer': 'https://example.com/safe',
    };
    expect(yacineDesktopVlcHeaders({
      'referer': 'https://example.com/attack\r\nX-Injected: 1',
    }, safe)['Referer'], 'https://example.com/safe');
    expect(yacineDesktopVlcHeaders({
      'referer': 'javascript:alert(1)',
    }, safe)['Referer'], 'https://example.com/safe');
  });

  test('skips expired, protected and HTML sources', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({
      'data': [
        {'url': 'https://media.example/expired.m3u8?e=1700000001'},
        {'url': 'https://media.example/protected.mpd', 'drm': {'enabled': true}},
        {'url': 'https://media.example/embed.html'},
        {'url': 'https://media.example/new.m3u8?e=1999999999',
         'headers': {'Referer': 'https://media.example/player'}}
      ]
    }), 200));
    final sources = await YacineChannelResolver(client).resolve('1234');
    expect(sources, hasLength(1));
    expect(sources.single.uri.path, '/new.m3u8');
    expect(sources.single.headers['Referer'], 'https://media.example/player');
    // Match the desktop fallback when no media-specific identity was declared.
    expect(sources.single.headers['User-Agent'], 'okhttp/4.12.0');
    client.close();
  });

  test('a rotated provider ID returns explicit 404 for catalog re-discovery', () async {
    final client = MockClient((_) async => http.Response('Not found', 404));
    await expectLater(YacineChannelResolver(client).resolve('1424'),
        throwsA(isA<YacineResolveException>().having(
            (e) => e.reason, 'reason', 'provider_api_http_404')));
    client.close();
  });

  test('invalid channel identifier cannot trigger a network request', () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('{}', 200);
    });
    await expectLater(YacineChannelResolver(client).resolve('../bad'),
        throwsA(isA<YacineResolveException>()));
    expect(called, isFalse);
    client.close();
  });
}

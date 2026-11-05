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
    client.close();
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
    // No provider-supplied User-Agent: use the native device player's default.
    expect(sources.single.headers.containsKey('User-Agent'), isFalse);
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

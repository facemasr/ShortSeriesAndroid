import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egy_tv_pro/native_api.dart';
import 'package:egy_tv_pro/yacine_channel_resolver.dart';
import 'package:egy_tv_pro/yacine_live_source_service.dart';

void main() {
  final mock = MockClient((request) async {
    expect(request.url.host, 'def001.ycnapi.com');
    final path = request.url.path;
    Map<String, dynamic> data;
    switch (path) {
      case '/api/categories':
        data = {'data': [
          {'id': '500', 'name': 'beIN SPORTS (1080P)', 'child_count': 0}
        ]};
        break;
      case '/api/categories/500/channels':
        data = {'data': [
          {'id': '1424', 'name': 'beIN SPORTS 1'},
          {'id': '1481', 'name': 'beIN English 1'},
        ]};
        break;
      case '/api/channel/1424':
        data = {'data': [
          {
            'url': 'https://streams.example.com/channel/index.m3u8',
            'url_type': '3',
            'name': 'HD',
            'headers': {
              'User-Agent': 'EGYTV-Test-UA/1.0',
              'Referer': 'https://example.com/player',
            }
          },
        ]};
        break;
      case '/api/channel/1481':
        data = {'data': []};
        break;
      default:
        fail('Unexpected API request: ' + path);
    }
    return http.Response(jsonEncode(data), 200,
      headers: {'content-type': 'application/json'});
  });

  test('current channel catalog delivers source URL and player headers', () async {
    final api = EgyApi(httpClient: mock);
    const cat = 'beIN SPORTS (1080P)';
    final channel = LiveChannel({
      'id': 1424, 'provider_id': '1424',
      'name_en': 'beIN SPORTS 1', 'name_ar': 'beIN SPORTS 1',
      'package_name': cat,
    });
    final resolution = await YacineLiveSourceService(api, mock)
        .resolve(channel);
    expect(resolution.channel.providerId, '1424');
    expect(resolution.sources.length, 1);
    expect(resolution.sources.first.uri.host, 'streams.example.com');
    expect(resolution.sources.first.headers['User-Agent'],
      'EGYTV-Test-UA/1.0');
    expect(resolution.sources.first.headers['Referer'],
      'https://example.com/player');
  });

  test('empty provider channel reports no source instead of inventing URL', () async {
    final api = EgyApi(httpClient: mock);
    final channel = LiveChannel({
      'id': 1481, 'provider_id': '1481',
      'name_en': 'beIN English 1', 'name_ar': 'beIN English 1',
      'package_name': 'beIN SPORTS (1080P)',
    });
    await expectLater(
      YacineLiveSourceService(api, mock).resolve(channel),
      throwsA(isA<YacineResolveException>().having(
        (error) => error.reason, 'reason',
        'provider_stream_unavailable_empty')),
    );
  });
}

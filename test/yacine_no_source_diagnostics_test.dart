import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';

Future<String> errorFor(List<Object?> data) async {
  final client = MockClient((request) async =>
    http.Response(jsonEncode({'data': data}), 200,
      headers: {'content-type': 'application/json'}));
  try {
    await YacineChannelResolver(client).resolve('1001695345450440626');
    return 'none';
  } on YacineResolveException catch (error) {
    return error.reason;
  } finally {
    client.close();
  }
}

void main() {
  test('An empty provider descriptor requests an exact-catalog refresh', () async {
    expect(await errorFor([]), 'provider_stream_unavailable_empty');
    expect(yacineShouldRefreshCatalogFor('provider_stream_unavailable_empty'),
        isTrue);
    expect(yacineShouldRefreshCatalogFor('provider_stream_unavailable'),
        isTrue);
    expect(yacineShouldRefreshCatalogFor('provider_api_http_404'),
        isTrue);
  });

  test('An expired source is distinct from missing media', () async {
    expect(await errorFor([
      {'url': 'https://media.example/live/index.m3u8?e=1700000001'}
    ]), 'provider_stream_expired');
    expect(yacineShouldRefreshCatalogFor('provider_stream_expired'), isTrue);
  });

  test('Protected streams are identified, never unprotected by a retry', () async {
    expect(await errorFor([
      {'url': 'https://media.example/live/index.m3u8',
        'drm': {'enabled': true}}
    ]), 'provider_stream_protected');
    expect(yacineShouldRefreshCatalogFor('provider_stream_protected'), isFalse);
  });

  test('Invalid links and HTML embeds are not passed to Media3', () async {
    expect(await errorFor([
      {'url': 'javascript:alert(1)'}
    ]), 'provider_stream_invalid_url');
    expect(await errorFor([
      {'url': 'https://example.com/watch.html'}
    ]), 'provider_stream_format_unsupported');
  });

  test('Normal HLS source is still passed through untouched', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({
      'data': [{
        'name': 'Full HD', 'url_type': 3,
        'url': 'https://example.com/live/index.m3u8?e=1999999999',
        'headers': {
          'User-Agent': 'okhttp/4.12.0',
          'Referer': 'https://example.com/'
        },
        'drm': null,
      }]
    }), 200));
    final sources = await YacineChannelResolver(client)
        .resolve('1001695345450440626');
    expect(sources.length, 1);
    expect(sources.single.label, 'Full HD');
    expect(sources.single.uri.host, 'example.com');
    expect(sources.single.headers['User-Agent'], 'okhttp/4.12.0');
    expect(sources.single.headers['Referer'], 'https://example.com/');
    client.close();
  });
}

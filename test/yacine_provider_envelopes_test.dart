import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';

Future<List<YacinePlaybackSource>> resolveWith(Object? data) async {
  final client = MockClient((request) async {
    expect(request.url.path, '/api/channel/1001695345450440626');
    return http.Response(
      jsonEncode({'data': data}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  try {
    return await YacineChannelResolver(client)
        .resolve('1001695345450440626');
  } finally {
    client.close();
  }
}

Future<String> resolveFailure(Object? data) async {
  try {
    await resolveWith(data);
  } on YacineResolveException catch (error) {
    return error.reason;
  }
  return 'none';
}

void main() {
  test('Nested source envelope returns the same valid stream and headers',
      () async {
    final rows = await resolveWith({
      'sources': [
        {
          'url': 'https://media.example/live/index.m3u8?e=1999999999',
          'name': '1080P',
          'url_type': 3,
          'headers': {
            'User-Agent': 'EGYSHOW-Test/1.0',
            'Referer': 'https://media.example/player',
          },
        }
      ],
    });
    expect(rows, hasLength(1));
    expect(rows.single.uri.host, 'media.example');
    expect(rows.single.label, '1080P');
    expect(rows.single.headers['User-Agent'], 'EGYSHOW-Test/1.0');
    expect(rows.single.headers['Referer'],
        'https://media.example/player');
  });

  test('Supports bounded nested result/data/streams envelope', () async {
    final rows = await resolveWith({
      'result': {
        'data': {
          'streams': [
            {'url': 'https://media.example/live.m3u8', 'url_type': 3}
          ]
        }
      }
    });
    expect(rows, hasLength(1));
  });

  test('Supports direct source map without treating other metadata as URLs',
      () async {
    final rows = await resolveWith({
      'url': 'https://media.example/movie.mp4',
      'name': 'Direct'
    });
    expect(rows, hasLength(1));
    expect(rows.single.label, 'Direct');
  });

  test('Truly empty array remains a missing-source condition', () async {
    expect(await resolveFailure([]), 'provider_stream_unavailable_empty');
    expect(yacineShouldRefreshCatalogFor('provider_stream_unavailable_empty'),
        isTrue);
  });

  test('Unexpected schema is not reported as an empty source list', () async {
    expect(await resolveFailure({'status': 'offline'}),
        'provider_data_schema_unsupported');
    expect(yacineShouldRefreshCatalogFor('provider_data_schema_unsupported'),
        isFalse);
  });

  test('Nested response with DRM remains protected', () async {
    expect(await resolveFailure({
      'sources': [
        {
          'url': 'https://media.example/live.m3u8',
          'drm': {'enabled': true}
        }
      ]
    }), 'provider_stream_protected');
  });
}

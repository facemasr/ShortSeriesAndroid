import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/native_api.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';
import 'package:egyshow_mobile/yacine_live_source_service.dart';

const oldId = '944153532374543408';
const currentId = '8385833572085990112';
const sdId = '8385833573281469359';
const otherId = '8385833572085240457';

LiveChannel stale() => LiveChannel({
  'id': 100,
  'provider_id': oldId,
  'name_ar': 'beIN SPORTS 1',
  'name_en': 'beIN SPORTS 1',
  'package_name': 'beIN SPORTS (1080P)',
});

http.Response list(List<Map<String, Object?>> data) =>
    http.Response(jsonEncode({'data': data}), 200);

Map<String, Object?> descriptor([String label = '1080P']) => {
  'name': label,
  'url_type': 3,
  'url': 'https://media.example/live/index.m3u8?e=1999999999',
  'user_agent': 'Real-Provider-Agent',
  'referer': 'https://media.example/player',
};

MockClient provider({
  required List<String> requests,
  bool fullHdEmpty = false,
  bool sdAvailable = true,
  bool otherStationOnly = false,
  bool protected = false,
}) => MockClient((request) async {
  requests.add(request.url.path);
  switch (request.url.path) {
    case '/api/categories':
      return list([
        {'id': '30', 'name': 'beIN SPORTS (1080P)', 'child_count': 0},
        {'id': '31', 'name': 'beIN SPORTS (720P)', 'child_count': 0},
      ]);
    case '/api/categories/30/channels':
      return list([
        {'id': otherId, 'name': 'beIN SPORTS 2'},
        if (!otherStationOnly)
          {'id': currentId, 'name': 'beIN SPORTS 1'},
      ]);
    case '/api/categories/31/channels':
      return list([
        {'id': sdId, 'name': 'beIN SPORTS 1'},
      ]);
    case '/api/channel/' + currentId:
      if (fullHdEmpty) return list([]);
      return list([
        if (protected)
          {'url': 'https://media.example/protected.m3u8',
            'drm': {'enabled': true}}
        else
          descriptor(),
        if (!protected) descriptor('Backup'),
      ]);
    case '/api/channel/' + sdId:
      return list(sdAvailable ? [descriptor('720P')] : []);
    default:
      return http.Response('not found', 404);
  }
});

void main() {
  test('Rotated ID uses current catalog before requesting descriptor',
      () async {
    final requests = <String>[];
    final client = provider(requests: requests);
    final api = EgyApi(httpClient: client);
    try {
      final result = await YacineLiveSourceService(api, client)
          .resolve(stale());
      expect(result.channel.providerId, currentId);
      expect(result.sources, hasLength(2));
      expect(result.sources.first.label, '1080P');
      expect(result.sources.first.headers['User-Agent'],
          'Real-Provider-Agent');
      expect(result.sources.first.headers['Referer'],
          'https://media.example/player');
      expect(requests, contains('/api/channel/' + currentId));
      expect(requests, isNot(contains('/api/channel/' + oldId)));
      expect(result.recovery, 'rotated_station_id');
    } finally {
      api.dispose();
    }
  });

  test('Current empty quality tries exact same station at 720P', () async {
    final requests = <String>[];
    final client = provider(requests: requests, fullHdEmpty: true);
    final api = EgyApi(httpClient: client);
    try {
      final result = await YacineLiveSourceService(api, client)
          .resolve(stale());
      expect(result.channel.providerId, sdId);
      expect(result.sources.single.label, '720P');
      expect(result.recovery, 'verified_quality_source');
      expect(requests, contains('/api/channel/' + sdId));
      expect(requests, isNot(contains('/api/channel/' + otherId)));
    } finally {
      api.dispose();
    }
  });

  test('Rejects replacement by similarly named but different station',
      () async {
    final requests = <String>[];
    final client = provider(requests: requests,
        otherStationOnly: true, sdAvailable: false);
    final api = EgyApi(httpClient: client);
    try {
      try {
        await YacineLiveSourceService(api, client).resolve(stale());
        fail('There is no usable matching channel');
      } on YacineResolveException catch (error) {
        expect(error.reason, isNotEmpty);
      }
      expect(requests, isNot(contains('/api/channel/' + otherId)));
    } finally {
      api.dispose();
    }
  });

  test('DRM-protected descriptor is not retried using sibling qualities',
      () async {
    final requests = <String>[];
    final client = provider(requests: requests, protected: true);
    final api = EgyApi(httpClient: client);
    try {
      await expectLater(
        YacineLiveSourceService(api, client).resolve(stale()),
        throwsA(isA<YacineResolveException>().having(
            (error) => error.reason, 'reason', 'provider_stream_protected')),
      );
      expect(requests, isNot(contains('/api/channel/' + sdId)));
    } finally {
      api.dispose();
    }
  });
}

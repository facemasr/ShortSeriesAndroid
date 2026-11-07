import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/native_api.dart';

LiveChannel stale({
  String group = 'Sports / beIN SPORTS (1080P)',
  String name = 'beIN SPORTS 1',
}) => LiveChannel({
  'provider_id': '1001695346839014961',
  'name_en': name,
  'name_ar': name,
  'package_name': group,
});

http.Response rows(List<Map<String, Object>> data) =>
  http.Response(jsonEncode({'data': data}), 200,
      headers: {'content-type': 'application/json'});

void main() {
  test('404 recovery walks a nested catalog and selects the exact station',
      () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url.path);
      expect(request.headers['User-Agent'], 'okhttp/4.12.0');
      switch (request.url.path) {
        case '/api/categories':
          return rows([{'id': '31', 'name': 'Sports', 'child_count': 1}]);
        case '/api/categories/31':
          return rows([{'id': '32', 'name': 'beIN SPORTS (1080P)',
              'child_count': 0}]);
        case '/api/categories/32/channels':
          return rows([
            {'id': '907', 'name': 'beIN SPORTS 2'},
            {'id': '6098366605392178279', 'name': 'beIN SPORTS 1'}
          ]);
      }
      return http.Response('not found', 404);
    });
    final api = EgyApi(httpClient: client);
    final result = await api.refreshProviderChannel(stale());
    expect(result?.providerId, '6098366605392178279');
    expect(result?.title(false), 'beIN SPORTS 1');
    expect(result?.group, 'Sports / beIN SPORTS (1080P)');
    expect(requests, [
      '/api/categories',
      '/api/categories/31',
      '/api/categories/32/channels',
    ]);
    api.dispose();
  });

  test('404 recovery refuses to substitute similarly named channel', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/categories') {
        return rows([{'id': '32', 'name': 'beIN SPORTS (1080P)',
            'child_count': 0}]);
      }
      return rows([{'id': '907', 'name': 'beIN SPORTS 2'}]);
    });
    final api = EgyApi(httpClient: client);
    expect(await api.refreshProviderChannel(stale(
      group: 'beIN SPORTS (1080P)')), isNull);
    api.dispose();
  });

  test('flat category supports rotated ID without scanning all stations',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/categories') {
        return rows([{'id': '32', 'name': 'beIN SPORTS (1080P)',
            'child_count': 0}]);
      }
      return rows([{'id': '6098366605392178279', 'name': 'beIN SPORTS 1'}]);
    });
    final api = EgyApi(httpClient: client);
    final result = await api.refreshProviderChannel(
      stale(group: 'beIN SPORTS (1080P)'));
    expect(result?.providerId, '6098366605392178279');
    api.dispose();
  });
}

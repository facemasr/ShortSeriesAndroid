import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/native_api.dart';

http.Response rows(List<Map<String, Object>> data) =>
    http.Response(jsonEncode({'data': data}), 200,
        headers: {'content-type': 'application/json'});

LiveChannel stale(String group, String name) => LiveChannel({
      'provider_id': '944153532374543408',
      'name_en': name,
      'name_ar': name,
      'package_name': group,
    });

void main() {
  test('refresh beIN SPORTS 1 across four current quality packages', () async {
    final paths = <String>[];
    final client = MockClient((r) async {
      paths.add(r.url.path);
      expect(r.headers['User-Agent'], 'okhttp/4.12.0');
      if (r.url.path == '/api/categories') {
        return rows([
          {'id': '10', 'name': 'beIN SPORTS (1080P)', 'child_count': 0},
          {'id': '11', 'name': 'beIN SPORTS (720P)', 'child_count': 0},
          {'id': '12', 'name': 'beIN SPORTS (360P)', 'child_count': 0},
          {'id': '13', 'name': 'beIN SPORTS (244P)', 'child_count': 0},
          {'id': '14', 'name': 'MBC CHANNELS', 'child_count': 0},
        ]);
      }
      final id = r.url.path.split('/')[3];
      if (id == '10') return rows([
        {'id': '3330321337737954745', 'name': 'beIN SPORTS 1'},
        {'id': '3330321337739320374', 'name': 'beIN SPORTS 2'}
      ]);
      if (id == '11') return rows([
        {'id': '3330321339193721856', 'name': 'beIN SPORTS 1'}
      ]);
      if (id == '12') return rows([
        {'id': '3330321339206588888', 'name': 'beIN SPORTS 1'}
      ]);
      if (id == '13') return rows([
        {'id': '3330321339151346286', 'name': 'beIN SPORTS 1'}
      ]);
      return rows([{'id': '99', 'name': 'MBC 1'}]);
    });
    final api = EgyApi(httpClient: client);
    final result = await api.refreshLiveQualityVariants(
        stale('beIN SPORTS (1080P)', 'beIN SPORTS 1'));
    expect(result.map((c) => c.providerId).toList(), [
      '3330321337737954745',
      '3330321339193721856',
      '3330321339206588888',
      '3330321339151346286'
    ]);
    expect(result.map((c) => c.group).toList(), [
      'beIN SPORTS (1080P)',
      'beIN SPORTS (720P)',
      'beIN SPORTS (360P)',
      'beIN SPORTS (244P)'
    ]);
    expect(paths.length, 5);
    expect(paths.any((p) => p.contains('/14/channels')), isFalse);
    api.dispose();
  });

  test('nested quality package follows exact parent category', () async {
    final client = MockClient((r) async {
      switch (r.url.path) {
        case '/api/categories':
          return rows([
            {'id': '20', 'name': 'Sports', 'child_count': 1},
            {'id': '30', 'name': 'Other', 'child_count': 1},
          ]);
        case '/api/categories/20':
          return rows([
            {'id': '21', 'name': 'beIN SPORTS (1080P)', 'child_count': 0},
            {'id': '22', 'name': 'beIN SPORTS (720P)', 'child_count': 0},
          ]);
        case '/api/categories/21/channels':
          return rows([{'id': '201', 'name': 'beIN SPORTS 1'}]);
        case '/api/categories/22/channels':
          return rows([{'id': '202', 'name': 'beIN SPORTS 1'}]);
      }
      return http.Response('not found', 404);
    });
    final api = EgyApi(httpClient: client);
    final options = await api.refreshLiveQualityVariants(
      stale('Sports / beIN SPORTS (1080P)', 'beIN SPORTS 1'));
    expect(options.map((x) => x.providerId), ['201', '202']);
    expect(options[1].group, 'Sports / beIN SPORTS (720P)');
    api.dispose();
  });

  test('never substitute beIN SPORTS 2 for beIN SPORTS 1', () async {
    final client = MockClient((r) async {
      if (r.url.path == '/api/categories') {
        return rows([{'id': '10', 'name': 'beIN SPORTS (720P)',
            'child_count': 0}]);
      }
      return rows([{'id': '202', 'name': 'beIN SPORTS 2'}]);
    });
    final api = EgyApi(httpClient: client);
    final options = await api.refreshLiveQualityVariants(
        stale('beIN SPORTS (1080P)', 'beIN SPORTS 1'));
    expect(options, isEmpty);
    api.dispose();
  });
}

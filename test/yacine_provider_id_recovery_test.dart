import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/native_api.dart';

void main() {
  LiveChannel oldChannel() => LiveChannel(<String, dynamic>{
    'id': 1424,
    'provider_id': '1424',
    'name_ar': 'beIN SPORTS 1',
    'name_en': 'beIN SPORTS 1',
    'package_name': 'beIN SPORTS (720P)',
  });

  test('rotated beIN numeric ID is recovered from current package and station',
      () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.url.path);
      expect(request.url.host, 'def001.ycnapi.com');
      if (request.url.path == '/api/categories') {
        return http.Response(jsonEncode({'data': [
          {'id': '450048112644538348',
           'name': 'beIN SPORTS (720P)', 'child_count': 0},
          {'id': '999', 'name': 'MBC CHANNELS', 'child_count': 0},
        ]}), 200);
      }
      if (request.url.path ==
          '/api/categories/450048112644538348/channels') {
        return http.Response(jsonEncode({'data': [
          {'id': '6098366605393296554', 'name': 'beIN SPORTS 2'},
          {'id': '6098366605392178279', 'name': 'beIN SPORTS 1'},
        ]}), 200);
      }
      return http.Response('{}', 404);
    });
    final api = EgyApi(httpClient: client);
    final current = await api.refreshProviderChannel(oldChannel());
    expect(current, isNotNull);
    expect(current!.providerId, '6098366605392178279');
    expect(current.group, 'beIN SPORTS (720P)');
    expect(current.title(false), 'beIN SPORTS 1');
    expect(calls, [
      '/api/categories',
      '/api/categories/450048112644538348/channels',
    ]);
    api.dispose();
  });

  test('same package but a different station cannot replace stale ID', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/categories') {
        return http.Response(jsonEncode({'data': [
          {'id': '450048112644538348',
           'name': 'beIN SPORTS (720P)', 'child_count': 0},
        ]}), 200);
      }
      return http.Response(jsonEncode({'data': [
        {'id': '6098366605393296554', 'name': 'beIN SPORTS 2'}
      ]}), 200);
    });
    final api = EgyApi(httpClient: client);
    expect(await api.refreshProviderChannel(oldChannel()), isNull);
    api.dispose();
  });
}

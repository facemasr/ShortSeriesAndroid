import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:egyshow_mobile/native_api.dart';

void main() {
  test('expired member token notifies the shell even on non-JSON 401', () async {
    var invalidations = 0;
    final api = EgyApi(httpClient: MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer member-token');
      return http.Response('Unauthorized', 401);
    }));
    addTearDown(api.dispose);
    api.token = 'member-token';
    api.onUnauthorized = () => invalidations++;
    await expectLater(api.profile(), throwsA(isA<ApiException>()));
    expect(invalidations, 1);
  });

  test('guest sign-in failure does not invalidate an unrelated session', () async {
    var invalidations = 0;
    final api = EgyApi(httpClient: MockClient((_) async =>
        http.Response('{"ok":false}', 401)));
    addTearDown(api.dispose);
    api.onUnauthorized = () => invalidations++;
    await expectLater(api.authenticate('user@example.com', 'wrong'),
        throwsA(isA<ApiException>()));
    expect(invalidations, 0);
  });

  test('late response for old token cannot invalidate new session', () async {
    final response = Completer<http.Response>();
    final api = EgyApi(httpClient: MockClient((_) => response.future));
    addTearDown(api.dispose);
    var invalidations = 0;
    api.token = 'old-token';
    api.onUnauthorized = () => invalidations++;
    final pending = api.profile();
    api.token = 'new-token';
    response.complete(http.Response('Unauthorized', 401));
    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(invalidations, 0);
  });
}

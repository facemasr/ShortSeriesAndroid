import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/native_api.dart';
import 'package:egyshow_mobile/yacine_live_station_sync.dart';

LiveChannel station(String id, {String name = 'beIN SPORTS 1'}) =>
    LiveChannel({
      'provider_id': id,
      'name_ar': name,
      'name_en': name,
      'package_name': 'beIN SPORTS (1080P)',
    });

void main() {
  test('rotated beIN ID is replaced with current catalog ID', () async {
    final result = await yacineFindLiveStation(
      station: station('944153532374543408'),
      currentProviderId: '944153532374543408',
      refreshStation: (stale) async {
        expect(stale.title(false), 'beIN SPORTS 1');
        expect(stale.group, 'beIN SPORTS (1080P)');
        return station('3330321337737954745');
      },
    );
    expect(result.providerId, '3330321337737954745');
    expect(result.outcome, 'updated_provider_id');
  });

  test('live ID does not force needless restart', () async {
    final result = await yacineFindLiveStation(
      station: station('3330321337737954745'),
      currentProviderId: '3330321337737954745',
      refreshStation: (stale) async => station(stale.providerId),
    );
    expect(result.outcome, 'verified_live_id');
  });

  test('missing exact station never substitutes another channel', () async {
    final result = await yacineFindLiveStation(
      station: station('944153532374543408'),
      currentProviderId: '944153532374543408',
      refreshStation: (_) async => null,
    );
    expect(result.providerId, '944153532374543408');
    expect(result.outcome, 'station_not_found_in_live_catalog');
  });

  test('provider timeout falls back to standard resolver, never hangs', () async {
    final result = await yacineFindLiveStation(
      station: station('944153532374543408'),
      currentProviderId: '944153532374543408',
      refreshStation: (_) => Completer<LiveChannel?>().future,
      timeout: const Duration(milliseconds: 2),
    );
    expect(result.outcome, 'catalog_timeout_using_last_id');
  });

  test('provider failure does not fabricate a station ID', () async {
    final result = await yacineFindLiveStation(
      station: station('944153532374543408'),
      currentProviderId: '944153532374543408',
      refreshStation: (_) async => throw StateError('offline'),
    );
    expect(result.providerId, '944153532374543408');
    expect(result.outcome, 'catalog_unavailable_using_last_id');
  });
}

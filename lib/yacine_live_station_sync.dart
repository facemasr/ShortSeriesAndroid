import 'dart:async';

import 'native_api.dart';

/// Validate a channel's current ID against the provider's LIVE catalog before
/// requesting media. Provider IDs rotate independently of the station name.
///
/// The exact station name AND original category path must match (see
/// EgyApi.refreshProviderChannel). If the catalog cannot be reached, keep
/// the previous ID and allow the normal resolver/error recovery to run.
class YacineLiveStationSync {
  const YacineLiveStationSync(this.providerId, this.outcome);

  final String providerId;
  final String outcome;
}

Future<YacineLiveStationSync> yacineFindLiveStation({
  required LiveChannel station,
  required String currentProviderId,
  required Future<LiveChannel?> Function(LiveChannel) refreshStation,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    final current = await refreshStation(station).timeout(timeout);
    if (current == null || current.providerId.isEmpty) {
      return YacineLiveStationSync(
          currentProviderId, 'station_not_found_in_live_catalog');
    }
    if (current.providerId == currentProviderId) {
      return YacineLiveStationSync(currentProviderId, 'verified_live_id');
    }
    return YacineLiveStationSync(current.providerId, 'updated_provider_id');
  } on TimeoutException {
    return YacineLiveStationSync(
        currentProviderId, 'catalog_timeout_using_last_id');
  } catch (_) {
    return YacineLiveStationSync(
        currentProviderId, 'catalog_unavailable_using_last_id');
  }
}

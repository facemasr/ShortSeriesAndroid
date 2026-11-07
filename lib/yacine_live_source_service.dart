import 'package:http/http.dart' as http;

import 'native_api.dart';
import 'yacine_channel_groups.dart';
import 'yacine_channel_resolver.dart';

/// One active station at a time: current catalog ID -> current stream
/// descriptor -> authorized media URL and provider-declared HTTP headers.
/// The catalog holds station metadata ONLY, never signed media URLs.
class YacineStationResolution {
  const YacineStationResolution({
    required this.channel,
    required this.sources,
    required this.sourceIndex,
    required this.recovery,
    required this.attemptedIds,
  });

  final LiveChannel channel;
  final List<YacinePlaybackSource> sources;
  final int sourceIndex;
  final String recovery;
  final int attemptedIds;
}

/// Mirrors EGY TV Sport's ChannelService.sources: request the selected
/// channel on this device, then refresh only the source currently playing.
/// A stale ID, a real empty descriptor, and a failed decoder are distinct.
/// This service never opens media or bypasses DRM/authorization.
class YacineLiveSourceService {
  const YacineLiveSourceService(this.api, this.client);
  final EgyApi api;
  final http.Client client;

  static String _name(LiveChannel channel) =>
      channel.title(false).trim().toLowerCase();

  static String _family(LiveChannel channel) =>
      yacineWithoutQuality(channel.group).trim().toLowerCase();

  static bool _sameStation(LiveChannel original, LiveChannel candidate) =>
      _name(original).isNotEmpty &&
      _name(original) == _name(candidate) &&
      _family(original).isNotEmpty &&
      _family(original) == _family(candidate);

  /// Resolve the LIVE station ID before opening media. When the exact
  /// quality has no media, check only the same station's sibling qualities.
  /// Every alternate ID must return its own non-empty descriptor; an
  /// unverified catalog record is never treated as a playable URL.
  Future<YacineStationResolution> resolve(
    LiveChannel station, {
    String? preferredProviderId,
    int preferredSourceIndex = 0,
    int maxQualityCandidates = 8,
  }) async {
    final resolver = YacineChannelResolver(client);
    final candidates = <LiveChannel>[];
    final tried = <String>{};
    YacineResolveException? lastSourceError;
    String discovery = 'current_catalog_checked';

    void enqueue(LiveChannel channel) {
      final id = channel.providerId;
      if (RegExp(r'^\d{1,24}.hasMatch(id) &&
          _sameStation(station, channel) &&
          !candidates.any((candidate) => candidate.providerId == id)) {
        candidates.add(channel);
      }
    }

    // Current ID first: the old numeric IDs in the disk catalog may have
    // rotated since the visitor last opened the app.
    try {
      final current = await api.refreshProviderChannel(station)
          .timeout(const Duration(seconds: 18));
      if (current != null) {
        enqueue(current);
        discovery = current.providerId == station.providerId
            ? 'verified_current_station'
            : 'rotated_station_id';
      } else {
        discovery = 'exact_station_not_in_current_catalog';
      }
    } catch (_) {
      discovery = 'current_catalog_unreachable';
    }

    final originalId = preferredProviderId ?? station.providerId;
    enqueue(LiveChannel({...station.raw, 'provider_id': originalId}));
    enqueue(station);

    Future<YacineStationResolution?> attempt(LiveChannel candidate,
        String recovery) async {
      if (!tried.add(candidate.providerId)) return null;
      try {
        final sources = await resolver.resolve(candidate.providerId);
        if (sources.isEmpty) return null;
        final index = preferredSourceIndex >= 0 &&
                preferredSourceIndex < sources.length
            ? preferredSourceIndex : 0;
        return YacineStationResolution(
          channel: candidate,
          sources: sources,
          sourceIndex: index,
          recovery: recovery,
          attemptedIds: tried.length,
        );
      } on YacineResolveException catch (error) {
        // DRM and access restrictions are never treated as a signal to
        // obtain an alternative protected stream.
        if (error.reason == 'provider_stream_protected' ||
            error.reason == 'provider_data_schema_unsupported' ||
            error.reason == 'provider_channel_invalid') {
          rethrow;
        }
        lastSourceError = error;
      }
      return null;
    }

    for (final candidate in candidates) {
      final result = await attempt(candidate, discovery);
      if (result != null) return result;
    }

    // Only search a bounded set of quality siblings for the EXACT station
    // and package family. Never substitute another channel by fuzzy name.
    List<LiveChannel> variants;
    try {
      variants = await api.refreshLiveQualityVariants(station)
          .timeout(const Duration(seconds: 22));
    } catch (_) {
      if (lastSourceError != null) throw lastSourceError!;
      throw const YacineResolveException('provider_live_catalog_unavailable');
    }
    final originalQuality = yacineChannelQuality(station) ?? 720;
    variants = variants.where((v) =>
        _sameStation(station, v) && !tried.contains(v.providerId)).toList();
    variants.sort((a, b) {
      int score(LiveChannel value) {
        final quality = yacineChannelQuality(value) ?? 720;
        return quality <= originalQuality
            ? originalQuality - quality
            : 10000 + quality - originalQuality;
      }
      return score(a).compareTo(score(b));
    });

    for (final candidate in variants.take(maxQualityCandidates)) {
      final result = await attempt(candidate, 'verified_quality_source');
      if (result != null) return result;
    }

    if (lastSourceError != null) throw lastSourceError!;
    throw const YacineResolveException('provider_no_playable_station_source');
  }
}

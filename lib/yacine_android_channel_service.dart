import 'dart:async';

import 'package:http/http.dart' as http;

import 'yacine_channel_resolver.dart';
import 'yacine_stream_probe.dart';

/// Android translation of EGY TV Sport Windows/stream_core.py:
/// ChannelService.sources -> choose(quick_check) -> ActiveChannel refresh.
///
/// It fetches the provider's CURRENT channel descriptor on this device.
/// Signed URLs and supplied media headers are deliberately never persisted.
/// A probe is diagnostic only: the actual Android decoder decides playback.
enum EgyTvProbeStatus {
  segmentReachable,
  manifestOnly,
  unchecked,
  unavailable,
}

class EgyTvStreamChoice {
  const EgyTvStreamChoice({
    required this.sources,
    required this.index,
    required this.status,
    this.reason,
  });
  final List<YacinePlaybackSource> sources;
  final int index;
  final EgyTvProbeStatus status;
  final String? reason;

  YacinePlaybackSource get selected => sources[index];
}

class EgyTvAndroidChannelService {
  const EgyTvAndroidChannelService(this.client);

  final http.Client client;

  /// Matches the desktop source strategy:
  /// - Resolve the selected channel (not all channels).
  /// - Preserve provider order and the preferred source index.
  /// - Check at most five HLS candidates before the FIRST playback.
  /// - Prefer a manifest with an accessible media segment.
  /// - Never make a failed/blocked HTTP probe prevent the native player
  ///   from attempting a still-valid provider source.
  Future<EgyTvStreamChoice> choose(
    String providerId, {
    int? preferredIndex,
    bool quickCheck = false,
  }) async {
    final sources = await YacineChannelResolver(client).resolve(providerId);
    final indices = <int>[
      if (preferredIndex != null && preferredIndex >= 0 &&
          preferredIndex < sources.length) preferredIndex,
      for (var i = 0; i < sources.length; i++)
        if (i != preferredIndex) i,
    ];
    final first = indices.first;
    if (!quickCheck) {
      return EgyTvStreamChoice(
          sources: sources, index: first, status: EgyTvProbeStatus.unchecked);
    }

    EgyTvStreamChoice? manifestOnly;
    EgyTvStreamChoice? unavailable;
    for (final index in indices.take(5)) {
      final source = sources[index];
      final path = source.uri.path.toLowerCase();
      final hls = path.endsWith('.m3u8') ||
          source.providerMode?.toString() == '3';
      if (!hls) {
        // Windows passes progressive media straight to libVLC when a
        // bounded probe cannot identify an HLS media segment.
        return EgyTvStreamChoice(
            sources: sources, index: index, status: EgyTvProbeStatus.unchecked);
      }
      try {
        final status = await YacineMediaProbe(client)
            .verifyHls(source.uri, source.headers)
            .timeout(const Duration(seconds: 8));
        if (status == YacineMediaStatus.segmentReachable) {
          return EgyTvStreamChoice(sources: sources, index: index,
              status: EgyTvProbeStatus.segmentReachable);
        }
        manifestOnly ??= EgyTvStreamChoice(sources: sources,
            index: index, status: EgyTvProbeStatus.manifestOnly);
      } on YacineProbeFailure catch (e) {
        unavailable ??= EgyTvStreamChoice(sources: sources,
            index: index, status: EgyTvProbeStatus.unavailable,
            reason: e.code);
      } on TimeoutException {
        unavailable ??= EgyTvStreamChoice(sources: sources,
            index: index, status: EgyTvProbeStatus.unavailable,
            reason: 'source_timeout');
      } catch (_) {
        unavailable ??= EgyTvStreamChoice(sources: sources,
            index: index, status: EgyTvProbeStatus.unavailable,
            reason: 'source_network_error');
      }
    }
    return manifestOnly ?? unavailable ?? EgyTvStreamChoice(
        sources: sources, index: first, status: EgyTvProbeStatus.unchecked);
  }

  /// Called by the foreground player on its refresh timer. Re-fetch exactly
  /// one selected channel, then retain the corresponding server label where
  /// available (same as the desktop ActiveChannel.preferred_index).
  Future<EgyTvStreamChoice> refresh(
      String providerId, {
      required String? currentLabel,
      required int currentIndex,
    }) async {
    final sources = await YacineChannelResolver(client).resolve(providerId);
    final sameLabel = currentLabel == null ? -1 :
        sources.indexWhere((s) => s.label == currentLabel);
    final selected = sameLabel >= 0 ? sameLabel :
        currentIndex >= 0 && currentIndex < sources.length
            ? currentIndex : 0;
    return EgyTvStreamChoice(sources: sources, index: selected,
        status: EgyTvProbeStatus.unchecked);
  }
}

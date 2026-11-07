import 'package:flutter_vlc_player/flutter_vlc_player.dart';

/// Mirror EGY TV Sport Desktop's real media headers and VLC reconnect
/// configuration. The API request User-Agent is intentionally NOT reused as
/// the player identity; only validated per-source headers are passed here.
VlcPlayerOptions yacineVlcOptions(Map<String, String> headers) {
  final ua = headers['User-Agent'];
  final ref = headers['Referer'];
  return VlcPlayerOptions(
    advanced: VlcAdvancedOptions(<String>[
      VlcAdvancedOptions.networkCaching(1800),
      VlcAdvancedOptions.liveCaching(1800),
    ]),
    http: VlcHttpOptions(<String>[
      VlcHttpOptions.httpReconnect(true),
      VlcHttpOptions.httpContinuous(true),
      if (ua != null && ua.isNotEmpty)
        VlcHttpOptions.httpUserAgent(ua),
      if (ref != null && ref.isNotEmpty)
        VlcHttpOptions.httpReferrer(ref),
    ]),
  );
}

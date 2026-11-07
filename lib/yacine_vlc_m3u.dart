/// Formats an on-demand, provider-authorized channel as VLC-compatible M3U.
/// Only VLC-supported User-Agent and Referrer options are serialized. Other
/// validated request headers are passed directly to the embedded Android player.
/// Expiring signed URLs must be resolved freshly before calling this function.
String yacineVlcM3u({
  required Uri stream,
  required String channelName,
  required String tvgId,
  required String groupTitle,
  required Map<String, String> headers,
}) {
  if (!stream.hasAuthority || stream.userInfo.isNotEmpty ||
      (stream.scheme != 'https' && stream.scheme != 'http')) {
    throw ArgumentError('Invalid HTTP stream URL');
  }

  String meta(String raw) => raw
      .replaceAll(RegExp(r'[\r\n\x00-\x1F\x7F]'), ' ')
      .replaceAll('"', "'")
      .trim();

  String? option(String key) {
    final raw = headers[key];
    if (raw == null || raw.isEmpty || raw.length > 1024 ||
        RegExp(r'[\r\n\x00-\x1F\x7F]').hasMatch(raw) ||
        raw.runes.any((r) => r > 0x7e)) return null;
    return raw;
  }

  final agent = option('User-Agent');
  final referer = option('Referer');
  final lines = <String>[
    '#EXTM3U',
    '#EXTINF:-1 tvg-id="' + meta(tvgId) + '" group-title="' +
        meta(groupTitle) + '" tvg-name="' + meta(channelName) + '",' +
        meta(channelName),
    if (agent != null) '#EXTVLCOPT:http-user-agent=' + agent,
    if (referer != null) '#EXTVLCOPT:http-referrer=' + referer,
    stream.toString(),
  ];
  return lines.join('\n') + '\n';
}

import 'dart:convert';

/// Build a single, consistent header map for native Android media playback.
///
/// Provider metadata may put fields in the descriptor or nested "headers".
/// Signed URLs remain in memory only. Do not derive authentication credentials,
/// cookies, DRM keys, or artificial Origin/Referer values.
/// No User-Agent is forced when the provider does not supply one: ExoPlayer,
/// VLC and browsers can then use their own platform identity.
Map<String, String> yacinePlaybackHeaders(
  Map<String, dynamic> descriptor, {
  String? fallbackUserAgent,
}) {
  final nested = _nestedHeaders(descriptor['headers']);

  Object? field(Map<String, dynamic> map, List<String> names) {
    final keys = names.map(_key).toSet();
    for (final entry in map.entries) {
      if (keys.contains(_key(entry.key))) return entry.value;
    }
    return null;
  }

  String? textHeader(Object? value) {
    if (value is! String || value.length > 2048) return null;
    // Common zero-width characters are embedded in some provider Referers.
    // They are not legal HTTP header bytes, and must never reach ExoPlayer.
    final cleaned = value
        .replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFEFF]'), '')
        .trim();
    if (cleaned.isEmpty || cleaned.length > 1024 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(cleaned) ||
        cleaned.runes.any((r) => r > 0x7E)) return null;
    return cleaned;
  }

  String? urlHeader(Object? value) {
    if (value is! String || value.isEmpty || value.length > 2048) return null;
    final raw = value.trim();
    if (raw.isEmpty ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(raw)) return null;
    // Match EGY TV Sport Desktop: preserve the provider's Referer/Origin
    // data by UTF-8 percent-encoding non-ASCII code points, NOT deleting
    // invisible characters. The resulting HTTP header is ASCII-safe.
    // Existing percent-escapes and URL separators are left untouched.
    final output = StringBuffer();
    for (final rune in raw.runes) {
      if (rune >= 0x20 && rune <= 0x7E) {
        output.writeCharCode(rune);
      } else {
        for (final byte in utf8.encode(String.fromCharCode(rune))) {
          output.write('%');
          output.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
        }
      }
    }
    final encoded = output.toString();
    if (encoded.length > 4096) return null;
    final uri = Uri.tryParse(encoded);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    return encoded;
  }

  // In the Windows player these provider-declared session headers are sent
  // only by the on-device relay. Never include them in M3U exports or logs.
  String? sessionHeader(Object? value) {
    if (value is! String || value.isEmpty || value.length > 4096 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(value) ||
        value.runes.any((r) => r > 0x7E)) return null;
    return value;
  }

  String? pickSession(List<String> aliases) =>
      sessionHeader(field(nested, aliases));

  String? pickText(List<String> aliases) =>
      textHeader(field(descriptor, aliases)) ??
      textHeader(field(nested, aliases));

  String? pickUrl(List<String> aliases) =>
      urlHeader(field(descriptor, aliases)) ??
      urlHeader(field(nested, aliases));

  // Provider media identity wins. When not declared, allow the active native
  // device, VLC, or browser to send its own real User-Agent.
  final agent = pickText(['user_agent', 'user-agent', 'useragent']) ??
      textHeader(fallbackUserAgent);
  final referer = pickUrl(['referer', 'referrer']);
  final origin = pickUrl(['origin']);
  final accept = pickText(['accept']);
  final acceptLanguage = pickText(['accept-language', 'accept_language']);
  final cacheControl = pickText(['cache-control', 'cache_control']);
  final cookie = pickSession(['cookie']);
  final authorization = pickSession(['authorization']);
  final authToken = pickSession(['x-auth-token']);

  return {
    if (agent != null) 'User-Agent': agent,
    if (referer != null) 'Referer': referer,
    if (origin != null) 'Origin': origin,
    if (accept != null) 'Accept': accept,
    if (acceptLanguage != null) 'Accept-Language': acceptLanguage,
    if (cacheControl != null) 'Cache-Control': cacheControl,
    if (cookie != null) 'Cookie': cookie,
    if (authorization != null) 'Authorization': authorization,
    if (authToken != null) 'X-Auth-Token': authToken,
  };
}

String _key(String value) =>
    value.replaceAll(RegExp(r'[-_\s]'), '').toLowerCase();

Map<String, dynamic> _nestedHeaders(Object? raw) {
  Object? value = raw;
  if (value is String && value.length <= 8192) {
    try { value = jsonDecode(value); } catch (_) { return {}; }
  }
  if (value is! Map) return {};
  final result = <String, dynamic>{};
  for (final item in value.entries) {
    if (item.key is String) result[item.key as String] = item.value;
  }
  return result;
}

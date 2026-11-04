import 'dart:convert';

/// Build a single, consistent header map for native Android media playback.
///
/// Provider metadata may put fields in the descriptor or nested "headers".
/// Signed URLs remain in memory only. Do not derive authentication credentials,
/// cookies, DRM keys, or artificial Origin/Referer values.
Map<String, String> yacinePlaybackHeaders(
  Map<String, dynamic> descriptor, {
  String fallbackUserAgent = 'okhttp/4.12.0',
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
    final cleaned = textHeader(value);
    if (cleaned == null) return null;
    final uri = Uri.tryParse(cleaned);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    return uri.toString();
  }

  String? pickText(List<String> aliases) =>
      textHeader(field(descriptor, aliases)) ??
      textHeader(field(nested, aliases));

  String? pickUrl(List<String> aliases) =>
      urlHeader(field(descriptor, aliases)) ??
      urlHeader(field(nested, aliases));

  final agent = pickText(['user_agent', 'user-agent', 'useragent']) ??
      textHeader(fallbackUserAgent) ?? 'okhttp/4.12.0';
  final referer = pickUrl(['referer', 'referrer']);
  final origin = pickUrl(['origin']);
  final accept = pickText(['accept']);
  final acceptLanguage = pickText(['accept-language', 'accept_language']);
  final cacheControl = pickText(['cache-control', 'cache_control']);

  return {
    'User-Agent': agent,
    if (referer != null) 'Referer': referer,
    if (origin != null) 'Origin': origin,
    if (accept != null) 'Accept': accept,
    if (acceptLanguage != null) 'Accept-Language': acceptLanguage,
    if (cacheControl != null) 'Cache-Control': cacheControl,
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

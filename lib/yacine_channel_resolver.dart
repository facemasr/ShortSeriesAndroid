import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'yacine_media_headers.dart';
import 'yacine_provider_policy.dart';
import 'yacine_stream_probe.dart';

/// Immutable device-resolved stream information, independent of the player.
/// Android ExoPlayer, browser players, and optional VLC exports consume the
/// same current URL and validated provider-supplied headers in their own ways.
Map<String, dynamic> _localMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is String) result[entry.key as String] = entry.value;
  }
  return result;
}
List<dynamic> _localList(Object? value) =>
    value is List ? value : <dynamic>[];
String _localText(Object? value) => value?.toString() ?? '';

/// Accept the provider's common, bounded JSON envelopes without interpreting
/// unrelated metadata fields as media. A genuine [] is different from an
/// unexpected response schema: report those failures separately.
List<dynamic>? yacineDescriptorRows(Object? value, [int depth = 0]) {
  if (depth >= 6) return null;
  if (value is List) return value;
  if (value is! Map) return null;
  final map = _localMap(value);
  if (map.containsKey('url')) return <dynamic>[map];

  const keys = <String>[
    'data', 'sources', 'streams', 'servers', 'items', 'result', 'playback',
  ];
  for (final key in keys) {
    if (!map.containsKey(key)) continue;
    final rows = yacineDescriptorRows(map[key], depth + 1);
    if (rows != null) return rows;
  }
  return null;
}

bool _supportedMediaUrl(Uri url, Object? providerMode) {
  final path = url.path.toLowerCase();
  if (const ['.m3u8','.m3u','.mpd','.ts','.mp4','.m4v','.webm',
    '.mkv','.mov','.mpg','.mpeg'].any(path.endsWith)) return true;
  if (path.endsWith('.ism/manifest')) return true;
  return const {'1','3'}.contains(providerMode?.toString());
}

/// Only catalog-side failures should trigger a bounded exact-station lookup.
/// DRM, licensing and malformed URLs are NOT bypassed.
bool yacineShouldRefreshCatalogFor(String reason) => const {
  'provider_api_http_404',
  'provider_stream_unavailable',
  'provider_stream_unavailable_empty',
  'provider_stream_expired',
  'provider_stream_invalid_url',
  'provider_stream_format_unsupported',
}.contains(reason);

class YacineResolveException implements Exception {
  const YacineResolveException(this.reason);
  final String reason;
  @override
  String toString() => 'YacineResolveException($reason)';
}

class YacinePlaybackSource {
  const YacinePlaybackSource(this.uri, this.headers, this.label, this.providerMode,
      {this.vlcPlaylistHeaders = const <String, String>{}});
  final Uri uri;
  /// ASCII-safe headers for Dart HTTP, the localhost relay and Media3.
  final Map<String, String> headers;
  /// Desktop libVLC receives the *original provider-declared* Referer media
  /// option, which may contain invisible Unicode characters. Keep this map
  /// in memory and use it ONLY for native libVLC's http-referrer option.
  final Map<String, String> vlcPlaylistHeaders;
  final String label;
  final Object? providerMode;
}

Map<String, String> yacineDesktopVlcHeaders(
    Map<String, dynamic> descriptor, Map<String, String> safeHeaders) {
  final original = descriptor['referer'];
  if (original is! String || original.isEmpty ||
      original.length > 2048 ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(original)) {
    return Map<String, String>.unmodifiable(safeHeaders);
  }
  final uri = Uri.tryParse(original);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return Map<String, String>.unmodifiable(safeHeaders);
  }
  return Map<String, String>.unmodifiable({
    ...safeHeaders,
    // Do not percent-encode the native VLC option. The Windows working
    // program passes the raw API field directly to libVLC.
    'Referer': original,
  });
}

class YacineChannelResolver {
  const YacineChannelResolver(this.client);
  final http.Client client;

  static const String _apiUrl = 'https://def001.ycnapi.com/api/channel/';
  static const String _apiAgent = 'okhttp/4.12.0';
  // The API requires its own HTTP identity; playback uses per-source headers.
  static const String _keyPrefix = 'c!xZj+N9&G@Ev@vw';

  static Map<String, dynamic> _decode(Uint8List bytes, String? stamp) {
    final input = utf8.decode(bytes).trim();
    if (input.startsWith('{')) return _localMap(jsonDecode(input));
    if (stamp == null || !RegExp(r'^[0-9]{1,16}$').hasMatch(stamp)) {
      throw const YacineResolveException('provider_data_invalid');
    }
    final encrypted = base64Decode(input);
    if (encrypted.length > 4000000) {
      throw const YacineResolveException('provider_data_too_large');
    }
    final key = utf8.encode(_keyPrefix + stamp);
    final decoded = Uint8List(encrypted.length);
    for (var i = 0; i < encrypted.length; i++) {
      decoded[i] = encrypted[i] ^ key[i % key.length];
    }
    return _localMap(jsonDecode(utf8.decode(decoded)));
  }

  Future<List<YacinePlaybackSource>> resolve(String providerId) async {
    if (!RegExp(r'^\d{1,24}$').hasMatch(providerId)) {
      throw const YacineResolveException('provider_channel_invalid');
    }
    // Fetch current per-channel metadata, just as a two-stage channel/player
    // flow does. A few API 404/5xx responses are temporary during rotation.
    // Never reuse a cached signed media URL to work around an API failure.
    http.Response? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      try {
        response = await client.get(
          Uri.parse(_apiUrl + providerId),
          headers: const {
            'User-Agent': _apiAgent,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 12));
      } on Exception {
        if (attempt == 1) rethrow;
        continue;
      }
      if (response.statusCode == 200 ||
          !yacineRetryableProviderStatus(response.statusCode)) break;
    }
    if (response?.statusCode == 404) {
      // The provider rotates channel IDs along with its category catalog.
      // A 404 must trigger ID re-discovery; retrying the same numeric ID
      // would never produce a playable signed media URL.
      throw const YacineResolveException('provider_api_http_404');
    }
    if (response == null || response.statusCode != 200) {
      throw const YacineResolveException('provider_api_unavailable');
    }
    final raw = _decode(response.bodyBytes, response.headers['t']);
    final rows = yacineDescriptorRows(raw['data']);
    if (rows == null) {
      // Unknown schema is not evidence that the provider has zero streams.
      // Do not loop over quality variants for an unrecognized response.
      throw const YacineResolveException('provider_data_schema_unsupported');
    }
    final found = <YacinePlaybackSource>[];
    var invalidUrls = 0;
    var unsupportedFormats = 0;
    var expiredUrls = 0;
    var protectedSources = 0;
    for (final item in rows.take(15)) {
      final source = _localMap(item);
      if (source.isEmpty) {
        invalidUrls++;
        continue;
      }
      final drm = source['drm'];
      if (yacineDescriptorHasDrm(drm)) {
        protectedSources++;
        continue;
      }

      final url = Uri.tryParse(_localText(source['url']));
      if (url == null || !url.hasAuthority ||
          url.userInfo.isNotEmpty ||
          (url.scheme != 'https' && url.scheme != 'http')) {
        invalidUrls++;
        continue;
      }
      // Support HLS, unprotected DASH, and native direct-media formats.
      if (!_supportedMediaUrl(url, source['url_type'])) {
        unsupportedFormats++;
        continue;
      }
      // Tokens may use seconds or milliseconds. Reject short-lived URLs
      // that have already expired, without persisting them.
      final rawExpiry = int.tryParse(url.queryParameters['e'] ??
          url.queryParameters['expires'] ??
          url.queryParameters['exp'] ?? '');
      final expires = rawExpiry != null && rawExpiry > 9999999999
          ? rawExpiry ~/ 1000 : rawExpiry;
      if (expires != null &&
          expires > 1700000000 &&
          expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 20) {
        expiredUrls++;
        continue;
      }

      // A generic on-device session; player-specific playback is handled later.
      // Desktop EGY TV Sport falls back to this identity when a descriptor
      // has no media User-Agent. Keep API identity and media identity distinct.
      final headers = yacinePlaybackHeaders(
          source, fallbackUserAgent: 'okhttp/4.12.0');
      final quality = _localText(source['name']).isNotEmpty ? _localText(source['name'])
          : _localText(source['quality']).isNotEmpty ? _localText(source['quality'])
          : 'Server ' + (found.length + 1).toString();
      found.add(YacinePlaybackSource(url,
          Map<String, String>.unmodifiable(headers), quality,
          source['url_type'],
          vlcPlaylistHeaders: yacineDesktopVlcHeaders(source, headers)));
    }
    if (found.isEmpty) {
      // Report WHY a successfully fetched descriptor has no playable source.
      // Do not include any signed URLs, cookies, tokens or private headers.
      if (rows.isEmpty) {
        throw const YacineResolveException('provider_stream_unavailable_empty');
      }
      if (protectedSources > 0 && protectedSources >= rows.take(15).length) {
        throw const YacineResolveException('provider_stream_protected');
      }
      if (expiredUrls > 0 &&
          expiredUrls == rows.take(15).length) {
        throw const YacineResolveException('provider_stream_expired');
      }
      if (unsupportedFormats > 0 &&
          unsupportedFormats == rows.take(15).length) {
        throw const YacineResolveException('provider_stream_format_unsupported');
      }
      if (invalidUrls > 0 && invalidUrls == rows.take(15).length) {
        throw const YacineResolveException('provider_stream_invalid_url');
      }
      throw const YacineResolveException('provider_stream_unavailable');
    }
    return found;
  }
}


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

bool _supportedMediaUrl(Uri url, Object? providerMode) {
  final path = url.path.toLowerCase();
  if (const ['.m3u8','.m3u','.mpd','.ts','.mp4','.m4v','.webm',
    '.mkv','.mov','.mpg','.mpeg'].any(path.endsWith)) return true;
  if (path.endsWith('.ism/manifest')) return true;
  return const {'1','3'}.contains(providerMode?.toString());
}

class YacineResolveException implements Exception {
  const YacineResolveException(this.reason);
  final String reason;
  @override
  String toString() => 'YacineResolveException($reason)';
}

class YacinePlaybackSource {
  const YacinePlaybackSource(this.uri, this.headers, this.label, this.providerMode);
  final Uri uri;
  final Map<String, String> headers;
  final String label;
  final Object? providerMode;
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
    if (response == null || response.statusCode != 200) {
      throw const YacineResolveException('provider_api_unavailable');
    }
    final raw = _decode(response.bodyBytes, response.headers['t']);
    final rows = _localList(raw['data']);
    final found = <YacinePlaybackSource>[];
    for (final item in rows.take(15)) {
      final source = _localMap(item);
      if (source.isEmpty) continue;
      final drm = source['drm'];
      if (yacineDescriptorHasDrm(drm)) continue;

      final url = Uri.tryParse(_localText(source['url']));
      if (url == null || !url.hasAuthority ||
          url.userInfo.isNotEmpty ||
          (url.scheme != 'https' && url.scheme != 'http')) continue;
      // Support HLS, unprotected DASH, and native direct-media formats.
      if (!_supportedMediaUrl(url, source['url_type'])) continue;
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
          source['url_type']));
    }
    if (found.isEmpty) throw const YacineResolveException('provider_stream_unavailable');
    return found;
  }
}


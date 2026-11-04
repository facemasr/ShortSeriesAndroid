import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Small, bounded checks adapted from the user's read-only collector.
/// A working playlist is not proof that the media segments can be fetched.
enum YacineMediaStatus { segmentReachable, manifestOnly }

class YacineProbeFailure implements Exception {
  const YacineProbeFailure(this.code);
  final String code;
  @override
  String toString() => 'YacineProbeFailure($code)';
}

class YacineHlsInspection {
  const YacineHlsInspection({this.variant, this.segment, this.encrypted = false});
  final Uri? variant;
  final Uri? segment;
  final bool encrypted;
}

/// Extract only media/variant references from HLS. Never request decryption
/// keys or treat an encrypted HLS playlist as an unprotected source.
YacineHlsInspection inspectYacineHls(String text, Uri base) {
  if (!text.trimLeft().startsWith('#EXTM3U')) {
    throw const YacineProbeFailure('not_hls_manifest');
  }
  final lines = const LineSplitter().convert(text).map((s) => s.trim()).toList();
  for (final line in lines) {
    if (line.startsWith('#EXT-X-KEY:') &&
        !RegExp(r'\bMETHOD=NONE(?:,|$)').hasMatch(line)) {
      return const YacineHlsInspection(encrypted: true);
    }
  }
  Uri? resolve(String value) {
    try {
      final uri = base.resolve(value);
      if (!const {'https', 'http'}.contains(uri.scheme) ||
          uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
      return uri;
    } catch (_) {
      return null;
    }
  }

  // Master playlist: choose a real variant, not a master URL in a tight loop.
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    for (var j = i + 1; j < lines.length; j++) {
      final value = lines[j];
      if (value.isEmpty) continue;
      if (value.startsWith('#')) break;
      return YacineHlsInspection(variant: resolve(value));
    }
  }
  // Media playlist: follow only an actual segment after #EXTINF.
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXTINF')) continue;
    for (var j = i + 1; j < lines.length; j++) {
      final value = lines[j];
      if (value.isEmpty) continue;
      if (value.startsWith('#')) break;
      return YacineHlsInspection(segment: resolve(value));
    }
  }
  return const YacineHlsInspection();
}

class _SmallMediaResponse {
  const _SmallMediaResponse(this.bytes, this.uri, this.contentType);
  final Uint8List bytes;
  final Uri uri;
  final String contentType;

  String get text => utf8.decode(bytes, allowMalformed: true).trimLeft();
}

class YacineMediaProbe {
  const YacineMediaProbe(this.client);
  final http.Client client;

  static bool _valid(Uri uri) =>
      const {'https', 'http'}.contains(uri.scheme) &&
      uri.hasAuthority && uri.userInfo.isEmpty;

  Future<_SmallMediaResponse> _readSmall(
    Uri initial,
    Map<String, String> headers, {
    required int maxBytes,
    bool mediaPart = false,
  }) async {
    var uri = initial;
    for (var redirect = 0; redirect < 4; redirect++) {
      if (!_valid(uri)) throw const YacineProbeFailure('invalid_media_url');
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (mediaPart) request.headers['Range'] = 'bytes=0-1023';
      final response = await client.send(request)
          .timeout(const Duration(seconds: 7));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null || location.isEmpty) {
          throw const YacineProbeFailure('redirect_without_location');
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.drain<void>();
        throw YacineProbeFailure('source_http_${response.statusCode}');
      }
      final buffer = BytesBuilder(copy: false);
      await for (final bytes in response.stream) {
        if (buffer.length >= maxBytes) break;
        buffer.add(bytes.length > maxBytes - buffer.length
            ? bytes.sublist(0, maxBytes - buffer.length) : bytes);
        if (buffer.length >= maxBytes) break;
      }
      return _SmallMediaResponse(
        buffer.takeBytes(), uri, response.headers['content-type'] ?? '',
      );
    }
    throw const YacineProbeFailure('too_many_redirects');
  }

  Future<YacineMediaStatus> verifyHls(
    Uri url,
    Map<String, String> headers,
  ) async {
    return _verifyHls(url, headers).timeout(
      const Duration(seconds: 14),
      onTimeout: () => throw const YacineProbeFailure('source_timeout'),
    );
  }

  Future<YacineMediaStatus> _verifyHls(
    Uri url,
    Map<String, String> headers,
  ) async {
    var current = url;
    // One master plus up to two nested variants.
    for (var depth = 0; depth < 3; depth++) {
      final response = await _readSmall(
        current, headers, maxBytes: 65536);
      if (response.contentType.toLowerCase().contains('text/html') ||
          response.contentType.toLowerCase().contains('application/json')) {
        throw const YacineProbeFailure('not_media_response');
      }
      final data = response.text;
      if (data.startsWith('<!DOCTYPE') || data.startsWith('<html')) {
        throw const YacineProbeFailure('not_media_response');
      }
      final parsed = inspectYacineHls(data, response.uri);
      if (parsed.encrypted) {
        throw const YacineProbeFailure('encrypted_stream');
      }
      if (parsed.variant != null) {
        current = parsed.variant!;
        continue;
      }
      if (parsed.segment == null) return YacineMediaStatus.manifestOnly;
      final segment = await _readSmall(
        parsed.segment!, headers, maxBytes: 1024, mediaPart: true);
      final bytes = segment.bytes;
      if (bytes.isEmpty) {
        throw const YacineProbeFailure('empty_segment');
      }
      final sample = segment.text.toLowerCase();
      if (sample.startsWith('<html') || sample.startsWith('<!doctype') ||
          segment.contentType.toLowerCase().startsWith('image/')) {
        throw const YacineProbeFailure('not_media_segment');
      }
      return YacineMediaStatus.segmentReachable;
    }
    throw const YacineProbeFailure('playlist_depth_exceeded');
  }
}

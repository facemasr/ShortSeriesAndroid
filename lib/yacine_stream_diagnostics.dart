import 'dart:async';
import 'package:http/http.dart' as http;
import 'yacine_channel_resolver.dart';

/// A small, optional HTTP-header check, not a playback proxy. Used only
/// after an explicit diagnostic request or a native VLC failure. No signed
/// URLs, access tokens or Referer values are logged or displayed.
class YacineManifestDiagnostic {
  const YacineManifestDiagnostic(this.httpStatus, this.reason);
  final int? httpStatus;
  final String reason;
  bool get accepted => httpStatus == 200 || httpStatus == 206;
  bool get denied => httpStatus == 401 || httpStatus == 403;
}

/// Fetch response HEADERS only and immediately close the HTTP stream.
/// Never download whole HLS segments, video files or DRM license data.
Future<YacineManifestDiagnostic> checkYacineManifest(
  http.Client client, YacinePlaybackSource source,
) async {
  final request = http.Request('GET', source.uri)
    ..followRedirects = true
    ..maxRedirects = 3;
  request.headers.addAll(source.headers);
  // Match the desktop playlist GET: some live HLS servers reject Range
  // requests even when the same manifest plays with HTTP 200. An incorrect
  // 403 probe would permanently stop VLC recovery.
  final isHls = source.uri.path.toLowerCase().endsWith('.m3u8') ||
      source.providerMode?.toString() == '3';
  if (!isHls) request.headers['Range'] = 'bytes=0-1023';
  try {
    final result = await client.send(request)
        .timeout(const Duration(seconds: 9));
    await result.stream.listen((_) {}).cancel();
    switch (result.statusCode) {
      case 200:
      case 206:
        return YacineManifestDiagnostic(result.statusCode, 'http_accepted');
      case 401:
        return const YacineManifestDiagnostic(401, 'authorization_required');
      case 403:
        return const YacineManifestDiagnostic(403, 'source_denied');
      case 404:
        return const YacineManifestDiagnostic(404, 'source_not_found');
      default:
        return YacineManifestDiagnostic(result.statusCode, 'source_http_error');
    }
  } on TimeoutException {
    return const YacineManifestDiagnostic(null, 'connection_timeout');
  } catch (_) {
    return const YacineManifestDiagnostic(null, 'network_error');
  }
}

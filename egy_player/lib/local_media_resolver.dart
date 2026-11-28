import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

bool isFirstPartyPage(Uri uri) =>
    uri.scheme == 'https' && uri.host == 'egyshow.com' &&
    uri.port == 443 && uri.userInfo.isEmpty && !uri.hasFragment;

class DeclaredVideoSource {
  const DeclaredVideoSource(this.uri, this.format);
  final Uri uri;
  final VideoFormat? format;
}

VideoFormat? declaredFormat(Uri uri, String mime) {
  final path = uri.path.toLowerCase();
  final type = mime.split(';').first.trim().toLowerCase();
  if (path.endsWith('.m3u8') || type.contains('mpegurl')) return VideoFormat.hls;
  if (path.endsWith('.mpd') || type == 'application/dash+xml') return VideoFormat.dash;
  if (type.startsWith('video/') ||
      const ['.mp4', '.webm', '.m4v', '.mkv', '.mov'].any((ext) => path.endsWith(ext))) {
    return VideoFormat.other;
  }
  return null;
}

// Parse only explicitly declared video sources on first-party pages.
// No script execution, iframe traversal, cookies, or authentication bypass.
List<DeclaredVideoSource> declaredVideoSources(Uri page, String markup) {
  if (!isFirstPartyPage(page)) return [];
  final result = <DeclaredVideoSource>[];
  final seen = <Uri>{};
  for (final element in html.parse(markup).querySelectorAll('video[src], video source[src]')) {
    final value = element.attributes['src']?.trim() ?? '';
    if (value.isEmpty) continue;
    final relative = Uri.tryParse(value);
    if (relative == null) continue;
    final uri = page.resolveUri(relative);
    if (!isFirstPartyPage(uri) || !seen.add(uri)) continue;
    final format = declaredFormat(uri, element.attributes['type'] ?? '');
    if (format != null) result.add(DeclaredVideoSource(uri, format));
  }
  return result;
}

Future<List<DeclaredVideoSource>> readDeclaredVideoSources(http.Client client, Uri page) async {
  if (!isFirstPartyPage(page)) return [];
  final request = http.Request('GET', page)
    ..followRedirects = false
    ..headers['Accept'] = 'text/html';
  final response = await client.send(request).timeout(const Duration(seconds: 8));
  final type = (response.headers['content-type'] ?? '').toLowerCase();
  const limit = 256 * 1024;
  if (response.statusCode != 200 || !type.startsWith('text/html') ||
      (response.contentLength ?? 0) > limit) {
    final sub = response.stream.listen((_) {});
    await sub.cancel();
    return [];
  }
  final bytes = <int>[];
  await for (final chunk in response.stream.timeout(const Duration(seconds: 5))) {
    if (bytes.length + chunk.length > limit) return [];
    bytes.addAll(chunk);
  }
  return declaredVideoSources(page, utf8.decode(bytes, allowMalformed: true));
}

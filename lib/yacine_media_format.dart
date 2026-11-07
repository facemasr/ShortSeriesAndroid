import 'package:video_player/video_player.dart';

/// Select Android's native media engine format from provider metadata and
/// the actual media URL. No protected-DRM license handling is added here.
VideoFormat? yacineMediaFormat(Uri uri, {Object? providerMode}) {
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return VideoFormat.hls;
  if (path.endsWith('.mpd')) return VideoFormat.dash;
  if (path.endsWith('.ism/manifest')) return VideoFormat.ss;
  if (const ['.ts','.mp4','.m4v','.webm','.mkv','.mov',
    '.mpg','.mpeg'].any(path.endsWith)) return VideoFormat.other;
  if (providerMode?.toString() == '3') return VideoFormat.hls;
  return null;
}

bool yacineIsMediaSource(Uri uri, {Object? providerMode}) {
  final path = uri.path.toLowerCase();
  if (const ['.m3u8','.m3u','.mpd','.ts','.mp4','.m4v','.webm',
    '.mkv','.mov','.mpg','.mpeg'].any(path.endsWith)) return true;
  if (path.endsWith('.ism/manifest')) return true;
  // Legacy no-extension URLs use the explicit provider mode.
  return const {'1','3'}.contains(providerMode?.toString());
}

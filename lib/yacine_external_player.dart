import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

import 'yacine_channel_resolver.dart';

/// Open a freshly resolved authorized channel in an external Android player.
/// This starts an Android ACTION_VIEW intent; it does not download media,
/// bypass access checks or claim to control the target player's decoding.
/// External players may ignore optional source User-Agent/Referer extras.
enum YacineExternalTarget { choose, vlc }

class YacineExternalPlayer {
  const YacineExternalPlayer._();

  static const String vlcPackage = 'org.videolan.vlc';

  static bool isExternalCompatible(YacinePlaybackSource source) {
    // Do not export provider session credentials to arbitrary external apps.
    return !const {'Cookie', 'Authorization', 'X-Auth-Token'}
        .any(source.headers.containsKey);
  }

  static String mediaMimeType(YacinePlaybackSource source) {
    final path = source.uri.path.toLowerCase();
    if (path.endsWith('.m3u8') || source.providerMode?.toString() == '3') {
      return 'application/vnd.apple.mpegurl';
    }
    if (path.endsWith('.mpd')) return 'application/dash+xml';
    return 'video/*';
  }

  static Future<void> open(
    YacinePlaybackSource source, {
    required String title,
    required YacineExternalTarget target,
    required String chooserTitle,
  }) async {
    if (!Platform.isAndroid) {
      throw const YacineExternalPlaybackException('android_only');
    }
    if (!isExternalCompatible(source)) {
      throw const YacineExternalPlaybackException(
          'session_headers_require_internal_player');
    }
    if (!const {'https', 'http'}.contains(source.uri.scheme) ||
        !source.uri.hasAuthority || source.uri.userInfo.isNotEmpty) {
      throw const YacineExternalPlaybackException('invalid_media_url');
    }

    // ACTION_VIEW with a proper media MIME type permits installed players to
    // appear in Android's native chooser rather than opening a web browser.
    // There is no standard Android mechanism that obliges an external app to
    // use HTTP options. Well-behaved apps may inspect these optional extras,
    // but a stream requiring them is not guaranteed to play in every app.
    final userAgent = source.headers['User-Agent'];
    final referrer = source.headers['Referer'];
    final intent = AndroidIntent(
      action: 'android.intent.action.VIEW',
      data: source.uri.toString(),
      type: mediaMimeType(source),
      package: target == YacineExternalTarget.vlc ? vlcPackage : null,
      arguments: <String, dynamic>{
        'title': title,
        'android.intent.extra.TITLE': title,
        if (userAgent != null && userAgent.isNotEmpty)
          'http-user-agent': userAgent,
        if (referrer != null && referrer.isNotEmpty)
          'http-referrer': referrer,
      },
    );
    try {
      if (target == YacineExternalTarget.vlc) {
        await intent.launch();
      } else {
        await intent.launchChooser(chooserTitle);
      }
    } catch (_) {
      throw const YacineExternalPlaybackException('no_external_player');
    }
  }
}

class YacineExternalPlaybackException implements Exception {
  const YacineExternalPlaybackException(this.reason);
  final String reason;
}

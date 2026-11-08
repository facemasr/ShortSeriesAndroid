import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// User-entered video links, analogous to the local URL editor in YTV Player.
/// Provider-resolved signed URLs are NEVER persisted by this service.
class YtvManualLink {
  const YtvManualLink({
    required this.url,
    this.userAgent = '',
    this.referer = '',
  });

  final Uri url;
  final String userAgent;
  final String referer;

  Map<String, String> get headers => {
    if (userAgent.isNotEmpty) 'User-Agent': userAgent,
    if (referer.isNotEmpty) 'Referer': referer,
  };

  static YtvManualLink parse(String input, {
    String userAgent = '',
    String referer = '',
  }) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    if (trimmed.length > 4096 || uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        !uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('invalid_video_url');
    }
    final agent = _cleanHeader(userAgent);
    final ref = _cleanHeader(referer);
    if (ref.isNotEmpty) {
      final refUri = Uri.tryParse(ref);
      if (refUri == null ||
          !const {'http', 'https'}.contains(refUri.scheme.toLowerCase()) ||
          !refUri.hasAuthority) {
        throw const FormatException('invalid_referer');
      }
    }
    return YtvManualLink(url: uri, userAgent: agent, referer: ref);
  }

  static String _cleanHeader(String raw) {
    final text = raw.trim();
    if (text.length > 1024 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      throw const FormatException('invalid_media_header');
    }
    return text;
  }

  /// Temporary URLs with tokens, credentials or explicit expiry should never
  /// be copied to SharedPreferences. They may still be used in the foreground.
  bool get mayPersist {
    if (url.userInfo.isNotEmpty || url.hasFragment) return false;
    const sensitive = {
      'e', 'exp', 'expires', 'expiry', 'token', 'sig', 'signature', 'key',
      'auth', 'authorization', 'access_token', 'jwt', 'session', 'policy',
      'hdnts', 'hmac', 'hash', 'st', 'end', 'start',
    };
    return !url.queryParameters.keys.any(
        (k) => sensitive.contains(k.toLowerCase()));
  }

  String toJson() => jsonEncode({
    'url': url.toString(), 'userAgent': userAgent, 'referer': referer,
  });

  static YtvManualLink fromJson(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map) throw const FormatException('invalid_manual_link');
    return parse(value['url']?.toString() ?? '',
      userAgent: value['userAgent']?.toString() ?? '',
      referer: value['referer']?.toString() ?? '',
    );
  }
}

class YtvManualLinkStore {
  const YtvManualLinkStore._();
  static const _prefix = 'egytvpro_user_ytv_v1_';

  static String _key(String providerId) =>
      _prefix + Uri.encodeComponent(providerId);

  static Future<YtvManualLink?> load(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(providerId));
    if (raw == null) return null;
    try {
      final saved = YtvManualLink.fromJson(raw);
      if (saved.mayPersist) return saved;
    } catch (_) {
      // Ignore and remove legacy or corrupted persisted values.
    }
    await prefs.remove(_key(providerId));
    return null;
  }

  static Future<void> save(String providerId, YtvManualLink link) async {
    if (!link.mayPersist) {
      throw const FormatException('temporary_url_not_persisted');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(providerId), link.toJson());
  }

  static Future<void> remove(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(providerId));
  }
}

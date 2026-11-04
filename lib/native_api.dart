import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

const origin = 'https://egyshow.com';
Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> asList(dynamic v) => v is List ? v : <dynamic>[];
String txt(dynamic v) => v?.toString() ?? '';
int numId(dynamic v) => v is num ? v.toInt() : int.tryParse(txt(v)) ?? 0;

class Media {
  Media(this.raw);
  final Map<String, dynamic> raw;
  int get id => numId(raw['id']);
  String get type => txt(raw['media_type']).isEmpty ? 'movie' : txt(raw['media_type']);
  String title(bool ar) {
    final first = txt(raw[ar ? 'title_ar' : 'title_en']).trim();
    return first.isNotEmpty ? first : txt(raw['title_ar']).isNotEmpty
        ? txt(raw['title_ar']) : txt(raw['title_en']);
  }
  String overview(bool ar) {
    final first = txt(raw[ar ? 'overview_ar' : 'overview_en']).trim();
    return first.isNotEmpty ? first : txt(raw['overview_ar']);
  }
  String get poster => txt(raw['poster_path']);
  String get backdrop => txt(raw['backdrop_path']).isNotEmpty ? txt(raw['backdrop_path']) : poster;
  String get year => txt(raw['release_year']);
  String get rating => txt(raw['vote_average']);
  List<Episode> get episodes => asList(raw['episodes']).map((e) => Episode(asMap(e))).where((e) => e.id > 0).toList();
  List<Map<String, dynamic>> get seasons => asList(raw['seasons']).map(asMap).toList();
  String get key => type + ':' + id.toString();
  bool get isSeries => type == 'series' || type == 'short_series';
}

class Episode {
  Episode(this.raw);
  final Map<String, dynamic> raw;
  int get id => numId(raw['id']);
  int get number => numId(raw['episode_number']);
  int get season => numId(raw['season_number']);
  String get image => txt(raw['still_path']);
  String title(bool ar) {
    final first = txt(raw[ar ? 'title_ar' : 'title_en']).trim();
    return first.isNotEmpty ? first : (ar ? 'الحلقة ' : 'Episode ') + number.toString();
  }
}

class LiveChannel {
  LiveChannel(this.raw);
  final Map<String, dynamic> raw;
  int get id => numId(raw['id']);
  String get providerId => txt(raw['provider_id']);
  String get group => txt(raw['category']).isNotEmpty
      ? txt(raw['category']) : txt(raw['package_name']);
  String get logo => txt(raw['logo_url']);
  String title(bool ar) {
    final first = txt(raw[ar ? 'title_ar' : 'title_en']).trim();
    if (first.isNotEmpty) return first;
    final original = txt(raw[ar ? 'name_ar' : 'name_en']).trim();
    if (original.isNotEmpty) return original;
    return txt(raw['title_ar']).isNotEmpty ? txt(raw['title_ar'])
        : txt(raw['name_ar']);
  }
}

class ApiException implements Exception {
  const ApiException(this.message, [this.code = 0]);
  final String message;
  final int code;
  @override
  String toString() => message;
}

class EgyApi {
  EgyApi() : client = http.Client();
  final http.Client client;
  String? token;

  Future<Map<String, dynamic>> call(String path, {String method = 'GET',
    Map<String, dynamic>? data, bool authenticated = false}) async {
    final headers = <String, String>{'Accept': 'application/json',
      'Content-Type': 'application/json', 'X-Client': 'EGYSHOW-Mobile-Native'};
    if ((authenticated || token != null) && token != null) {
      headers['Authorization'] = 'Bearer ' + token!;
    }
    final uri = Uri.parse(origin + path);
    http.Response response;
    try {
      response = await (method == 'POST'
          ? client.post(uri, headers: headers, body: jsonEncode(data ?? {}))
          : method == 'DELETE' ? client.delete(uri, headers: headers)
          : client.get(uri, headers: headers))
          .timeout(const Duration(seconds: 35));
    } on TimeoutException {
      throw const ApiException('انتهت مهلة الاتصال / Connection timed out');
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالموقع / Network unavailable');
    }
    Map<String, dynamic> result;
    try {
      result = asMap(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      throw ApiException('استجابة غير صالحة (' + response.statusCode.toString() + ')', response.statusCode);
    }
    if (response.statusCode >= 400 || result['ok'] == false) {
      throw ApiException(txt(result['error']).isNotEmpty
          ? txt(result['error']) : txt(result['message']).isNotEmpty
              ? txt(result['message']) : 'HTTP ' + response.statusCode.toString(),
          response.statusCode);
    }
    return result;
  }
  Future<Map<String, List<Media>>> home() async {
    final json = await call('/api/v1/home');
    return {for (final key in ['featured', 'trending', 'latest'])
      key: asList(json[key]).map((e) => Media(asMap(e))).toList()};
  }
  Future<List<Media>> catalog(String type, {int page = 1}) async {
    final response = await call('/api/v1/media?type=' + Uri.encodeQueryComponent(type) +
        '&page=' + page.toString() + '&limit=24');
    return asList(response['items']).map((v) => Media(asMap(v))).toList();
  }
  Future<List<Media>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await call('/api/v1/search?q=' + Uri.encodeQueryComponent(query.trim()) + '&limit=40');
    return asList(response['items']).map((v) => Media(asMap(v))).toList();
  }
  Future<Media> details(int id) async =>
      Media(asMap((await call('/api/v1/media/' + id.toString()))['media']));
  Future<List<LiveChannel>> live({int page = 1}) async {
    // Live TV metadata comes from the provider on this Android device,
    // not from the EGYSHOW website or a cached server-side channel map.
    // Fresh signed stream URLs are resolved separately on channel open.
    return _YacineDirectCatalog(client).load();
  }
  Future<Map<String, dynamic>> playerContext(String type, int id) =>
      call('/api/v1/player/context?target_type=' + type + '&target_id=' + id.toString());
  Future<Map<String, dynamic>> lease(Map<String, dynamic> source, {bool bypassCache = false, bool forceRelay = false}) =>
      call('/api/v1/player/source/' + numId(source['id']).toString() + '/lease',
        method: 'POST', data: {
          'target_type': txt(source['target_type']),
          'target_id': numId(source['target_id']),
          'allow_failover': true, 'force_relay': forceRelay, 'bypass_cache': bypassCache,
        });
  Future<Map<String, dynamic>> refreshLease(String id) =>
      call('/api/v1/player/lease/' + Uri.encodeComponent(id) + '/refresh',
          method: 'POST', data: {});
  Future<Map<String, dynamic>> authenticate(String email, String password,
      {String? displayName, String language = 'ar'}) =>
      call('/api/v1/auth/' + (displayName == null ? 'login' : 'register'),
        method: 'POST', data: {'email': email.trim(), 'password': password,
          if (displayName != null) 'display_name': displayName,
          'preferred_language': language});
  Future<Map<String, dynamic>> profile() => call('/api/v1/profile', authenticated: true);
  Future<void> setServerFavorite(int id, bool enabled) async {
    await call('/api/v1/profile/favorites/' + id.toString(),
        method: 'POST', authenticated: true, data: {'enabled': enabled});
  }
  void dispose() => client.close();
}

/// Direct catalog client. Only movie/series/auth/ads/update APIs use EGYSHOW.
/// Live channel categories, IDs and stream resolution never use EGYSHOW.
class _YacineDirectCatalog {
  _YacineDirectCatalog(this.client);
  final http.Client client;

  DateTime _nextApiRequest = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _paceApi() async {
    // Match the supplied collector's conservative catalog request rate.
    final remaining = _nextApiRequest.difference(DateTime.now());
    if (remaining > Duration.zero) await Future.delayed(remaining);
    _nextApiRequest = DateTime.now().add(const Duration(milliseconds: 250));
  }
  static const _base = 'https://def001.ycnapi.com/api/';
  static const _agent = 'okhttp/4.12.0';
  static const _prefix = 'c!xZj+N9&G@Ev@vw';

  List<dynamic> _decode(http.Response response) {
    if (response.bodyBytes.length > 4000000) {
      throw const ApiException('provider_catalog_too_large');
    }
    try {
      final input = utf8.decode(response.bodyBytes).trim();
      Map<String, dynamic> value;
      if (input.startsWith('{')) {
        value = asMap(jsonDecode(input));
      } else {
        final stamp = response.headers['t'] ?? '';
        if (!RegExp(r'^\d{1,16}$').hasMatch(stamp)) {
          throw const FormatException('missing timestamp');
        }
        final encrypted = base64Decode(input);
        if (encrypted.isEmpty || encrypted.length > 4000000) {
          throw const FormatException('invalid payload size');
        }
        final key = utf8.encode(_prefix + stamp);
        for (var i = 0; i < encrypted.length; i++) {
          encrypted[i] ^= key[i % key.length];
        }
        value = asMap(jsonDecode(utf8.decode(encrypted)));
      }
      if (value['data'] is! List) {
        throw const FormatException('missing data');
      }
      return asList(value['data']);
    } catch (_) {
      throw const ApiException('provider_catalog_response_invalid');
    }
  }

  Future<List<dynamic>> _request(String route) async {
    if (!RegExp(r'^categories(?:/\d+(?:/channels)?)?$').hasMatch(route)) {
      throw const ApiException('provider_route_invalid');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      await _paceApi();
      try {
        final response = await client.get(Uri.parse(_base + route),
          headers: const {
            'User-Agent': _agent,
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          }).timeout(const Duration(seconds: 18));
        if (response.statusCode == 200) return _decode(response);
        final retryable = response.statusCode == 429 ||
            response.statusCode >= 500;
        if (!retryable || attempt == 1) {
          throw ApiException(
            'provider_catalog_http_' + response.statusCode.toString(),
            response.statusCode,
          );
        }
      } on ApiException {
        rethrow;
      } on TimeoutException {
        if (attempt == 1) {
          throw const ApiException('provider_catalog_timeout');
        }
      } catch (_) {
        if (attempt == 1) {
          throw const ApiException('provider_catalog_network_unavailable');
        }
      }
      await Future.delayed(const Duration(milliseconds: 700));
    }
    throw const ApiException('provider_catalog_network_unavailable');
  }

  int _stableId(String providerId, Set<int> taken) {
    var id = int.tryParse(providerId);
    if (id == null || id < 1 || id > 9223372036854775807) {
      id = 17;
      for (final unit in providerId.codeUnits) {
        id = ((id! * 131) + unit) & 0x7fffffff;
      }
      if (id == 0) id = 1;
    }
    while (!taken.add(id!)) {
      id = (id + 1) & 0x7fffffff;
      if (id == 0) id = 1;
    }
    return id;
  }

  Future<List<LiveChannel>> load() async {
    final top = await _request('categories');
    final queue = <Map<String, dynamic>>[];
    for (final item in top) {
      final row = asMap(item);
      queue.add({'item': row, 'path': txt(row['name']).trim()});
    }
    final visited = <String>{}, seenChannels = <String>{};
    final takenIds = <int>{};
    final channels = <LiveChannel>[];
    var head = 0;
    while (head < queue.length) {
      if (head >= 160) {
        throw const ApiException('provider_category_limit');
      }
      final current = queue[head++];
      final item = asMap(current['item']);
      final providerCategoryId = txt(item['id']);
      if (!RegExp(r'^\d{1,24}$').hasMatch(providerCategoryId) ||
          !visited.add(providerCategoryId)) continue;
      final group = txt(current['path']);
      if (numId(item['child_count']) > 0) {
        final children = await _request('categories/' + providerCategoryId);
        for (final child in children) {
          final row = asMap(child);
          final title = txt(row['name']).trim();
          queue.add({'item': row,
            'path': group.isEmpty ? title : group + ' / ' + title});
        }
        continue;
      }
      final rows = await _request('categories/' + providerCategoryId + '/channels');
      for (final entry in rows) {
        final channel = asMap(entry);
        final id = txt(channel['id']);
        final name = txt(channel['name']).trim();
        if (!RegExp(r'^\d{1,24}$').hasMatch(id) ||
            name.isEmpty || !seenChannels.add(id)) continue;
        final logo = Uri.tryParse(txt(channel['logo']));
        final safeLogo = logo != null &&
            (logo.scheme == 'https' || logo.scheme == 'http') &&
            logo.hasAuthority && logo.userInfo.isEmpty
            ? logo.toString() : '';
        channels.add(LiveChannel({
          'id': _stableId(id, takenIds),
          'provider_id': id,
          'name_ar': name,
          'name_en': name,
          'package_name': group,
          'logo_url': safeLogo,
        }));
        if (channels.length >= 2500) {
          throw const ApiException('provider_channel_limit');
        }
      }
    }
    if (channels.length < 25) {
      throw const ApiException('provider_catalog_incomplete');
    }
    return channels;
  }
}

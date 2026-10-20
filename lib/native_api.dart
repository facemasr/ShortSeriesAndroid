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
  String get logo => txt(raw['logo_url']);
  String title(bool ar) => txt(raw[ar ? 'name_ar' : 'name_en']).isNotEmpty
      ? txt(raw[ar ? 'name_ar' : 'name_en']) : txt(raw['name_ar']);
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
    final json = await call('/api/v1/live?page=' + page.toString() + '&limit=24');
    return asList(json['channels']).map((v) => LiveChannel(asMap(v))).toList();
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

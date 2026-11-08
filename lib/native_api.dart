import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// Standalone provider client. Never requests EGYSHOW website APIs.
Map<String, dynamic> asMap(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};
List<dynamic> asList(dynamic value) =>
    value is List ? value : <dynamic>[];
String txt(dynamic value) => value?.toString() ?? '';
int numId(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(txt(value)) ?? 0;

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
    return txt(raw['title_ar']).isNotEmpty
        ? txt(raw['title_ar']) : txt(raw['name_ar']);
  }
}

class ApiException implements Exception {
  const ApiException(this.message, [this.code = 0]);
  final String message;
  final int code;
  @override
  String toString() => message;
}

/// Catalog metadata, current channel IDs and quality variants. Per-channel
/// media URLs and provider headers are resolved separately on the device.
class EgyApi {
  EgyApi({http.Client? httpClient}) : client = httpClient ?? http.Client();
  final http.Client client;

  Future<List<LiveChannel>> live({int page = 1}) =>
      _YacineDirectCatalog(client).load();

  Future<LiveChannel?> refreshProviderChannel(LiveChannel stale) =>
      _YacineDirectCatalog(client).refreshOne(stale);

  Future<List<LiveChannel>> refreshLiveQualityVariants(LiveChannel stale) =>
      _YacineDirectCatalog(client).refreshQualityVariants(stale);

  void dispose() => client.close();
}

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

  /// Recover a rotated provider ID without guessing another TV station.
  /// The live catalog encodes nested packages as "Parent / Child", so
  /// searching only top-level categories silently fails for nested channels.
  /// Resolve the exact category path and exact original station name.
  Future<LiveChannel?> refreshOne(LiveChannel stale) async {
    final path = stale.group.split(' / ')
        .map((segment) => segment.trim().toLowerCase())
        .where((segment) => segment.isNotEmpty).toList();
    final stationName = stale.title(false).trim().toLowerCase();
    if (path.isEmpty || stationName.isEmpty) return null;

    var categories = await _request('categories');
    Map<String, dynamic>? selected;
    for (var level = 0; level < path.length; level++) {
      selected = null;
      for (final entry in categories) {
        final item = asMap(entry);
        if (txt(item['name']).trim().toLowerCase() == path[level]) {
          selected = item;
          break;
        }
      }
      if (selected == null) return null;
      final categoryId = txt(selected['id']);
      if (!RegExp(r'^\d{1,24}$').hasMatch(categoryId)) return null;
      if (level < path.length - 1) {
        if (numId(selected['child_count']) <= 0) return null;
        categories = await _request('categories/' + categoryId);
      }
    }
    if (selected == null || numId(selected['child_count']) > 0) return null;

    final selectedId = txt(selected['id']);
    final channels = await _request('categories/' + selectedId + '/channels');
    for (final entry in channels) {
      final row = asMap(entry);
      if (txt(row['name']).trim().toLowerCase() != stationName) continue;
      final providerId = txt(row['id']);
      if (!RegExp(r'^\d{1,24}$').hasMatch(providerId)) continue;
      final logo = Uri.tryParse(txt(row['logo']));
      final safeLogo = logo != null &&
          const {'https', 'http'}.contains(logo.scheme) &&
          logo.hasAuthority && logo.userInfo.isEmpty ? logo.toString() : '';
      return LiveChannel(<String, dynamic>{
        'id': _stableId(providerId, <int>{}),
        'provider_id': providerId,
        'name_ar': txt(row['name']).trim(),
        'name_en': txt(row['name']).trim(),
        'package_name': stale.group,
        'logo_url': safeLogo,
      });
    }
    return null;
  }

  static final RegExp _qualitySuffix = RegExp(
    r'\s*(?:\(\s*|\[\s*)?(?:2160|1440|1080|720|576|480|360|320|288|270|244|240|144)\s*p?\s*(?:\)|\])?\s*$'
    r'|\s*(?:\(\s*|\[\s*)?(?:4k|uhd|fhd|full[\s_-]*hd|hd|sd)\s*(?:\)|\])?\s*$',
    caseSensitive: false,
  );

  static String _baseQualityPackage(String name) =>
      name.replaceAll(_qualitySuffix, '').trim().toLowerCase();

  /// Find the exact station in the CURRENT provider's sibling quality
  /// categories, without using stale IDs or querying other stations' media.
  Future<List<LiveChannel>> refreshQualityVariants(LiveChannel stale) async {
    final parts = stale.group.split(' / ').map((v) => v.trim())
        .where((v) => v.isNotEmpty).toList();
    final stationName = stale.title(false).trim().toLowerCase();
    if (parts.isEmpty || stationName.isEmpty) return <LiveChannel>[];

    var categories = await _request('categories');
    var prefix = '';
    for (final part in parts.take(parts.length - 1)) {
      Map<String, dynamic>? parent;
      for (final row in categories) {
        final current = asMap(row);
        if (txt(current['name']).trim().toLowerCase() ==
            part.toLowerCase()) {
          parent = current;
          break;
        }
      }
      if (parent == null || numId(parent['child_count']) <= 0) {
        return <LiveChannel>[];
      }
      final parentId = txt(parent['id']);
      if (!RegExp(r'^\d{1,24}$').hasMatch(parentId)) {
        return <LiveChannel>[];
      }
      categories = await _request('categories/' + parentId);
      prefix = prefix.isEmpty ? part : prefix + ' / ' + part;
    }

    final wanted = _baseQualityPackage(parts.last);
    final candidateGroups = <Map<String, dynamic>>[];
    for (final row in categories) {
      final group = asMap(row);
      final id = txt(group['id']);
      if (numId(group['child_count']) > 0 ||
          !RegExp(r'^\d{1,24}$').hasMatch(id) ||
          _baseQualityPackage(txt(group['name'])) != wanted) {
        continue;
      }
      candidateGroups.add(group);
    }
    if (candidateGroups.length > 8) {
      throw const ApiException('provider_quality_category_limit');
    }

    final results = <LiveChannel>[];
    final seen = <String>{};
    final taken = <int>{};
    for (final group in candidateGroups) {
      final id = txt(group['id']);
      final name = txt(group['name']).trim();
      final path = prefix.isEmpty ? name : prefix + ' / ' + name;
      final rows = await _request('categories/' + id + '/channels');
      for (final entry in rows) {
        final row = asMap(entry);
        if (txt(row['name']).trim().toLowerCase() != stationName) {
          continue;
        }
        final providerId = txt(row['id']);
        if (!RegExp(r'^\d{1,24}$').hasMatch(providerId) ||
            !seen.add(providerId)) continue;
        final logo = Uri.tryParse(txt(row['logo']));
        final safeLogo = logo != null &&
            (logo.scheme == 'https' || logo.scheme == 'http') &&
            logo.hasAuthority && logo.userInfo.isEmpty
                ? logo.toString() : '';
        results.add(LiveChannel({
          'id': _stableId(providerId, taken),
          'provider_id': providerId,
          'name_ar': txt(row['name']).trim(),
          'name_en': txt(row['name']).trim(),
          'package_name': path,
          'logo_url': safeLogo,
        }));
      }
    }
    return results;
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

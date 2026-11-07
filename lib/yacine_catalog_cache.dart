import 'dart:convert';
import 'native_api.dart';

/// Persist only provider catalog metadata. Signed playback URLs and headers
/// are deliberately excluded from offline storage.
String encodeYacineCatalog(List<LiveChannel> channels) => jsonEncode([
  for (final channel in channels)
    <String, dynamic>{
      'id': channel.id,
      'provider_id': channel.providerId,
      'name_ar': channel.title(true),
      'name_en': channel.title(false),
      'package_name': channel.group,
      'logo_url': channel.logo,
    }
]);

List<LiveChannel> decodeYacineCatalog(String? serialized) {
  if (serialized == null || serialized.length > 800000) return <LiveChannel>[];
  try {
    final data = jsonDecode(serialized);
    if (data is! List || data.isEmpty || data.length > 2500) {
      return <LiveChannel>[];
    }
    final result = <LiveChannel>[];
    final seen = <String>{};
    for (final row in data) {
      if (row is! Map) return <LiveChannel>[];
      final channel = LiveChannel(Map<String, dynamic>.from(row));
      final id = channel.providerId;
      if (!RegExp(r'^\d{1,24}$').hasMatch(id) ||
          channel.id <= 0 || channel.title(false).isEmpty ||
          !seen.add(id)) return <LiveChannel>[];
      result.add(channel);
    }
    return result;
  } catch (_) {
    return <LiveChannel>[];
  }
}

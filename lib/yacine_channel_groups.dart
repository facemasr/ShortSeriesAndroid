import 'native_api.dart';

/// Coalesces only explicitly marked quality variants of the SAME station.
/// All original provider IDs are preserved; signed media URLs are never stored.
final RegExp _resolution = RegExp(
  r'(2160|1440|1080|720|576|480|360|320|288|270|244|240|144)\s*p?',
  caseSensitive: false,
);
final RegExp _qualitySuffix = RegExp(
  r'\s*[\[(]?\s*(?:2160|1440|1080|720|576|480|360|320|288|270|244|240|144)\s*p?\s*[\])]?\s*$|\s*[\[(]?\s*(?:4k|uhd|fhd|full[\s_-]*hd|hd|sd)\s*[\])]?\s*$',
  caseSensitive: false,
);

int? yacineChannelQuality(LiveChannel channel) {
  final category = channel.group;
  final name = channel.title(false);
  final match = _resolution.firstMatch(category) ?? _resolution.firstMatch(name);
  if (match != null) return int.tryParse(match.group(1)!);
  final labels = ('$category $name').toLowerCase();
  if (RegExp(r'\b(4k|uhd)\b').hasMatch(labels)) return 2160;
  if (RegExp(r'\b(fhd|full[\s_-]*hd)\b').hasMatch(labels)) return 1080;
  if (RegExp(r'\bhd\b').hasMatch(labels)) return 720;
  if (RegExp(r'\bsd\b').hasMatch(labels)) return 480;
  return null;
}

String yacineWithoutQuality(String value) =>
    value.replaceAll(_qualitySuffix, '').trim();

class YacineQualityGroup {
  YacineQualityGroup(this.variants);
  final List<LiveChannel> variants;

  LiveChannel get preferred {
    final sorted = variants.toList()
      ..sort((a, b) =>
          (yacineChannelQuality(b) ?? 0).compareTo(yacineChannelQuality(a) ?? 0));
    for (final channel in sorted) {
      if ((yacineChannelQuality(channel) ?? 0) <= 720) return channel;
    }
    return sorted.last;
  }

  String title(bool ar) => yacineWithoutQuality(preferred.title(ar));
  String get category => yacineWithoutQuality(preferred.group);
  List<int> get qualities {
    final values = variants.map(yacineChannelQuality).whereType<int>().toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }
}

List<YacineQualityGroup> groupYacineChannels(List<LiveChannel> channels) {
  final groups = <String, List<LiveChannel>>{};
  for (final channel in channels) {
    final title = yacineWithoutQuality(channel.title(false)).toLowerCase();
    final category = yacineWithoutQuality(channel.group).toLowerCase();
    final q = yacineChannelQuality(channel);
    final id = channel.providerId.isNotEmpty
        ? channel.providerId : channel.id.toString();
    final key = title + '|' + category + (q == null ? '|' + id : '');
    groups.putIfAbsent(key, () => <LiveChannel>[]).add(channel);
  }
  return groups.values.map((c) => YacineQualityGroup(c)).toList();
}

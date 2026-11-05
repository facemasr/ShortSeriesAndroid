import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/native_api.dart';
import 'package:egyshow_mobile/yacine_channel_groups.dart';

LiveChannel ch(String id, String name, String group) =>
    LiveChannel(<String, dynamic>{
      'id': int.parse(id), 'provider_id': id,
      'name_en': name, 'name_ar': name, 'category': group,
    });

void main() {
  test('beIN SPORTS 1 appears once with all four resolution variants', () {
    final catalog = <LiveChannel>[
      ch('1424', 'beIN SPORTS 1', 'beIN SPORTS (1080P)'),
      ch('1425', 'beIN SPORTS 2', 'beIN SPORTS (1080P)'),
      ch('24', 'beIN SPORTS 1', 'beIN SPORTS (360P)'),
      ch('4', 'beIN SPORTS 1', 'beIN SPORTS (720P)'),
      ch('44', 'beIN SPORTS 1', 'beIN SPORTS (244P)'),
      ch('90', 'beIN SPORTS 1', 'Other package (480P)'),
    ];
    final grouped = groupYacineChannels(catalog);
    expect(grouped, hasLength(3));
    final first = grouped.firstWhere((g) =>
        g.title(false) == 'beIN SPORTS 1' && g.category == 'beIN SPORTS');
    expect(first.qualities, <int>[1080, 720, 360, 244]);
    expect(first.preferred.providerId, '4');
    expect(first.variants.map((c) => c.providerId).toSet(),
        <String>{'1424', '4', '24', '44'});
    expect(grouped.where((g) => g.title(false) == 'beIN SPORTS 2'),
        hasLength(1));
  });

  test('unlabeled streams remain distinct to prevent false merges', () {
    expect(groupYacineChannels([
      ch('10', 'Local Sports', 'Other'),
      ch('11', 'Local Sports', 'Other'),
    ]), hasLength(2));
  });

  test('quality parsing does not rewrite source identity', () {
    final channel = ch('1424', 'beIN SPORTS 1', 'beIN SPORTS (1080P)');
    expect(yacineChannelQuality(channel), 1080);
    expect(yacineWithoutQuality(channel.group), 'beIN SPORTS');
    expect(channel.providerId, '1424');
  });
}

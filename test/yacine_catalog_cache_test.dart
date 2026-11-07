import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/native_api.dart';
import 'package:egyshow_mobile/yacine_catalog_cache.dart';

void main() {
  test('cached index has no signed video URLs or session headers', () {
    final channel = LiveChannel(<String, dynamic>{
      'id': 1424, 'provider_id': '1424',
      'name_ar': 'beIN SPORTS 1', 'name_en': 'beIN SPORTS 1',
      'package_name': 'beIN SPORTS (1080P)', 'logo_url': '',
      'url': 'https://media.example/live.m3u8?t=SECRET&e=1999999999',
      'headers': <String, String>{'Cookie': 'secret'},
    });
    final stored = encodeYacineCatalog(<LiveChannel>[channel]);
    expect(stored.contains('SECRET'), isFalse);
    expect(stored.contains('Cookie'), isFalse);
    final read = decodeYacineCatalog(stored);
    expect(read, hasLength(1));
    expect(read.single.providerId, '1424');
    expect(read.single.group, 'beIN SPORTS (1080P)');
  });

  test('malformed, empty or duplicate catalogs are rejected', () {
    expect(decodeYacineCatalog('invalid-json'), isEmpty);
    expect(decodeYacineCatalog('[]'), isEmpty);
    final row = jsonDecode(encodeYacineCatalog([
      LiveChannel({'id': 1, 'provider_id': '1', 'name_en': 'Channel 1'})
    ])) as List;
    expect(decodeYacineCatalog(jsonEncode([...row, ...row])), isEmpty);
    expect(decodeYacineCatalog(jsonEncode([
      {'id': 1, 'provider_id': '../bad', 'name_en': 'Channel'}
    ])), isEmpty);
  });
}

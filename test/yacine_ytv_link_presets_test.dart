import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:egyshow_mobile/yacine_ytv_link_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('YTV style editor supports an ordinary video URL and media headers', () {
    final source = YtvManualLink.parse('https://example.com/live.m3u8',
      userAgent: 'EGYSHOW Android', referer: 'https://example.com/');
    expect(source.mayPersist, isTrue);
    expect(source.headers['User-Agent'], 'EGYSHOW Android');
    expect(source.headers['Referer'], 'https://example.com/');
    expect(YtvManualLink.fromJson(source.toJson()).url, source.url);
  });

  test('Signed stream URLs must never be persisted', () {
    for (final input in [
      'https://cdn.example.com/live.m3u8?e=1790000000',
      'https://cdn.example.com/live.m3u8?token=signed',
      'https://cdn.example.com/live.m3u8?hdnts=private',
      'https://cdn.example.com/live.m3u8?Signature=private',
    ]) {
      expect(YtvManualLink.parse(input).mayPersist, isFalse);
    }
  });

  test('Reject invalid and unsafe input', () {
    for (final value in [
      'javascript:alert(1)', 'file:///etc/passwd', 'http://name:pass@example.org/live',
      'not a valid URL'
    ]) {
      expect(() => YtvManualLink.parse(value), throwsFormatException);
    }
    expect(() => YtvManualLink.parse('https://example.com',
      userAgent: 'abc\nInvalid: attack'), throwsFormatException);
  });

  test('Only user-supplied non-expiring links can be saved and cleared', () async {
    SharedPreferences.setMockInitialValues({});
    final sample = YtvManualLink.parse('https://example.com/stream.m3u8');
    await YtvManualLinkStore.save('station-1', sample);
    expect((await YtvManualLinkStore.load('station-1'))?.url, sample.url);
    await YtvManualLinkStore.remove('station-1');
    expect(await YtvManualLinkStore.load('station-1'), isNull);
    await expectLater(YtvManualLinkStore.save('station-2',
        YtvManualLink.parse('https://example.com/live?token=secret')),
        throwsFormatException);
  });
}

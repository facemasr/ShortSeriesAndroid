import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_media_headers.dart';
import 'package:egyshow_mobile/yacine_vlc_m3u.dart';

void main() {
  test('beIN 1: creates clean per-channel VLC options from provider fields', () {
    final h = yacinePlaybackHeaders({
      'user_agent': 'Mozilla/5.0 Chrome/150.0.0.0',
      'referer': 'http://yacinneeee.live\u2060\u200D\u3164',
    });
    final text = yacineVlcM3u(
      stream: Uri.parse('http://media.example/live/918454578001/index.m3u8?t=NEW&e=1999999999'),
      channelName: 'beIN SPORTS 1',
      tvgId: '1424',
      groupTitle: 'beIN SPORTS (1080P)',
      headers: h,
    );
    expect(text, startsWith('#EXTM3U\n'));
    expect(text, contains('tvg-name="beIN SPORTS 1",beIN SPORTS 1'));
    expect(text, contains('#EXTVLCOPT:http-user-agent=Mozilla/5.0 Chrome/150.0.0.0'));
    expect(text, contains('#EXTVLCOPT:http-referrer=http://yacinneeee.live%E2%81%A0%E2%80%8D%E3%85%A4\n'));
    expect(text, contains('index.m3u8?t=NEW&e=1999999999'));
    expect(text.contains('\u2060'), isFalse);
  });

  test('beIN 2: preserves independently resolved URL and source headers', () {
    final m3u = yacineVlcM3u(
      stream: Uri.parse('https://media.example/live/2/index.m3u8?t=DIFFERENT'),
      channelName: 'beIN SPORTS 2',
      tvgId: '1425',
      groupTitle: 'Sports',
      headers: {'Referer': 'https://source.example'},
    );
    expect(m3u.contains('#EXTVLCOPT:http-user-agent='), isFalse);
    expect(m3u, contains('http-referrer=https://source.example'));
    expect(m3u, contains('tvg-id="1425"'));
    expect(m3u, contains('t=DIFFERENT'));
  });

  test('rejects invalid media URLs and newline metadata injection', () {
    expect(() => yacineVlcM3u(
      stream: Uri.parse('javascript:alert(1)'),
      channelName: 'bad',
      tvgId: '0',
      groupTitle: 'x',
      headers: const {},
    ), throwsArgumentError);
    final t = yacineVlcM3u(
      stream: Uri.parse('https://media.example/live.mp4'),
      channelName: 'Example\n#EXTVLCOPT:http-user-agent=EVIL',
      tvgId: '1',
      groupTitle: 'x',
      headers: const {},
    );
    expect(t.split('\n').where((line) => line.startsWith('#EXTVLCOPT')), isEmpty);
  });
}

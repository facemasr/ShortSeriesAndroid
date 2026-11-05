import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_media_headers.dart';

void main() {
  const declaredAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36';

  for (final channel in ['beIN SPORTS 1', 'beIN SPORTS 2']) {
    test('$channel: preserves percent-encoded provider Referer and User-Agent', () {
      final result = yacinePlaybackHeaders({
        'user_agent': declaredAgent,
        'referer': 'http://yacinneeee.live\u2060\u200D\u2060\u3164\u200C\u2060\u200D\u2060',
        'headers': {'ACCEPT': '*/*'},
      });
      expect(result, {
        'User-Agent': declaredAgent,
        'Referer': 'http://yacinneeee.live'
            '%E2%81%A0%E2%80%8D%E2%81%A0%E3%85%A4'
            '%E2%80%8C%E2%81%A0%E2%80%8D%E2%81%A0',
        'Accept': '*/*',
      });
    });
  }

  test('merges mixed-case nested fields with source-level override', () {
    final result = yacinePlaybackHeaders({
      'user_agent': 'SourceUA/1.0',
      'referrer': 'https://ref.example/path?q=1',
      'headers': '{"USER_AGENT":"NestedUA/2.0","ORIGIN":"https://ref.example",'
        '"aCCePt":"application/vnd.apple.mpegurl",'
        '"Accept-Language":"ar-EG"}',
    });
    expect(result['User-Agent'], 'SourceUA/1.0');
    expect(result['Referer'], 'https://ref.example/path?q=1');
    expect(result['Origin'], 'https://ref.example');
    expect(result['Accept'], 'application/vnd.apple.mpegurl');
    expect(result['Accept-Language'], 'ar-EG');
  });

  test('falls back to valid nested Referer when top-level is malformed', () {
    final result = yacinePlaybackHeaders({
      'referer': 'not a url',
      'headers': {'referer': 'https://ref.example/', 'user-agent': 'Playback/4'},
    });
    expect(result['Referer'], 'https://ref.example/');
    expect(result['User-Agent'], 'Playback/4');
  });

  test('rejects header injection and does not forward secrets', () {
    final result = yacinePlaybackHeaders({
      'user_agent': 'Bad\r\nInjected: yes',
      'referer': 'javascript:alert(1)',
      'headers': {
        'User-Agent': 'okhttp/4.12.0',
        'Authorization': 'Bearer SECRET',
        'Cookie': 'private=session',
        'Host': 'spoofed.test',
        'Origin': 'https://valid.example',
      },
    });
    expect(result['User-Agent'], 'okhttp/4.12.0');
    expect(result['Origin'], 'https://valid.example');
    expect(result.containsKey('Referer'), isFalse);
    expect(result.containsKey('Authorization'), isFalse);
    expect(result.containsKey('Cookie'), isFalse);
    expect(result.containsKey('Host'), isFalse);
  });

  test('uses native device or VLC identity when provider omitted agent', () {
    final result = yacinePlaybackHeaders({'headers': <String, String>{}});
    expect(result.containsKey('User-Agent'), isFalse);
  });

  test('explicit platform agent only fills absent provider agent', () {
    final result = yacinePlaybackHeaders({
      'referer': 'https://provider.example/live',
    }, fallbackUserAgent: 'AndroidPlayer/1.0');
    expect(result['User-Agent'], 'AndroidPlayer/1.0');
    expect(result['Referer'], 'https://provider.example/live');
    final declared = yacinePlaybackHeaders({
      'user_agent': 'ProviderAgent/8',
    }, fallbackUserAgent: 'AndroidPlayer/1.0');
    expect(declared['User-Agent'], 'ProviderAgent/8');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_vlc_options.dart';

void main() {
  test('VLC gets the playback UA and referer instead of API identity', () {
    final options = yacineVlcOptions({
      'User-Agent': 'Mozilla/5.0 Chrome/150.0.0.0',
      'Referer': 'http://example.test/player',
    });
    final httpOptions = options.http!.options;
    expect(httpOptions, contains(
      'http-user-agent=Mozilla/5.0 Chrome/150.0.0.0'));
    expect(httpOptions, contains('http-referrer=http://example.test/player'));
    expect(httpOptions, contains('http-reconnect'));
  });

  test('VLC does not invent missing media headers', () {
    final options = yacineVlcOptions({});
    final values = options.http!.options.join(';');
    expect(values.contains('http-user-agent='), isFalse);
    expect(values.contains('http-referrer='), isFalse);
  });
}

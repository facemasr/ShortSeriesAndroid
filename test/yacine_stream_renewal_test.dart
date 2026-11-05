import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_stream_renewal.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1793882800 * 1000,
      isUtc: true);
  final headers = {'User-Agent': 'Chrome/150', 'Referer': 'https://ref.example'};
  Uri source(String token, int expiry) =>
      Uri.parse('https://media.example/index.m3u8?t=$token&e=$expiry');

  test('unchanged URL and headers preserve existing healthy player', () {
    final u = source('A', 1793882850);
    expect(yacineHotSwapNeeded(activeUri: u, activeHeaders: headers,
      updatedUri: u, updatedHeaders: headers,
      activeSince: now.subtract(const Duration(minutes: 10)),
      now: now, healthy: true), isFalse);
  });
  test('changed token is adopted proactively before expiry', () {
    expect(yacineHotSwapNeeded(activeUri: source('A', 1793882850),
      activeHeaders: headers, updatedUri: source('B', 1793890000),
      updatedHeaders: headers, activeSince: now, now: now,
      healthy: true), isTrue);
  });
  test('fresh healthy picture does not restart for an early token rotation', () {
    expect(yacineHotSwapNeeded(activeUri: source('A', 1793990000),
      activeHeaders: headers, updatedUri: source('B', 1793990000),
      updatedHeaders: headers, activeSince: now, now: now,
      healthy: true), isFalse);
  });
  test('metadata includes rotating User-Agent and Referer', () {
    final u = source('A', 1793882850);
    expect(yacineHotSwapNeeded(activeUri: u, activeHeaders: headers,
      updatedUri: u, updatedHeaders: {'User-Agent': 'Chrome/151'},
      activeSince: now, now: now, healthy: true), isTrue);
  });
  test('unhealthy stream allows immediate hot-swap', () {
    expect(yacineHotSwapNeeded(activeUri: source('A', 1793990000),
      activeHeaders: headers, updatedUri: source('B', 1793990000),
      updatedHeaders: headers, activeSince: now, now: now,
      healthy: false), isTrue);
  });
  test('unknown-expiry sources rotate only after running three minutes', () {
    final a = Uri.parse('https://media.example/live.m3u8?t=A');
    final b = Uri.parse('https://media.example/live.m3u8?t=B');
    expect(yacineHotSwapNeeded(activeUri: a, activeHeaders: headers,
      updatedUri: b, updatedHeaders: headers,
      activeSince: now.subtract(const Duration(minutes: 2)),
      now: now, healthy: true), isFalse);
    expect(yacineHotSwapNeeded(activeUri: a, activeHeaders: headers,
      updatedUri: b, updatedHeaders: headers,
      activeSince: now.subtract(const Duration(minutes: 4)),
      now: now, healthy: true), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_decoder_fallback.dart';

void main() {
  test('try desktop VLC when Media3 fails to initialize an API source', () {
    expect(yacineShouldUseDesktopVlc(
      sourceCount: 1, media3Attempted: true,
      manualSource: false, healthyPlayer: false,
    ), isTrue);
  });

  test('do not treat an empty provider response as a decoder problem', () {
    expect(yacineShouldUseDesktopVlc(
      sourceCount: 0, media3Attempted: false,
      manualSource: false, healthyPlayer: false,
    ), isFalse);
  });

  test('never interrupt a healthy Media3 stream to switch decoders', () {
    expect(yacineShouldUseDesktopVlc(
      sourceCount: 1, media3Attempted: true,
      manualSource: false, healthyPlayer: true,
    ), isFalse);
  });

  test('manual URLs are never handed silently to another decoder', () {
    expect(yacineShouldUseDesktopVlc(
      sourceCount: 1, media3Attempted: true,
      manualSource: true, healthyPlayer: false,
    ), isFalse);
  });

  test('do not switch decoders before Media3 has attempted the URL', () {
    expect(yacineShouldUseDesktopVlc(
      sourceCount: 1, media3Attempted: false,
      manualSource: false, healthyPlayer: false,
    ), isFalse);
  });
}

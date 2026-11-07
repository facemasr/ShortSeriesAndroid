import 'package:flutter_test/flutter_test.dart';
import 'package:egyshow_mobile/yacine_provider_policy.dart';

void main() {
  test('retry brief channel metadata errors only', () {
    for (final code in [404, 408, 425, 429, 500, 502, 503, 504]) {
      expect(yacineRetryableProviderStatus(code), isTrue, reason: '$code');
    }
  });
  test('do not retry authorization or permanent failures', () {
    for (final code in [200, 201, 301, 400, 401, 403, 405, 410, 422]) {
      expect(yacineRetryableProviderStatus(code), isFalse, reason: '$code');
    }
  });
}

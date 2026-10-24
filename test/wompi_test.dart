import 'package:flutter_test/flutter_test.dart';
import 'package:corteya/booking/wompi.dart';

void main() {
  test(
    'Web Checkout conserva todos los parámetros firmados y los codifica',
    () {
      final parameters = {
        'public-key': 'pub_test_public',
        'currency': 'COP',
        'amount-in-cents': '1200000',
        'reference': 'R-ABCD-1',
        'signature:integrity': List.filled(64, 'a').join(),
        'redirect-url': 'corteya://pago',
        'expiration-time': '2026-10-23T20:30:00.000Z',
      };
      final uri = wompiCheckoutUri('https://checkout.wompi.co/p/', parameters);
      expect(uri.queryParameters, parameters);
      expect(uri.toString(), contains('signature%3Aintegrity='));
      expect(
        () => wompiCheckoutUri('https://evil.test/p/', parameters),
        throwsFormatException,
      );
      expect(
        () => wompiCheckoutUri('http://checkout.wompi.co/p/', parameters),
        throwsFormatException,
      );
      expect(
        () => wompiCheckoutUri('https://checkout.wompi.co/p/', {}),
        throwsFormatException,
      );
    },
  );
  test('Saldo en barbería es precio menos señal, sin montos negativos', () {
    expect(remainingCop(38000, 12000), 26000);
    expect(remainingCop(38000, 0), 38000);
    expect(remainingCop(38000, 38000), 0);
    expect(() => remainingCop(38000, 40000), throwsFormatException);
  });
}

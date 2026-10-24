import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:corteya/auth/screens.dart';
import 'package:corteya/barbershop/home.dart';
import 'package:corteya/barbershop/models.dart';
import 'package:corteya/app/theme.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets('Celular inválido no envía OTP; válido avanza', (tester) async {
    var requests = 0;
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneScreen(
          request: (phone) async {
            requests++;
          },
          onSent: (phone) => sent = phone,
        ),
      ),
    );
    await tester.tap(find.text('Enviar código'));
    await tester.pump();
    expect(find.text('Ingresa 10 dígitos que empiecen por 3.'), findsOneWidget);
    expect(requests, 0);
    await tester.enterText(find.byType(TextFormField), '3123456789');
    await tester.tap(find.text('Enviar código'));
    await tester.pump();
    expect(requests, 1);
    expect(sent, '3123456789');
  });
  testWidgets('OTP cuenta 60 segundos y reinicia al reenviar', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OtpScreen(
          now: tester.binding.clock.now,
          verify: (_) async {},
          resend: () async {
            requests++;
          },
          onVerified: () {},
        ),
      ),
    );
    expect(find.text('Reenviar en 60s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Reenviar en 1s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Reenviar'));
    await tester.pump();
    expect(requests, 1);
    expect(find.text('Reenviar en 60s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final enabled in [true, false]) {
    testWidgets('Home bookingEnabled=$enabled', (tester) async {
      final shop = Barbershop(
        slug: 'demo',
        name: 'Barbería desde backend',
        open: true,
        statusMessage: 'Abierto',
        bookingEnabled: enabled,
      );
      var bookings = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: shopTheme(shop),
          home: ShopHome(
            content: ShopContent(shop, [
              const ShopService('1', 'Corte', 30, 38000),
            ], []),
            onBook: () => bookings++,
            onChange: () {},
            onAccount: () {},
          ),
        ),
      );
      expect(find.text('Barbería desde backend'), findsOneWidget);
      expect(find.text(r'$38.000'), findsOneWidget);
      expect(
        find.text('Reservar cita'),
        enabled ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Esta barbería todavía no recibe reservas en línea'),
        enabled ? findsNothing : findsOneWidget,
      );
      if (enabled) {
        await tester.tap(find.text('Reservar cita'));
        expect(bookings, 1);
      }
    });
  }
}

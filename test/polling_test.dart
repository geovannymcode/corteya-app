import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corteya/app/state.dart';
import 'package:corteya/booking/api.dart';
import 'package:corteya/booking/payment.dart';
import 'package:corteya/booking/poller.dart';

import 'fixtures/booking_backend.dart';

void main() {
  testWidgets('Polling de 5 s se detiene al salir y al vencer el hold', (
    tester,
  ) async {
    final now = tester.binding.clock.now();
    final api = FixtureApi()
      ..current = appointmentFixture(
        deadline: now.add(const Duration(seconds: 12)),
      );
    final poller = AppointmentPoller(
      api: api,
      token: 'a' * 32,
      now: tester.binding.clock.now,
    );
    poller.setActive(true);
    await tester.pump();
    expect(api.reads, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(api.reads, 2);
    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
    expect(poller.expired, isTrue);
    final calls = api.reads;
    await tester.pump(const Duration(minutes: 2));
    expect(api.reads, calls);
    poller.dispose();
  });
  testWidgets(
    'Desactivar cancela el siguiente timer y reanudar consulta una vez',
    (tester) async {
      final api = FixtureApi()
        ..current = appointmentFixture(
          deadline: tester.binding.clock.now().add(const Duration(hours: 1)),
        );
      final poller = AppointmentPoller(
        api: api,
        token: 'a' * 32,
        now: tester.binding.clock.now,
      );
      poller.setActive(true);
      await tester.pump();
      poller.setActive(false);
      await tester.pump(const Duration(seconds: 40));
      expect(api.reads, 1);
      poller.setActive(true);
      await tester.pump();
      expect(api.reads, 2);
      poller.dispose();
    },
  );
  testWidgets('Errores aplican backoff 10 y 20 segundos', (tester) async {
    final api = FixtureApi()
      ..failure = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      );
    final poller = AppointmentPoller(
      api: api,
      token: 'a' * 32,
      now: tester.binding.clock.now,
    );
    poller.setActive(true);
    await tester.pump();
    expect(api.reads, 1);
    await tester.pump(const Duration(seconds: 9));
    expect(api.reads, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.reads, 2);
    await tester.pump(const Duration(seconds: 19));
    expect(api.reads, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.reads, 3);
    poller.dispose();
  });
  testWidgets('Widget pausa polling en segundo plano y bajo otra ruta', (
    tester,
  ) async {
    final api = FixtureApi()
      ..current = appointmentFixture(
        deadline: tester.binding.clock.now().add(const Duration(hours: 1)),
      );
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith(FixtureApp.new),
          bookingApiProvider.overrideWithValue(api),
          clockProvider.overrideWithValue(tester.binding.clock.now),
        ],
        child: MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [paymentRouteObserver],
          home: WaitingScreen(token: 'a' * 32, onConfirmed: (_) {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final initial = api.reads;
    expect(initial, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(api.reads, initial);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.reads, initial + 1);
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Otra pantalla')),
      ),
    );
    await tester.pumpAndSettle();
    final covered = api.reads;
    await tester.pump(const Duration(seconds: 30));
    expect(api.reads, covered);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(api.reads, covered + 1);
    await tester.pumpWidget(const SizedBox());
    final disposed = api.reads;
    await tester.pump(const Duration(seconds: 30));
    expect(api.reads, disposed);
  });
}

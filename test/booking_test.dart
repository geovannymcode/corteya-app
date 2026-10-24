import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:corteya/app/state.dart';
import 'package:corteya/booking/api.dart';
import 'package:corteya/booking/flow.dart';
import 'package:corteya/booking/models.dart';
import 'package:corteya/booking/payment.dart';
import 'package:corteya/booking/appointments.dart';

import 'fixtures/booking_backend.dart';
import 'session_test.dart' show Adapter, jsonBody;

Widget harness(Widget child, FixtureApi api, {DateTime Function()? now}) =>
    ProviderScope(
      overrides: [
        appProvider.overrideWith(FixtureApp.new),
        bookingApiProvider.overrideWithValue(api),
        clockProvider.overrideWithValue(now ?? () => fixedNow),
      ],
      child: MaterialApp(home: child),
    );
Future<void> choose(WidgetTester tester) async {
  await tester.tap(find.text('Corte'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Camilo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('10:00 a. m.'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await initializeDateFormatting('es_CO');
  });
  test('Libre hoy y día de semana en Bogotá', () {
    expect(freeAtText(slot, fixedNow), 'Libre hoy a las 10:00 a. m.');
    expect(
      freeAtText(DateTime.utc(2026, 10, 29, 14), fixedNow),
      'Libre el jueves a las 9:00 a. m.',
    );
    expect(freeAtText(null, fixedNow), 'Sin horarios esta semana');
  });
  testWidgets('Tres pasos y resumen usa los valores de booking-quote', (
    tester,
  ) async {
    final api = FixtureApi();
    await tester.pumpWidget(harness(const BookingFlow(), api));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué te hacemos?'), findsOneWidget);
    await tester.tap(find.text('Corte'));
    await tester.pumpAndSettle();
    expect(find.text('¿Con quién?'), findsOneWidget);
    expect(find.text('Sin horarios esta semana'), findsOneWidget);
    await tester.tap(find.text('Camilo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cuándo?'), findsOneWidget);
    await tester.tap(find.text('10:00 a. m.'));
    await tester.pumpAndSettle();
    expect(find.text('Revisa tu reserva'), findsOneWidget);
    expect(find.text(r'$42.000'), findsOneWidget);
    expect(find.text(r'$30.000'), findsOneWidget);
    expect(find.text('Política entregada por el backend.'), findsOneWidget);
  });
  for (final limit in [false, true]) {
    testWidgets(
      '409 ${limit ? 'límite pendiente conserva resumen' : 'horario recarga paso 3'}',
      (tester) async {
        final api = FixtureApi()
          ..conflict = !limit
          ..pendingLimit = limit;
        await tester.pumpWidget(harness(const BookingFlow(), api));
        await tester.pumpAndSettle();
        await choose(tester);
        await tester.ensureVisible(find.text('Confirmar reserva'));
        await tester.tap(find.text('Confirmar reserva'));
        await tester.pumpAndSettle();
        expect(api.creates, 1);
        if (limit) {
          expect(
            find.text(
              'Ya tienes 2 reservas pendientes de pago en esta barbería',
            ),
            findsOneWidget,
          );
          expect(find.text('Revisa tu reserva'), findsOneWidget);
        } else {
          expect(find.text('Ese horario acaba de ser tomado'), findsOneWidget);
          expect(find.text('¿Cuándo?'), findsOneWidget);
          expect(api.slotReads, 2);
        }
      },
    );
  }
  testWidgets('Servicio preseleccionado entra en paso 2', (tester) async {
    await tester.pumpWidget(
      harness(const BookingFlow(serviceId: 'service'), FixtureApi()),
    );
    await tester.pumpAndSettle();
    expect(find.text('¿Con quién?'), findsOneWidget);
  });
  testWidgets('Bre-B copia llave y referencia y termina cuenta regresiva', (
    tester,
  ) async {
    final initial = tester.binding.clock.now();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final a = Appointment.fromJson({
      ...appointmentFixture().json,
      'paymentInstructions': breb(initial.add(const Duration(seconds: 10))),
    });
    await tester.pumpWidget(
      harness(
        PaymentScreen(token: a.token, initial: a),
        FixtureApi(),
        now: tester.binding.clock.now,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(r'$12.000'), findsOneWidget);
    expect(find.text('Tiempo restante: 0:10'), findsOneWidget);
    await tester.tap(find.byTooltip('Copiar llave'));
    await tester.pump();
    expect(copied, '@BARBERIA');
    await tester.tap(find.byTooltip('Copiar referencia'));
    await tester.pump();
    expect(copied, 'R-ABCD');
    await tester.pump(const Duration(seconds: 11));
    expect(
      find.text('Tu reserva venció. Si ya pagaste, la barbería lo revisará'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final timely in [true, false]) {
    testWidgets(
      'Cancelar ${timely ? 'con devolución' : 'sin devolución'} pide confirmar y muestra mensaje backend',
      (tester) async {
        final api = FixtureApi()
          ..current = appointmentFixture(
            status: 'CONFIRMED',
            until: fixedNow.add(Duration(hours: timely ? 1 : -1)),
          )
          ..cancellationMessage = timely
              ? 'Cancelaste a tiempo: la barbería te devolverá \$12.000'
              : 'Cancelaste con menos de 6 horas: la señal no es reembolsable';
        await tester.pumpWidget(
          harness(AppointmentScreen(token: 'a' * 32), api),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Cancelar cita'));
        await tester.tap(find.text('Cancelar cita'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            timely
                ? 'Cancelas a tiempo: la barbería te devolverá \$12.000.'
                : 'Cancelas fuera del plazo: la señal no es reembolsable.',
          ),
          findsOneWidget,
        );
        expect(api.cancels, 0);
        await tester.tap(find.text('Sí, cancelar'));
        await tester.pumpAndSettle();
        expect(api.cancels, 1);
        expect(find.text(api.cancellationMessage), findsOneWidget);
      },
    );
  }
  for (final status in ['CONFIRMED', 'EXPIRED', 'DECLINED']) {
    testWidgets('Espera muestra $status del backend', (tester) async {
      final now = tester.binding.clock.now();
      final api = FixtureApi()
        ..current = appointmentFixture(
          status: status == 'DECLINED' ? 'PENDING_PAYMENT' : status,
          attempt: status == 'DECLINED' ? 'DECLINED' : 'APPROVED',
          canRetry: true,
          deadline: now.add(const Duration(minutes: 10)),
        );
      var confirmed = false;
      await tester.pumpWidget(
        harness(
          WaitingScreen(token: 'a' * 32, onConfirmed: (_) => confirmed = true),
          api,
          now: tester.binding.clock.now,
        ),
      );
      await tester.pump();
      await tester.pump();
      if (status == 'CONFIRMED') {
        expect(confirmed, isTrue);
      } else if (status == 'EXPIRED') {
        expect(
          find.text(
            'Tu reserva venció. Si ya pagaste, la barbería lo revisará',
          ),
          findsOneWidget,
        );
      } else {
        expect(find.text('El pago no se aprobó'), findsOneWidget);
        expect(find.text('Intentar de nuevo'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      final calls = api.reads;
      await tester.pump(const Duration(minutes: 1));
      expect(api.reads, calls);
    });
  }
  testWidgets(
    'Espera muestra ticket sin backoff si CONFIRMED y falla la lista auxiliar',
    (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      final api = BookingApi(dio);
      final detail = appointmentFixture(status: 'CONFIRMED');
      var auxiliaryCalls = 0;
      var detailCalls = 0;
      dio.httpClientAdapter = Adapter((request) async {
        if (request.path == '/api/v1/me/appointments') {
          auxiliaryCalls++;
          return jsonBody('{}', 503);
        }
        detailCalls++;
        return jsonBody(jsonEncode(detail.json), 200);
      });
      final confirmed = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookingApiProvider.overrideWithValue(api),
            clockProvider.overrideWithValue(() => fixedNow),
          ],
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: confirmed,
              builder: (context, done, child) => done
                  ? AppointmentScreen(token: detail.token)
                  : WaitingScreen(
                      token: detail.token,
                      onConfirmed: (_) => confirmed.value = true,
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tu cita está confirmada'), findsOneWidget);
      expect(find.text('Reintentar consulta'), findsNothing);
      expect(auxiliaryCalls, 1);
      expect(detailCalls, 2);
      await tester.pump(const Duration(seconds: 40));
      expect(detailCalls, 2);
      expect(auxiliaryCalls, 1);
      await tester.pumpWidget(const SizedBox());
      confirmed.dispose();
      dio.close();
    },
  );
}

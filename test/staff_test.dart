import 'dart:convert';

import 'package:corteya/app/state.dart';
import 'package:corteya/auth/profile.dart';
import 'package:corteya/booking/api.dart';
import 'package:corteya/booking/payment.dart' show paymentRouteObserver;
import 'package:corteya/staff/api.dart';
import 'package:corteya/staff/models.dart';
import 'package:corteya/staff/refresh.dart';
import 'package:corteya/staff/screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'fixtures/booking_backend.dart';
import 'session_test.dart' show Adapter, jsonBody;

class StaffApp extends AppController {
  StaffApp(this.role);
  final String role;
  @override
  AppState build() => AppState(
    content: content,
    ready: true,
    profile: Profile('user', 'Ana', [
      Membership(
        barbershopId: 'shop',
        role: role,
        barbershopSlug: 'demo',
        barberId: 'barber',
      ),
    ]),
  );
}

Map<String, dynamic> row({
  String status = 'CONFIRMED',
  String refund = 'NONE',
}) => {
  'id': 'appointment',
  'barberId': 'barber',
  'customerName': 'Ricardo',
  'customerPhone': '+573001234567',
  'serviceName': 'Corte',
  'barberName': 'Camilo',
  'startsAt': slot.toIso8601String(),
  'endsAt': slot.add(const Duration(minutes: 30)).toIso8601String(),
  'status': status,
  'depositStatus': 'PENDING',
  'refundStatus': refund,
  'appointment': {'depositCop': 12000},
};
Map<String, dynamic> item() => {
  'appointmentId': 'appointment',
  'depositId': 'deposit',
  'customerName': 'Ricardo',
  'customerPhone': '+573001234567',
  'startsAt': slot.toIso8601String(),
  'amountCop': 12000,
  'reference': 'R-TEST',
};
Map<String, dynamic> metrics() => {
  'totalAppointments': 2,
  'completed': 1,
  'noShows': 1,
  'noShowRate': 50,
  'depositsReceivedCop': 12000,
  'estimatedRevenueCop': 76000,
  'pendingRefunds': 1,
  'pendingRefundsCop': 12000,
};

class Backend {
  final calls = <RequestOptions>[];
  String status = 'CONFIRMED', refund = 'NONE';
  bool conflict = false;
  int? actionError;
  late final Dio dio = Dio()
    ..httpClientAdapter = Adapter((r) async {
      calls.add(r);
      dynamic data;
      var code = 200;
      if (r.method == 'POST') {
        if (actionError != null) {
          code = actionError!;
          data = {'detail': 'La operación no está permitida ahora'};
        } else if (conflict && r.path.endsWith('/time-off')) {
          code = 409;
          data = {
            'detail': 'Conflicto',
            'conflicts': [
              {
                'startsAt': slot.toIso8601String(),
                'endsAt': slot
                    .add(const Duration(minutes: 30))
                    .toIso8601String(),
              },
              {
                'startsAt': slot.toIso8601String(),
                'endsAt': slot
                    .add(const Duration(minutes: 30))
                    .toIso8601String(),
              },
            ],
          };
        } else if (conflict && r.path.endsWith('/appointments')) {
          code = 409;
          data = {'detail': 'cruce'};
        } else {
          code = 204;
          data = null;
        }
      } else if (r.path.endsWith('/action-items')) {
        data = {
          'pendingBreB': [item()],
          'latePayments': [item()],
          'pendingRefunds': [item()],
        };
      } else if (r.path.endsWith('/agenda')) {
        data = [row(status: status, refund: refund)];
      } else if (r.path.endsWith('/time-off')) {
        data = [];
      } else if (r.path.endsWith('/summary')) {
        data = {
          'metrics': metrics(),
          'barbers': [
            {
              'barberName': 'Camilo',
              'barberId': 'barber',
              'metrics': metrics(),
            },
          ],
        };
      } else if (r.path.endsWith('/barbers')) {
        data = [
          {'id': 'barber', 'name': 'Camilo', 'photoUrl': null},
        ];
      } else if (r.path.endsWith('/availability')) {
        data = {'morning': [], 'afternoon': []};
      }
      return jsonBody(jsonEncode(data), code);
    });
}

Future<void> mount(WidgetTester t, Backend b, {String role = 'OWNER'}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        appProvider.overrideWith(() => StaffApp(role)),
        staffApiProvider.overrideWithValue(StaffApi(b.dio)),
        bookingApiProvider.overrideWithValue(BookingApi(b.dio)),
        clockProvider.overrideWithValue(() => fixedNow),
      ],
      child: MaterialApp(
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorObservers: [paymentRouteObserver],
        home: const StaffScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  final f = find.text(label).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> cleanup(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
}

void main() {
  setUpAll(tz.initializeTimeZones);
  test('WhatsApp E.164 y mensaje codificado', () {
    final uri = whatsappLink('300 123 4567', 'Hola Ricardo, ¿cómo estás?');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/573001234567');
    expect(uri.queryParameters['text'], 'Hola Ricardo, ¿cómo estás?');
    expect(uri.toString(), contains('%C2%BF'));
    expect(() => whatsappLink('abc', 'hola'), throwsFormatException);
    expect(e164('+573001234567'), '+573001234567');
    expect(
      reminder(
        'Ricardo',
        slot,
        'Piloto',
        fixedNow.subtract(const Duration(days: 1)),
      ),
      contains('mañana'),
    );
  });
  test('Estados y asistencia respetan las reglas de backend', () {
    expect(staffStatus('PENDING_PAYMENT'), 'Pendiente de señal');
    expect(staffStatus('COMPLETED'), 'Asistió');
    expect(staffStatus('NO_SHOW'), 'No asistió');
    expect(depositLabel('APPROVED'), 'Señal recibida');
    final a = StaffAppointment.fromJson(row());
    expect(a.canComplete(slot.subtract(const Duration(minutes: 16))), false);
    expect(a.canComplete(slot.subtract(const Duration(minutes: 15))), true);
    expect(a.canNoShow(slot), false);
    expect(a.canNoShow(slot.add(const Duration(seconds: 1))), true);
  });
  testWidgets('Refresco cancela timer y petición al perder visibilidad', (
    t,
  ) async {
    var reads = 0;
    CancelToken? token;
    final refresh = StaffRefresh((c) async {
      reads++;
      token = c;
    });
    refresh.setActive(true);
    await t.pump();
    expect(reads, 1);
    await t.pump(const Duration(seconds: 60));
    await t.pump();
    expect(reads, 2);
    refresh.setActive(false);
    expect(token!.isCancelled, true);
    await t.pump(const Duration(minutes: 2));
    expect(reads, 2);
    refresh.setActive(true);
    await t.pump();
    expect(reads, 3);
    refresh.dispose();
    await t.pump(const Duration(minutes: 2));
    expect(reads, 3);
  });
  for (final role in ['OWNER', 'BARBER']) {
    testWidgets('Agenda $role y controles de rol', (t) async {
      final b = Backend();
      await mount(t, b, role: role);
      expect(find.text('Ricardo · Corte'), findsOneWidget);
      expect(
        find.text('Todos los barberos'),
        role == 'OWNER' ? findsOneWidget : findsNothing,
      );
      expect(
        b.calls
            .firstWhere((r) => r.path.endsWith('/agenda'))
            .queryParameters['barberId'],
        isNull,
      );
      await tap(t, 'Ricardo · Corte');
      expect(
        find.text('Puedes marcar asistencia desde 15 minutos antes del inicio'),
        findsOneWidget,
      );
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Asistió'),
      );
      expect(button.onPressed, isNull);
      await cleanup(t);
    });
  }
  for (final approve in [true, false]) {
    testWidgets('Confirmar o rechazar señal $approve espera confirmación', (
      t,
    ) async {
      final b = Backend();
      await mount(t, b);
      await tap(t, 'Pendientes');
      await tap(t, approve ? 'Sí me llegó \$12.000' : 'No me llegó');
      expect(b.calls.where((r) => r.method == 'POST'), isEmpty);
      await tap(t, 'Confirmar');
      expect(
        b.calls.any(
          (r) =>
              r.path.endsWith(approve ? '/deposit/confirm' : '/deposit/reject'),
        ),
        true,
      );
      await cleanup(t);
    });
  }
  testWidgets('Cancelar requiere motivo y confirmación', (t) async {
    final b = Backend();
    await mount(t, b);
    await tap(t, 'Ricardo · Corte');
    await tap(t, 'Cancelar cita');
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'))
          .onPressed,
      isNull,
    );
    await t.enterText(find.byType(TextField), 'Imprevisto');
    await t.pump();
    await tap(t, 'Continuar');
    await tap(t, 'Confirmar');
    expect(b.calls.firstWhere((r) => r.path.endsWith('/cancel')).data, {
      'reason': 'Imprevisto',
    });
    await cleanup(t);
  });
  testWidgets('Devolución exige confirmación del monto y cliente', (t) async {
    final b = Backend()..refund = 'PENDING';
    await mount(t, b);
    await tap(t, 'Ricardo · Corte');
    await tap(t, 'Marcar como devuelta');
    expect(find.text('¿Ya le devolviste \$12.000 a Ricardo?'), findsOneWidget);
    expect(b.calls.where((r) => r.method == 'POST'), isEmpty);
    await tap(t, 'Confirmar');
    expect(b.calls.any((r) => r.path.endsWith('/deposit/refunded')), true);
    await cleanup(t);
  });
  testWidgets('Pendientes agrupados con contador sin duplicar depósito', (
    t,
  ) async {
    final b = Backend();
    await mount(t, b);
    await tap(t, 'Pendientes');
    expect(find.text('Señales por confirmar'), findsOneWidget);
    expect(find.text('Pagos tardíos'), findsOneWidget);
    expect(find.text('Devoluciones pendientes'), findsOneWidget);
    expect(
      t.widget<Badge>(find.byType(Badge)).label,
      isA<Text>().having((v) => v.data, 'count', '1'),
    );
    await cleanup(t);
  });
  testWidgets('Resumen consulta los tres periodos y muestra barras de OWNER', (
    t,
  ) async {
    final b = Backend();
    await mount(t, b);
    await tap(t, 'Resumen');
    for (final label in ['Semana', 'Mes', 'Día']) {
      await tap(t, label);
    }
    expect(
      b.calls
          .where((r) => r.path.endsWith('/summary'))
          .map((r) => r.queryParameters['period'])
          .toSet(),
      {'DAY', 'WEEK', 'MONTH'},
    );
    expect(find.text('Por barbero'), findsOneWidget);
    await cleanup(t);
  });
  for (final code in [403, 404, 409]) {
    testWidgets(
      'Acción $code muestra mensaje del backend sin cambiar la cita',
      (t) async {
        final b = Backend()..actionError = code;
        await mount(t, b);
        await tap(t, 'Pendientes');
        await tap(t, 'No me llegó');
        await tap(t, 'Confirmar');
        expect(
          find.text('La operación no está permitida ahora'),
          findsOneWidget,
        );
        expect(find.text('Sí me llegó \$12.000'), findsOneWidget);
        await cleanup(t);
      },
    );
  }
  testWidgets('OWNER filtra agenda y BARBER no expone desglose', (t) async {
    final b = Backend();
    await mount(t, b);
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await tap(t, 'Camilo');
    expect(
      b.calls
          .lastWhere((r) => r.path.endsWith('/agenda'))
          .queryParameters['barberId'],
      'barber',
    );
    await cleanup(t);
    await mount(t, Backend(), role: 'BARBER');
    await tap(t, 'Resumen');
    expect(find.text('Por barbero'), findsNothing);
    await cleanup(t);
  });
  testWidgets('Cubrir agenda con formulario suspende refresco hasta volver', (
    t,
  ) async {
    final b = Backend();
    await mount(t, b);
    int reads() => b.calls.where((r) => r.path.endsWith('/agenda')).length;
    final initial = reads();
    await tap(t, 'Nueva cita');
    await t.pump(const Duration(minutes: 2));
    expect(reads(), initial);
    Navigator.of(t.element(find.text('Nueva cita manual'))).pop();
    await t.pumpAndSettle();
    expect(reads(), initial + 1);
    await cleanup(t);
  });
  testWidgets('Cita manual 409 mantiene formulario y muestra cruce', (t) async {
    final b = Backend()..conflict = true;
    await mount(t, b);
    await tap(t, 'Nueva cita');
    await t.enterText(
      find.widgetWithText(TextField, 'Nombre del cliente'),
      'Ricardo',
    );
    await tap(t, 'Crear cita');
    expect(find.text('Ya hay una cita en ese horario'), findsOneWidget);
    await cleanup(t);
  });
  testWidgets('Bloqueo 409 muestra las citas en conflicto', (t) async {
    final b = Backend()..conflict = true;
    await mount(t, b);
    await tap(t, 'Bloquear horas');
    await t.tap(find.byType(DropdownButtonFormField<String>).first);
    await t.pumpAndSettle();
    await tap(t, 'Camilo');
    await tap(t, 'Guardar bloqueo');
    expect(
      find.text('No se puede bloquear: tienes 2 citas en ese horario'),
      findsOneWidget,
    );
    await cleanup(t);
  });
  testWidgets('Agenda deja de refrescar en Cuenta y en segundo plano', (
    t,
  ) async {
    final b = Backend();
    await mount(t, b);
    int reads() => b.calls.where((r) => r.path.endsWith('/agenda')).length;
    final initial = reads();
    await tap(t, 'Cuenta');
    await t.pump(const Duration(minutes: 2));
    expect(reads(), initial);
    await tap(t, 'Agenda');
    final resumed = reads();
    expect(resumed, initial + 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(minutes: 2));
    expect(reads(), resumed);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(reads(), resumed + 1);
    await cleanup(t);
  });
}

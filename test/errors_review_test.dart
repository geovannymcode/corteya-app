import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:corteya/app/router.dart';
import 'package:corteya/app/state.dart';
import 'package:corteya/barbershop/picker.dart';
import 'package:corteya/booking/api.dart';
import 'package:corteya/booking/appointments.dart';
import 'package:corteya/core/errors.dart';

import 'fixtures/booking_backend.dart';
import 'session_test.dart' show Adapter, jsonBody;

void main() {
  setUpAll(tz.initializeTimeZones);
  Dio notFoundApi() =>
      Dio()..httpClientAdapter = Adapter((_) async => jsonBody('{}', 404));
  test('404 neutro por defecto y contexto de barbería solo sin detail', () {
    final request = RequestOptions(path: '/api/v1/appointments/token');
    final response = Response<dynamic>(
      requestOptions: request,
      statusCode: 404,
      data: {},
    );
    final error = DioException(requestOptions: request, response: response);
    expect(userMessage(error), 'No encontramos lo que buscabas');
    expect(
      userMessage(error, barbershopLookup: true),
      'No encontramos esa barbería. Revisa el código e intenta de nuevo.',
    );
    response.data = {'detail': 'El recurso ya no está disponible.'};
    expect(userMessage(error), 'El recurso ya no está disponible.');
    expect(
      userMessage(error, barbershopLookup: true),
      'El recurso ya no está disponible.',
    );
  });
  testWidgets('404 de una cita muestra mensaje neutro', (tester) async {
    final api = notFoundApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bookingApiProvider.overrideWithValue(BookingApi(api))],
        child: MaterialApp(home: AppointmentScreen(token: 'a' * 32)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No encontramos lo que buscabas'), findsOneWidget);
    expect(find.textContaining('No encontramos esa barbería'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('404 buscando código muestra mensaje de barbería', (
    tester,
  ) async {
    final api = notFoundApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith(FixtureApp.new),
          apiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: ShopPicker()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'no-existe');
    await tester.tap(find.text('Entrar con código'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No encontramos esa barbería. Revisa el código e intenta de nuevo.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('404 de deep link de barbería conserva contexto', (tester) async {
    final api = notFoundApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith(FixtureApp.new),
          apiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: LinkEntry(slug: 'no-existe')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No encontramos esa barbería. Revisa el código e intenta de nuevo.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}

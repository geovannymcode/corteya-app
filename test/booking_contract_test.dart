import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corteya/booking/api.dart';
import 'package:corteya/booking/models.dart';

import 'fixtures/booking_backend.dart';
import 'session_test.dart' show Adapter, jsonBody;

void main() {
  test('booking-quote es GET autenticado y crear solo envía selección y fecha con offset', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final api = BookingApi(dio);
    final seen = <RequestOptions>[];
    dio.httpClientAdapter = Adapter((r) async {
      seen.add(r);
      if (r.path.endsWith('/booking-quote')) {
        return jsonBody(
          jsonEncode({
            'priceCop': 42000,
            'depositMode': 'BREB_MANUAL',
            'depositCop': 12000,
            'payAtShopCop': 30000,
            'holdMinutes': 15,
            'cancellableWithRefundUntil': slot.toIso8601String(),
            'cancelPolicyText': 'La política del backend',
          }),
          200,
        );
      }
      return jsonBody(
        jsonEncode({
          'publicToken': 'a' * 32,
          'status': 'PENDING_PAYMENT',
          'depositCop': 12000,
          'holdExpiresAt': fixedNow
              .add(const Duration(minutes: 15))
              .toIso8601String(),
          'paymentInstructions': breb(
            fixedNow.add(const Duration(minutes: 15)),
          ),
        }),
        201,
      );
    });
    final quote = await api.quote('demo', 'service', 'barber', slot);
    expect(seen.first.method, 'GET');
    expect(seen.first.extra['public'], isNot(true));
    expect(seen.first.queryParameters, {
      'serviceId': 'service',
      'barberId': 'barber',
      'startsAt': slot.toUtc().toIso8601String(),
    });
    final a = await api.create(content, service, barber, slot, quote);
    expect(a.priceCop, 42000);
    expect(a.depositCop, 12000);
    expect(seen.last.data, {
      'serviceId': 'service',
      'barberId': 'barber',
      'startsAt': slot.toUtc().toIso8601String(),
    });
    expect(a.instructions!.mode, 'BREB_MANUAL');
    dio.close();
  });
  test('No acepta cotización incompleta ni montos inconsistentes', () {
    expect(
      () => BookingQuote.fromJson({
        'priceCop': 42000,
        'depositCop': 12000,
        'payAtShopCop': 1,
        'depositMode': 'NONE',
        'holdMinutes': 15,
        'cancelPolicyText': 'Política',
      }),
      throwsFormatException,
    );
  });
  test('Detalle retoma sin caché desde Mis citas y estado actual del backend prevalece', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final api = BookingApi(dio);
    final original = appointmentFixture();
    var mineCalls = 0;
    dio.httpClientAdapter = Adapter((r) async {
      if (r.path == '/api/v1/me/appointments') {
        mineCalls++;
        return jsonBody(
          jsonEncode({
            'upcoming': [original.json],
            'past': [],
          }),
          200,
        );
      }
      return jsonBody(
        jsonEncode({
          'publicToken': original.token,
          'status': 'CONFIRMED',
          'startsAt': original.startsAt.toIso8601String(),
          'endsAt': original.endsAt.toIso8601String(),
          'depositCop': 12000,
          'deposit': {
            'method': 'WOMPI',
            'status': 'APPROVED',
            'latestAttemptStatus': 'APPROVED',
            'canRetry': false,
            'holdExpiresAt': null,
          },
        }),
        200,
      );
    });
    final a = await api.appointment(original.token);
    expect(a.status, 'CONFIRMED');
    expect(a.serviceName, 'Corte');
    expect(a.priceCop, 42000);
    await api.appointment(original.token);
    expect(mineCalls, 1);
    dio.close();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:corteya/core/formats.dart';
import 'package:corteya/core/errors.dart';
import 'package:corteya/app/theme.dart';
import 'package:corteya/barbershop/links.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  test('Celular colombiano exacto', () {
    expect(validPhone('3123456789'), isTrue);
    for (final phone in [
      '2123456789',
      '312345678',
      '31234567890',
      '+573123456789',
      '31234x6789',
    ]) {
      expect(validPhone(phone), isFalse);
    }
  });
  test('COP entero sin espacio ni decimales', () {
    expect(formatCop(38000), r'$38.000');
    expect(formatCop(0), r'$0');
    expect(formatCop(1250000), r'$1.250.000');
  });
  test('Offset se convierte a Bogotá y cruza día', () {
    final date = bogota(DateTime.parse('2026-10-24T02:00:00+02:00'));
    expect(date.day, 23);
    expect(date.hour, 19);
    expect(bogotaTime(date), '7:00 p. m.');
    expect(bogotaTime(DateTime.parse('2026-10-23T17:00:00Z')), '12:00 p. m.');
  });
  test('Color inválido usa fallback y texto supera contraste 4.5', () {
    expect(parseColor('red', Colors.blue), Colors.blue);
    expect(parseColor('#abcd', Colors.blue), Colors.blue);
    for (final color in [
      Colors.black,
      Colors.white,
      Colors.red,
      Colors.blue,
      const Color(0xff777777),
    ]) {
      final text = accentText(color);
      final a = color.computeLuminance();
      final b = text.computeLuminance();
      expect(
        ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
  test(
    'ProblemDetail preserva mensajes 429 y 503; sin red no revela detalles',
    () {
      for (final status in [429, 503]) {
        final request = RequestOptions(path: '/otp');
        final error = DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: status,
            data: {'detail': 'Intenta de nuevo en un minuto.'},
          ),
        );
        expect(userMessage(error), 'Intenta de nuevo en un minuto.');
      }
      expect(
        userMessage(
          DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.connectionError,
            error: 'secret',
          ),
        ),
        'Revisa tu conexión',
      );
      expect(
        userMessage(StateError('token secreto')),
        isNot(contains('secreto')),
      );
    },
  );
  test('Enlaces propios y QR HTTPS solo del dominio configurado', () {
    expect(shopSlug('corteya://b/mi-barberia'), 'mi-barberia');
    expect(
      shopSlug('https://corteya.co/b/mi-barberia', appLinkHost: 'corteya.co'),
      'mi-barberia',
    );
    expect(
      shopSlug('https://otro.co/b/mi-barberia', appLinkHost: 'corteya.co'),
      isNull,
    );
    expect(shopSlug('../../me'), isNull);
  });
}

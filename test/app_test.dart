import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:corteya/app/app.dart';
import 'package:corteya/app/config.dart';
import 'package:corteya/app/router.dart';
import 'package:corteya/app/state.dart';
import 'package:corteya/auth/profile.dart';
import 'package:corteya/core/storage.dart';

import 'session_test.dart' show MemoryStore, Adapter, jsonBody;

class MockPreferences extends Mock implements ShopPreferences {}

void main() {
  setUpAll(tz.initializeTimeZones);
  test('Staff se decide por slug y rol de esa barbería, no por ID ni otra membresía', () {
    final profile = Profile.fromJson({
      'id': 'user',
      'name': 'Ana',
      'memberships': [
        {
          'barbershopId': 'private-id',
          'barbershopSlug': 'mi-barberia',
          'barbershopName': 'Mi Barbería',
          'role': 'BARBER',
        },
        {
          'barbershopId': 'other-id',
          'barbershopSlug': 'otra-barberia',
          'barbershopName': 'Otra Barbería',
          'role': 'OWNER',
        },
      ],
    });
    expect(profile.staffOf('mi-barberia'), isTrue);
    expect(profile.staffOf('otra-barberia'), isTrue);
    expect(profile.staffOf('private-id'), isFalse);
    expect(profile.staffOf('tercera'), isFalse);
    expect(profile.staffOf(null), isFalse);
    final old = Profile.fromJson({
      'id': 'user',
      'name': 'Ana',
      'memberships': [
        {'barbershopId': 'private-id', 'role': 'OWNER'},
      ],
    });
    expect(old.staffOf('mi-barberia'), isFalse);
  });
  for (final staff in [false, true]) {
    testWidgets('Arranque con sesión y membresía actual staff=$staff', (
      tester,
    ) async {
      final preferences = MockPreferences();
      when(() => preferences.read()).thenAnswer((_) async => 'mi-barberia');
      when(() => preferences.write(any())).thenAnswer((_) async {});
      final store = MemoryStore();
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'https://example.test',
              appLinkHost: 'corteya.invalid',
              environment: 'test',
            ),
          ),
          tokenStoreProvider.overrideWithValue(store),
          preferencesProvider.overrideWithValue(preferences),
        ],
      );
      final paths = <String>[];
      container.read(apiProvider).httpClientAdapter = Adapter((r) async {
        paths.add(r.path);
        final Object data;
        if (r.path == '/api/v1/me') {
          data = {
            'id': 'user',
            'name': 'Ana',
            'memberships': [
              {
                'barbershopId': 'private-id',
                'barbershopSlug': staff ? 'mi-barberia' : 'otra',
                'barbershopName': 'Mi Barbería',
                'role': 'OWNER',
              },
            ],
          };
        } else if (r.path.endsWith('/services')) {
          data = [
            {
              'id': 'service',
              'name': 'Corte',
              'durationMinutes': 30,
              'priceCop': 38000,
            },
          ];
        } else if (r.path.endsWith('/barbers')) {
          expect(r.queryParameters['serviceId'], 'service');
          data = [
            {'id': 'barber', 'name': 'Camilo', 'photoUrl': null},
          ];
        } else {
          data = {
            'slug': 'mi-barberia',
            'name': 'Mi Barbería',
            'logoUrl': null,
            'primaryColor': '#ddf66b',
            'secondaryColor': '#ffffff',
            'open': true,
            'statusMessage': 'Abierto',
            'nextChangeAt': null,
            'bookingEnabled': true,
          };
        }
        return jsonBody(jsonEncode(data), 200);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CorteYaApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(paths, contains('/api/v1/me'));
      expect(find.text('Modo barbero'), staff ? findsOneWidget : findsNothing);
      expect(find.text('Mi Barbería'), staff ? findsNothing : findsOneWidget);
      if (!staff) {
        await tester.tap(find.text('Reservar cita'));
        await tester.pumpAndSettle();
        expect(find.text('¿Qué te hacemos?'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }
  testWidgets('Deep link al arrancar y cambiar barbería con app abierta', (
    tester,
  ) async {
    final preferences = MockPreferences();
    when(() => preferences.read()).thenAnswer((_) async => null);
    when(() => preferences.write(any())).thenAnswer((_) async {});
    final store = MemoryStore()..value = null;
    final container = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://example.test',
            appLinkHost: 'corteya.invalid',
            environment: 'test',
          ),
        ),
        tokenStoreProvider.overrideWithValue(store),
        preferencesProvider.overrideWithValue(preferences),
      ],
    );
    container.read(apiProvider).httpClientAdapter = Adapter((r) async {
      if (r.path.endsWith('/services')) return jsonBody('[]', 200);
      final slug = r.path.split('/').last;
      return jsonBody(
        jsonEncode({
          'slug': slug,
          'name': slug,
          'logoUrl': null,
          'open': false,
          'statusMessage': 'Cerrado',
          'bookingEnabled': false,
        }),
        200,
      );
    });
    final router = container.read(routerProvider);
    router.go('corteya://b/primera');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CorteYaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('primera'), findsOneWidget);
    router.go('corteya://b/segunda');
    await tester.pumpAndSettle();
    expect(find.text('segunda'), findsOneWidget);
    verify(() => preferences.write('primera')).called(1);
    verify(() => preferences.write('segunda')).called(1);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  testWidgets('Reservar sin sesión pide OTP y nombre y conserva el destino', (
    tester,
  ) async {
    final preferences = MockPreferences();
    when(() => preferences.read()).thenAnswer((_) async => 'mi-barberia');
    when(() => preferences.write(any())).thenAnswer((_) async {});
    final store = MemoryStore()..value = null;
    String? name;
    final container = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://example.test',
            appLinkHost: 'corteya.invalid',
            environment: 'test',
          ),
        ),
        tokenStoreProvider.overrideWithValue(store),
        preferencesProvider.overrideWithValue(preferences),
      ],
    );
    container.read(apiProvider).httpClientAdapter = Adapter((r) async {
      Object data = {};
      if (r.path.endsWith('/otp/request')) {
        expect(r.data, {'phone': '+573123456789'});
      } else if (r.path.endsWith('/otp/verify')) {
        expect(r.data, {'phone': '+573123456789', 'code': '123456'});
        data = {'accessToken': 'access', 'refreshToken': 'refresh'};
      } else if (r.path == '/api/v1/me') {
        if (r.method == 'PATCH') name = (r.data as Map)['name'] as String;
        data = {'id': 'user', 'name': name, 'memberships': []};
      } else if (r.path.endsWith('/services')) {
        data = [];
      } else {
        data = {
          'slug': 'mi-barberia',
          'name': 'Mi Barbería',
          'open': true,
          'statusMessage': 'Abierto',
          'bookingEnabled': true,
        };
      }
      return jsonBody(jsonEncode(data), 200);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CorteYaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reservar cita'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '3123456789');
    await tester.ensureVisible(find.text('Enviar código'));
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verificar código'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo te llamas?'), findsOneWidget);
    expect(
      container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      '/name?next=booking',
    );
    expect(store.value!.refreshToken, 'refresh');
    await tester.enterText(find.byType(TextFormField), 'Ana');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(name, 'Ana');
    expect(
      container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      '/booking',
    );
    expect(find.text('¿Qué te hacemos?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}

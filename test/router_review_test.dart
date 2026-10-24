import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:corteya/app/app.dart';
import 'package:corteya/app/config.dart';
import 'package:corteya/app/router.dart';
import 'package:corteya/app/state.dart';
import 'package:corteya/core/storage.dart';

import 'fixtures/booking_backend.dart';
import 'session_test.dart' show MemoryStore, Adapter, jsonBody;

class ReviewPreferences extends Mock implements ShopPreferences {}

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'Refresh fallido permite home, deep link y cambiar barbería; protege reserva',
    (tester) async {
      final preferences = ReviewPreferences();
      when(() => preferences.write(any())).thenAnswer((_) async {});
      final store = MemoryStore();
      final container = ProviderContainer(
        overrides: [
          appProvider.overrideWith(FixtureApp.new),
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
      final api = container.read(apiProvider);
      api.httpClientAdapter = Adapter((request) async {
        if (request.path == '/private') return jsonBody('{}', 401);
        if (request.path.endsWith('/services')) return jsonBody('[]', 200);
        return jsonBody(
          jsonEncode({
            'slug': 'nueva',
            'name': 'Nueva barbería',
            'open': false,
            'statusMessage': 'Cerrado',
            'bookingEnabled': true,
          }),
          200,
        );
      });
      var refreshes = 0;
      container.read(sessionProvider).refreshDio.httpClientAdapter = Adapter((
        request,
      ) async {
        refreshes++;
        return jsonBody('{}', 401);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CorteYaApp(),
        ),
      );
      await tester.pumpAndSettle();
      final failure = expectLater(
        api.get<dynamic>('/private'),
        throwsA(isA<DioException>()),
      );
      await tester.pumpAndSettle();
      await failure;
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(store.value, isNull);
      expect(container.read(appProvider).profile, isNull);
      expect(container.read(appProvider).message, isNotNull);
      final router = container.read(routerProvider);
      router.go('/home');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.text('Barbería del contrato'), findsOneWidget);
      router.go('corteya://b/nueva');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.text('Nueva barbería'), findsOneWidget);
      router.go('/booking');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/login?next=booking',
      );
      expect(
        find.text('Tu sesión terminó. Ingresa de nuevo para continuar.'),
        findsOneWidget,
      );
      router.go('/');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      await container.read(appProvider.notifier).changeShop();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Escanea el QR de tu barbería'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}

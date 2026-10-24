import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:corteya/app/app.dart';
import 'package:corteya/app/router.dart';
import 'package:corteya/app/state.dart';
import 'package:corteya/booking/api.dart';

import 'fixtures/booking_backend.dart';

class MemoryPendingStore extends PendingPaymentStore {
  MemoryPendingStore() : super(const FlutterSecureStorage());
  String? user, token;
  @override
  Future<void> save(String user, String token) async {
    this.user = user;
    this.token = token;
  }

  @override
  Future<String?> read(String user) async => user == this.user ? token : null;
}

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await initializeDateFormatting('es_CO');
  });
  testWidgets(
    'Redirect manipulado nunca confirma; consulta token local del usuario',
    (tester) async {
      final pending = MemoryPendingStore();
      await pending.save('user', 'a' * 32);
      final api = FixtureApi()
        ..current = appointmentFixture(
          deadline: tester.binding.clock.now().add(const Duration(minutes: 2)),
        );
      final container = ProviderContainer(
        overrides: [
          appProvider.overrideWith(FixtureApp.new),
          bookingApiProvider.overrideWithValue(api),
          pendingPaymentProvider.overrideWithValue(pending),
          clockProvider.overrideWithValue(tester.binding.clock.now),
        ],
      );
      container
          .read(routerProvider)
          .go('corteya://pago?status=CONFIRMED&publicToken=evil');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CorteYaApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tu cita está confirmada'), findsNothing);
      expect(find.text('Estamos verificando tu pago'), findsOneWidget);
      expect(api.reads, 1);
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/appointments/${'a' * 32}/wait',
      );
      api.current = appointmentFixture(status: 'CONFIRMED');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Tu cita está confirmada'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}

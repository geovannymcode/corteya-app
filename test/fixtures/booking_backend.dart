import 'package:dio/dio.dart';
import 'package:corteya/app/state.dart';
import 'package:corteya/auth/profile.dart';
import 'package:corteya/barbershop/models.dart';
import 'package:corteya/booking/api.dart';
import 'package:corteya/booking/models.dart';

final fixedNow = DateTime.utc(2026, 10, 23, 13);
final slot = DateTime.utc(2026, 10, 23, 15);
const service = ShopService('service', 'Corte', 30, 38000);
final barber = Barber('barber', 'Camilo', null, slot);
const fixtureShop = Barbershop(
  slug: 'demo',
  name: 'Barbería del contrato',
  open: true,
  statusMessage: 'Abierto',
  bookingEnabled: true,
  bookingWindowDays: 14,
  address: 'Calle de la barbería',
  city: 'Bogotá',
);
final content = ShopContent(fixtureShop, [service], [barber]);

class FixtureApp extends AppController {
  @override
  AppState build() => AppState(
    content: content,
    profile: const Profile('user', 'Ana', []),
    ready: true,
  );
  @override
  Future<void> start() async {}
}

BookingQuote fixtureQuote() => BookingQuote.fromJson({
  'priceCop': 42000,
  'depositMode': 'BREB_MANUAL',
  'depositCop': 12000,
  'payAtShopCop': 30000,
  'holdMinutes': 15,
  'cancellableWithRefundUntil': fixedNow
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'cancelPolicyText': 'Política entregada por el backend.',
});
Map<String, dynamic> breb(DateTime deadline) => {
  'mode': 'BREB_MANUAL',
  'amountCop': 12000,
  'reference': 'R-ABCD',
  'expiresAt': deadline.toIso8601String(),
  'brebKey': '@BARBERIA',
  'brebHolderName': 'Titular de la barbería',
};
Appointment appointmentFixture({
  String status = 'PENDING_PAYMENT',
  String attempt = 'PENDING',
  DateTime? deadline,
  DateTime? until,
  bool canRetry = false,
  String? refundStatus,
}) => Appointment.fromJson({
  'publicToken': 'a' * 32,
  'status': status,
  'serviceName': 'Corte',
  'barberName': 'Camilo',
  'barbershopName': 'Barbería del contrato',
  'barbershopSlug': 'demo',
  'startsAt': slot.toIso8601String(),
  'endsAt': slot.add(const Duration(minutes: 30)).toIso8601String(),
  'priceCop': 42000,
  'depositCop': 12000,
  'cancellable': true,
  'cancellableWithRefundUntil':
      (until ?? fixedNow.add(const Duration(hours: 1))).toIso8601String(),
  'cancelPolicyText': 'Política entregada por el backend.',
  'deposit': {
    'method': 'WOMPI',
    'status': 'PENDING',
    'amountCop': 12000,
    'reference': 'R-ABCD',
    'latestAttemptStatus': attempt,
    'canRetry': canRetry,
    'holdExpiresAt': (deadline ?? fixedNow.add(const Duration(minutes: 15)))
        .toIso8601String(),
    'refundStatus': refundStatus ?? 'NONE',
  },
});

class FixtureApi extends BookingApi {
  FixtureApi() : super(Dio());
  int reads = 0, slotReads = 0, creates = 0, cancels = 0;
  bool conflict = false, pendingLimit = false;
  Appointment? current;
  List<Appointment>? sequence;
  Object? failure;
  String cancellationMessage =
      'Cancelaste a tiempo: la barbería te devolverá \$12.000';
  @override
  Future<List<Barber>> barbers(String slug, String serviceId) async => [
    barber,
    const Barber('unavailable', 'Sin disponibilidad', null),
  ];
  @override
  Future<Map<String, List<DateTime>>> slots(
    String slug,
    String serviceId,
    String barberId,
    DateTime day,
  ) async {
    slotReads++;
    return {
      'morning': [slot],
      'afternoon': [],
    };
  }

  @override
  Future<BookingQuote> quote(
    String slug,
    String serviceId,
    String barberId,
    DateTime start,
  ) async => quoteFixture();
  BookingQuote quoteFixture() => fixtureQuote();
  @override
  Future<Appointment> create(
    ShopContent content,
    ShopService service,
    Barber barber,
    DateTime start,
    BookingQuote quote,
  ) async {
    creates++;
    if (conflict || pendingLimit) {
      throw DioException(
        requestOptions: RequestOptions(),
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 409,
          data: {
            'detail': pendingLimit
                ? 'Ya tienes 2 reservas pendientes de pago en esta barbería'
                : 'Ese horario acaba de ser tomado',
          },
        ),
      );
    }
    return appointmentFixture();
  }

  @override
  Future<Appointment> appointment(
    String token, {
    CancelToken? cancelToken,
  }) async {
    reads++;
    if (failure != null) throw failure!;
    return sequence == null
        ? current ?? appointmentFixture()
        : sequence![(reads - 1).clamp(0, sequence!.length - 1)];
  }

  @override
  Future<MyAppointments> mine() async =>
      MyAppointments([current ?? appointmentFixture()], []);
  @override
  Future<String> cancel(String token) async {
    cancels++;
    current = appointmentFixture(status: 'CANCELLED', refundStatus: 'PENDING');
    return cancellationMessage;
  }

  @override
  Future<Barbershop> shop(String slug) async => shopFixture();
  Barbershop shopFixture() => fixtureShop;
}

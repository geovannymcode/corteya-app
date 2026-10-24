import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app/state.dart';
import '../barbershop/models.dart';
import 'models.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
final bookingApiProvider = Provider<BookingApi>((ref) {
  ref.watch(appProvider.select((state) => state.profile?.id));
  return BookingApi(ref.watch(apiProvider));
});

class BookingApi {
  BookingApi(this.dio);
  final Dio dio;
  final _details = <String, Map<String, dynamic>>{};
  final _enrichmentAttempted = <String>{};
  Future<List<Barber>> barbers(String slug, String serviceId) async {
    final result = await dio.get<List<dynamic>>(
      '/api/v1/barbershops/${Uri.encodeComponent(slug)}/barbers',
      queryParameters: {'serviceId': serviceId},
      options: Options(extra: {'public': true}),
    );
    return result.data!.map((e) => Barber.fromJson(objectMap(e))).toList();
  }

  Future<Map<String, List<DateTime>>> slots(
    String slug,
    String serviceId,
    String barberId,
    DateTime day,
  ) async {
    final result = await dio.get<Map<String, dynamic>>(
      '/api/v1/barbershops/${Uri.encodeComponent(slug)}/availability',
      queryParameters: {
        'serviceId': serviceId,
        'barberId': barberId,
        'date': dateKey(day),
      },
      options: Options(extra: {'public': true}),
    );
    return {
      for (final key in ['morning', 'afternoon'])
        key: (result.data![key] as List).map(instant).toList(),
    };
  }

  Future<BookingQuote> quote(
    String slug,
    String serviceId,
    String barberId,
    DateTime start,
  ) async {
    final result = await dio.get<Map<String, dynamic>>(
      '/api/v1/barbershops/${Uri.encodeComponent(slug)}/booking-quote',
      queryParameters: {
        'serviceId': serviceId,
        'barberId': barberId,
        'startsAt': start.toUtc().toIso8601String(),
      },
    );
    return BookingQuote.fromJson(result.data!);
  }

  Future<Appointment> create(
    ShopContent content,
    ShopService service,
    Barber barber,
    DateTime start,
    BookingQuote quote,
  ) async {
    final result = await dio.post<Map<String, dynamic>>(
      '/api/v1/barbershops/${Uri.encodeComponent(content.shop.slug)}/appointments',
      data: {
        'serviceId': service.id,
        'barberId': barber.id,
        'startsAt': start.toUtc().toIso8601String(),
      },
    );
    final json = <String, dynamic>{
      'serviceName': service.name,
      'barberName': barber.name,
      'barbershopName': content.shop.name,
      'barbershopSlug': content.shop.slug,
      'barbershopLogoUrl': content.shop.logoUrl,
      'startsAt': start.toUtc().toIso8601String(),
      'endsAt': start
          .add(Duration(minutes: service.durationMinutes))
          .toUtc()
          .toIso8601String(),
      'priceCop': quote.priceCop,
      'depositCop': quote.depositCop,
      'cancellableWithRefundUntil': quote.until?.toUtc().toIso8601String(),
      'cancelPolicyText': quote.policy,
      ...result.data!,
    };
    final appointment = Appointment.fromJson(json);
    _details[appointment.token] = json;
    return appointment;
  }

  Future<MyAppointments> mine() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/v1/me/appointments',
    );
    List<Appointment> parse(String key) =>
        (response.data![key] as List).map((v) {
          final json = objectMap(v);
          final a = Appointment.fromJson(json);
          _details[a.token] = json;
          return a;
        }).toList();
    return MyAppointments(parse('upcoming'), parse('past'));
  }

  Future<Appointment> appointment(
    String token, {
    CancelToken? cancelToken,
  }) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/v1/appointments/${Uri.encodeComponent(token)}',
      cancelToken: cancelToken,
    );
    if (_details[token]?.containsKey('cancellable') != true &&
        _enrichmentAttempted.add(token)) {
      // Optional enrichment: remember the attempt even when the list fails or
      // omits this token, so polling never depends on this auxiliary endpoint.
      try {
        final rows = await dio.get<Map<String, dynamic>>(
          '/api/v1/me/appointments',
          cancelToken: cancelToken,
        );
        for (final section in ['upcoming', 'past']) {
          for (final row in rows.data![section] as List) {
            final json = objectMap(row);
            final rowToken = json['publicToken'] as String;
            _details[rowToken] = {...?_details[rowToken], ...json};
          }
        }
      } catch (error) {
        if (error is DioException && CancelToken.isCancel(error)) rethrow;
        final cancellation = cancelToken?.cancelError;
        if (cancellation != null) throw cancellation;
        // Keep the authoritative detail, including when enrichment is malformed.
      }
    }
    return Appointment.fromJson({...?_details[token], ...response.data!});
  }

  Future<PaymentInstructions> retry(String token) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/v1/appointments/${Uri.encodeComponent(token)}/payment-attempts',
    );
    return PaymentInstructions.fromJson(response.data!);
  }

  Future<String> cancel(String token) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/v1/appointments/${Uri.encodeComponent(token)}/cancel',
    );
    return response.data!['message'] as String;
  }

  Future<Barbershop> shop(String slug) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/v1/barbershops/${Uri.encodeComponent(slug)}',
      options: Options(extra: {'public': true}),
    );
    return Barbershop.fromJson(response.data!);
  }
}

final pendingPaymentProvider = Provider<PendingPaymentStore>(
  (ref) => PendingPaymentStore(ref.watch(tokenStoreProvider).storage),
);

class PendingPaymentStore {
  PendingPaymentStore(this.storage);
  final FlutterSecureStorage storage;
  Future<void> save(String user, String token) async => storage.write(
    key: 'pendingPayment',
    value: jsonEncode({'user': user, 'token': token}),
  );
  Future<String?> read(String user) async {
    final String? value = await storage.read(key: 'pendingPayment');
    if (value == null) return null;
    try {
      final data = objectMap(jsonDecode(value));
      return data['user'] == user ? data['token'] as String? : null;
    } on Object {
      return null;
    }
  }
}

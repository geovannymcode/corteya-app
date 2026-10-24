import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../barbershop/models.dart';
import '../core/formats.dart';
import 'api.dart';
import 'models.dart';

final bookingProvider =
    NotifierProvider.autoDispose<BookingController, BookingState>(
      BookingController.new,
    );

class BookingState {
  const BookingState({
    this.step = 1,
    this.service,
    this.barber,
    this.day,
    this.slot,
    this.quote,
    this.barbers = const [],
    this.slots = const {},
    this.loading = false,
    this.error,
    this.slotTaken = false,
  });
  final int step;
  final ShopService? service;
  final Barber? barber;
  final DateTime? day, slot;
  final BookingQuote? quote;
  final List<Barber> barbers;
  final Map<String, List<DateTime>> slots;
  final bool loading, slotTaken;
  final Object? error;
}

class BookingController extends Notifier<BookingState> {
  int _revision = 0;
  @override
  BookingState build() => const BookingState();
  ShopContent get content => ref.read(appProvider).content!;
  BookingApi get api => ref.read(bookingApiProvider);
  void backTo(int step) {
    ++_revision;
    state = BookingState(
      step: step,
      service: state.service,
      barber: state.barber,
      day: state.day,
      barbers: state.barbers,
      slots: state.slots,
    );
  }

  Future<void> selectService(ShopService service) async {
    final revision = ++_revision;
    state = BookingState(step: 2, service: service, loading: true);
    try {
      final rows = await api.barbers(content.shop.slug, service.id);
      if (ref.mounted && _revision == revision) {
        state = BookingState(step: 2, service: service, barbers: rows);
      }
    } catch (e) {
      if (ref.mounted && _revision == revision) {
        state = BookingState(step: 2, service: service, error: e);
      }
    }
  }

  Future<void> selectBarber(Barber barber) async {
    final now = bogota(ref.read(clockProvider)());
    await selectDay(DateTime.utc(now.year, now.month, now.day), barber: barber);
  }

  Future<void> selectDay(
    DateTime day, {
    Barber? barber,
    bool slotTaken = false,
  }) async {
    final revision = ++_revision;
    final service = state.service!;
    final selected = barber ?? state.barber!;
    state = BookingState(
      step: 3,
      service: service,
      barber: selected,
      day: day,
      barbers: state.barbers,
      loading: true,
      slotTaken: slotTaken,
    );
    try {
      final slots = await api.slots(
        content.shop.slug,
        service.id,
        selected.id,
        day,
      );
      if (ref.mounted && revision == _revision) {
        state = BookingState(
          step: 3,
          service: service,
          barber: selected,
          day: day,
          barbers: state.barbers,
          slots: slots,
          slotTaken: slotTaken,
        );
      }
    } catch (e) {
      if (ref.mounted && revision == _revision) {
        state = BookingState(
          step: 3,
          service: service,
          barber: selected,
          day: day,
          barbers: state.barbers,
          error: e,
          slotTaken: slotTaken,
        );
      }
    }
  }

  Future<void> selectSlot(DateTime slot) async {
    final revision = ++_revision;
    final old = state;
    state = BookingState(
      step: 3,
      service: old.service,
      barber: old.barber,
      day: old.day,
      slot: slot,
      barbers: old.barbers,
      slots: old.slots,
      loading: true,
    );
    try {
      final quote = await api.quote(
        content.shop.slug,
        old.service!.id,
        old.barber!.id,
        slot,
      );
      if (ref.mounted && revision == _revision) {
        state = BookingState(
          step: 3,
          service: old.service,
          barber: old.barber,
          day: old.day,
          slot: slot,
          quote: quote,
          barbers: old.barbers,
          slots: old.slots,
        );
      }
    } catch (e) {
      if (!ref.mounted || revision != _revision) return;
      if (e is DioException && e.response?.statusCode == 409) {
        await selectDay(old.day!, slotTaken: true);
      } else {
        state = BookingState(
          step: 3,
          service: old.service,
          barber: old.barber,
          day: old.day,
          barbers: old.barbers,
          slots: old.slots,
          error: e,
        );
      }
    }
  }

  Future<Appointment?> confirm() async {
    if (state.loading || state.quote == null) return null;
    final old = state;
    state = BookingState(
      step: 3,
      service: old.service,
      barber: old.barber,
      day: old.day,
      slot: old.slot,
      quote: old.quote,
      barbers: old.barbers,
      slots: old.slots,
      loading: true,
    );
    try {
      final result = await api.create(
        content,
        old.service!,
        old.barber!,
        old.slot!,
        old.quote!,
      );
      if (!ref.mounted) return null;
      return result;
    } catch (e) {
      if (!ref.mounted) return null;
      final detail = e is DioException && e.response?.data is Map
          ? (e.response!.data as Map)['detail']?.toString().toLowerCase() ?? ''
          : '';
      if (e is DioException &&
          e.response?.statusCode == 409 &&
          RegExp('horario|ocupado|tomado').hasMatch(detail)) {
        await selectDay(old.day!, slotTaken: true);
      } else {
        state = BookingState(
          step: 3,
          service: old.service,
          barber: old.barber,
          day: old.day,
          slot: old.slot,
          quote: old.quote,
          barbers: old.barbers,
          slots: old.slots,
          error: e,
        );
      }
      return null;
    }
  }
}

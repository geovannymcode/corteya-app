import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state.dart';
import '../booking/models.dart';
import 'models.dart';

final staffApiProvider = Provider<StaffApi>(
  (ref) => StaffApi(ref.watch(apiProvider)),
);

class StaffApi {
  StaffApi(this.dio);
  final Dio dio;
  String path(String slug) =>
      '/api/v1/barbershops/${Uri.encodeComponent(slug)}/staff';
  Future<List<StaffAppointment>> agenda(
    String slug,
    DateTime day,
    String? barber,
    CancelToken cancel,
  ) async {
    final r = await dio.get<List<dynamic>>(
      '${path(slug)}/agenda',
      queryParameters: {'date': dateKey(day), 'barberId': ?barber},
      cancelToken: cancel,
    );
    return r.data!.map((j) => StaffAppointment.fromJson(objectMap(j))).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<List<TimeBlock>> blocks(
    String slug,
    DateTime day,
    CancelToken cancel,
  ) async {
    final from = '${dateKey(day)}T00:00:00-05:00';
    final to = '${dateKey(day.add(const Duration(days: 1)))}T00:00:00-05:00';
    final r = await dio.get<List<dynamic>>(
      '${path(slug)}/time-off',
      queryParameters: {'from': from, 'to': to},
      cancelToken: cancel,
    );
    return r.data!.map((j) => TimeBlock.fromJson(objectMap(j))).toList();
  }

  Future<ActionItems> actions(String slug, CancelToken cancel) async =>
      ActionItems.fromJson(
        (await dio.get<Map<String, dynamic>>(
          '${path(slug)}/action-items',
          cancelToken: cancel,
        )).data!,
      );
  Future<Map<String, dynamic>> summary(
    String slug,
    String period,
    DateTime day,
    CancelToken cancel,
  ) async => (await dio.get<Map<String, dynamic>>(
    '${path(slug)}/summary',
    queryParameters: {'period': period, 'date': dateKey(day)},
    cancelToken: cancel,
  )).data!;
  Future<void> act(
    String slug,
    String id,
    String action, {
    String? reason,
  }) async {
    await dio.post<dynamic>(
      '${path(slug)}/appointments/${Uri.encodeComponent(id)}/$action',
      data: reason == null ? null : {'reason': reason},
    );
  }

  Future<void> manual(String slug, Map<String, dynamic> body) async {
    await dio.post<dynamic>('${path(slug)}/appointments', data: body);
  }

  Future<void> block(String slug, Map<String, dynamic> body) async {
    await dio.post<dynamic>('${path(slug)}/time-off', data: body);
  }

  Future<void> deleteBlock(String slug, String id) async {
    await dio.delete<dynamic>(
      '${path(slug)}/time-off/${Uri.encodeComponent(id)}',
    );
  }
}

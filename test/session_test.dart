import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corteya/core/api.dart';
import 'package:corteya/core/storage.dart';

class MemoryStore extends TokenStore {
  Tokens? value = const Tokens('old-access', 'old-refresh');
  int clears = 0;
  @override
  Future<Tokens?> read() async => value;
  @override
  Future<void> write(Tokens tokens) async {
    value = tokens;
  }

  @override
  Future<void> clear() async {
    value = null;
    clears++;
  }
}

class Adapter implements HttpClientAdapter {
  Adapter(this.reply);
  final Future<ResponseBody> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => reply(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(String data, int status) => ResponseBody.fromString(
  data,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
void main() {
  test('El logger nunca incluye tokens, teléfonos, OTP ni URLs', () async {
    final output = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(SafeDevLogger(output.add));
    dio.httpClientAdapter = Adapter(
      (request) async => jsonBody('{"accessToken":"secret-response"}', 200),
    );
    await dio.post<dynamic>(
      '/otp/3123456789',
      data: {'phone': '3123456789', 'code': '123456'},
      options: Options(headers: {'Authorization': 'Bearer secret-request'}),
    );
    expect(output, ['HTTP POST', 'HTTP 200']);
    dio.close();
  });
  test(
    'Un 401 público de OTP no intenta refrescar ni destruye otra sesión',
    () async {
      final store = MemoryStore();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      final refresh = Dio(dio.options.copyWith());
      var calls = 0;
      dio.httpClientAdapter = Adapter((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return jsonBody('{}', 401);
      });
      refresh.httpClientAdapter = Adapter((request) async {
        calls++;
        return jsonBody('{}', 401);
      });
      dio.interceptors.add(
        SessionInterceptor(
          dio: dio,
          refreshDio: refresh,
          store: store,
          onExpired: () {},
        ),
      );
      await expectLater(
        dio.post<dynamic>(
          '/api/v1/auth/otp/verify',
          options: Options(extra: {'public': true}),
        ),
        throwsA(isA<DioException>()),
      );
      expect(calls, 0);
      expect(store.value, isNotNull);
      dio.close();
      refresh.close();
    },
  );
  test('Cerrar sesión durante un refresh no restaura credenciales', () async {
    final store = MemoryStore();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final refresh = Dio(dio.options.copyWith());
    final started = Completer<void>();
    final proceed = Completer<void>();
    dio.httpClientAdapter = Adapter((request) async => jsonBody('{}', 401));
    refresh.httpClientAdapter = Adapter((request) async {
      started.complete();
      await proceed.future;
      return jsonBody(
        '{"accessToken":"new-access","refreshToken":"new-refresh"}',
        200,
      );
    });
    final interceptor = SessionInterceptor(
      dio: dio,
      refreshDio: refresh,
      store: store,
      onExpired: () {},
    );
    dio.interceptors.add(interceptor);
    final request = dio
        .get<dynamic>('/private')
        .then<void>((_) {}, onError: (Object _) {});
    await started.future;
    await interceptor.clear();
    proceed.complete();
    await request;
    expect(store.value, isNull);
    expect(await interceptor.credentials(), isNull);
    dio.close();
    refresh.close();
  });
  for (final fails in [false, true]) {
    test('Tres 401 simultáneos: un refresh; falla=$fails', () async {
      final store = MemoryStore();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      final refresh = Dio(dio.options.copyWith());
      final gate = Completer<void>();
      var oldRequests = 0;
      var refreshes = 0;
      var retries = 0;
      var expirations = 0;
      dio.httpClientAdapter = Adapter((request) async {
        if (request.headers['Authorization'] == 'Bearer old-access') {
          oldRequests++;
          if (oldRequests == 3) gate.complete();
          await gate.future;
          return jsonBody('{}', 401);
        }
        expect(request.headers['Authorization'], 'Bearer new-access');
        retries++;
        return jsonBody('{"ok":true}', 200);
      });
      refresh.httpClientAdapter = Adapter((request) async {
        refreshes++;
        expect(request.data, {'refreshToken': 'old-refresh'});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonBody(
          fails
              ? '{}'
              : '{"accessToken":"new-access","refreshToken":"new-refresh"}',
          fails ? 401 : 200,
        );
      });
      dio.interceptors.add(
        SessionInterceptor(
          dio: dio,
          refreshDio: refresh,
          store: store,
          onExpired: () => expirations++,
        ),
      );
      final results = await Future.wait(
        List.generate(3, (i) async {
          try {
            return (await dio.get<dynamic>('/request/$i')).statusCode;
          } on DioException {
            return 401;
          }
        }),
      );
      expect(refreshes, 1);
      expect(oldRequests, 3);
      if (fails) {
        expect(store.value, isNull);
        expect(store.clears, 1);
        expect(expirations, 1);
        expect(retries, 0);
        expect(results, [401, 401, 401]);
      } else {
        expect(retries, 3);
        expect(results, [200, 200, 200]);
        expect(store.value!.refreshToken, 'new-refresh');
        expect(expirations, 0);
      }
      dio.close();
      refresh.close();
    });
  }
  test('401 tardío reusa token nuevo sin rotar otra vez', () async {
    final store = MemoryStore();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final refresh = Dio(dio.options.copyWith());
    final rotated = Completer<void>();
    var calls = 0;
    refresh.httpClientAdapter = Adapter((request) async {
      calls++;
      return jsonBody(
        '{"accessToken":"new-access","refreshToken":"new-refresh"}',
        200,
      );
    });
    dio.httpClientAdapter = Adapter((request) async {
      if (request.headers['Authorization'] == 'Bearer old-access') {
        if (request.path == '/slow') await rotated.future;
        return jsonBody('{}', 401);
      }
      if (!rotated.isCompleted) rotated.complete();
      return jsonBody('{}', 200);
    });
    dio.interceptors.add(
      SessionInterceptor(
        dio: dio,
        refreshDio: refresh,
        store: store,
        onExpired: () {},
      ),
    );
    await Future.wait([dio.get<dynamic>('/fast'), dio.get<dynamic>('/slow')]);
    expect(calls, 1);
    dio.close();
    refresh.close();
  });
}

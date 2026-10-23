import 'dart:async';

import 'package:dio/dio.dart';

import 'storage.dart';

class SessionInterceptor extends Interceptor {
  SessionInterceptor({
    required this.dio,
    required this.refreshDio,
    required this.store,
    required this.onExpired,
  });
  final Dio dio;
  final Dio refreshDio;
  final TokenStore store;
  final void Function() onExpired;
  Future<Tokens>? _refreshing;
  Tokens? _tokens;
  bool _loaded = false;
  Future<Tokens?>? _loading;
  int _generation = 0;
  Future<void> _storageQueue = Future<void>.value();
  Future<void> _persist(Future<void> Function() operation) {
    final next = _storageQueue.then((_) => operation());
    _storageQueue = next.catchError((Object _) {});
    return next;
  }

  Future<Tokens?> credentials() async {
    if (_loaded) return _tokens;
    return _loading ??= _load();
  }

  Future<Tokens?> _load() async {
    final generation = _generation;
    final tokens = await store.read();
    if (_generation == generation) {
      _tokens = tokens;
      _loaded = true;
    }
    return _tokens;
  }

  Future<void> waitForRefresh() async {
    final pending = _refreshing;
    if (pending != null) await pending;
  }

  Future<void> establish(Tokens tokens) async {
    final generation = _generation;
    await _persist(() => store.write(tokens));
    if (_generation != generation) throw StateError("Session changed");
    _tokens = tokens;
    _loaded = true;
    _generation++;
  }

  Future<void> clear() async {
    _generation++;
    _tokens = null;
    _loaded = true;
    await _persist(store.clear);
  }

  bool _public(RequestOptions options) => options.extra['public'] == true;
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      if (!_public(options)) {
        options.headers.remove('Authorization');
        final tokens = await credentials();
        if (tokens != null) {
          options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
        }
      }
      handler.next(options);
    } catch (_) {
      handler.reject(DioException(requestOptions: options));
    }
  }

  Future<Tokens> _refresh(Tokens old, int generation) async {
    try {
      final result = await refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': old.refreshToken},
      );
      if (_generation != generation) throw StateError('Session changed');
      final tokens = Tokens.fromJson(result.data!);
      await establish(tokens);
      return tokens;
    } catch (_) {
      if (_generation == generation) {
        try {
          await clear();
        } finally {
          onExpired();
        }
      }
      rethrow;
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final error = err;
    final request = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        _public(request) ||
        request.extra['retried'] == true) {
      handler.next(error);
      return;
    }
    try {
      final current = await credentials();
      if (current == null) {
        handler.next(error);
        return;
      }
      Tokens updated;
      if (request.headers['Authorization'] != 'Bearer ${current.accessToken}') {
        updated =
            current; // A delayed 401 already has a rotated token available.
      } else {
        final pending = _refreshing ??= _refresh(current, _generation);
        try {
          updated = await pending;
        } finally {
          if (identical(_refreshing, pending)) _refreshing = null;
        }
      }
      request.extra['retried'] = true;
      request.headers['Authorization'] = 'Bearer ${updated.accessToken}';
      handler.resolve(await dio.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(error);
    }
  }
}

/// Never log URLs, bodies, headers or exception objects: they can contain PII.
class SafeDevLogger extends LogInterceptor {
  SafeDevLogger(this.output)
    : super(
        request: false,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        error: false,
        logPrint: _discard,
      );
  final void Function(String) output;
  static void _discard(Object value) {}
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    output('HTTP ${options.method}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    output('HTTP ${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    output('HTTP ${err.response?.statusCode ?? "sin conexión"}');
    handler.next(err);
  }
}

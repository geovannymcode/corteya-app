import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/profile.dart';
import '../barbershop/models.dart';
import '../core/api.dart';
import '../core/storage.dart';
import 'config.dart';

final configProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
final preferencesProvider = Provider<ShopPreferences>(
  (ref) => ShopPreferences(),
);
final apiProvider = Provider<Dio>((ref) {
  final config = ref.watch(configProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  final refresh = Dio(dio.options.copyWith());
  final session = SessionInterceptor(
    dio: dio,
    refreshDio: refresh,
    store: ref.watch(tokenStoreProvider),
    onExpired: () => ref.read(appProvider.notifier).expire(),
  );
  dio.interceptors.add(session);
  if (kDebugMode && config.environment == 'dev') {
    dio.interceptors.add(SafeDevLogger((message) => debugPrint(message)));
  }
  ref.onDispose(() {
    dio.close();
    refresh.close();
  });
  return dio;
});
final sessionProvider = Provider<SessionInterceptor>(
  (ref) =>
      ref.watch(apiProvider).interceptors.whereType<SessionInterceptor>().first,
);
final appProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppState {
  const AppState({
    this.content,
    this.profile,
    this.ready = false,
    this.message,
    this.startupError,
  });
  final ShopContent? content;
  final Profile? profile;
  final bool ready;
  final String? message;
  final Object? startupError;
}

class AppController extends Notifier<AppState> {
  int _selection = 0;
  @override
  AppState build() => const AppState();
  Dio get api => ref.read(apiProvider);
  Future<void> start() async {
    state = AppState(content: state.content, profile: state.profile);
    try {
      if (await ref.read(sessionProvider).credentials() != null) {
        try {
          await loadProfile();
        } catch (_) {
          if (await ref.read(sessionProvider).credentials() != null) rethrow;
        }
      }
      final slug = await ref.read(preferencesProvider).read();
      if (slug != null) await selectShop(slug);
      state = AppState(
        content: state.content,
        profile: state.profile,
        ready: true,
        message: state.message,
      );
    } catch (error) {
      state = AppState(
        content: state.content,
        profile: state.profile,
        ready: true,
        message: state.message,
        startupError: error,
      );
    }
  }

  Future<void> selectShop(String slug) async {
    final selection = ++_selection;
    final path = '/api/v1/barbershops/${Uri.encodeComponent(slug)}';
    final response = await api.get<Map<String, dynamic>>(
      path,
      options: Options(extra: {'public': true}),
    );
    final shop = Barbershop.fromJson(response.data!);
    final serviceResponse = await api.get<List<dynamic>>(
      '$path/services',
      options: Options(extra: {'public': true}),
    );
    final services = serviceResponse.data!
        .map((v) => ShopService.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
    final responses = await Future.wait(
      services.map(
        (s) => api.get<List<dynamic>>(
          '$path/barbers',
          queryParameters: {'serviceId': s.id},
          options: Options(extra: {'public': true}),
        ),
      ),
    );
    final barbers = <String, Barber>{};
    for (final response in responses) {
      for (final value in response.data!) {
        final barber = Barber.fromJson(Map<String, dynamic>.from(value as Map));
        barbers[barber.id] = barber;
      }
    }
    if (_selection != selection) return;
    await ref.read(preferencesProvider).write(slug);
    if (_selection != selection) return;
    state = AppState(
      content: ShopContent(shop, services, barbers.values.toList()),
      profile: state.profile,
      ready: state.ready,
      message: state.message,
    );
  }

  Future<void> changeShop() async {
    ++_selection;
    await ref.read(preferencesProvider).write(null);
    state = AppState(profile: state.profile, ready: true);
  }

  Future<void> loadProfile() async {
    final response = await api.get<Map<String, dynamic>>('/api/v1/me');
    state = AppState(
      content: state.content,
      profile: Profile.fromJson(response.data!),
      ready: state.ready,
    );
  }

  Future<void> requestOtp(String phone) async {
    await api.post<dynamic>(
      '/api/v1/auth/otp/request',
      data: {'phone': '+57$phone'},
      options: Options(extra: {'public': true}),
    );
  }

  Future<void> verifyOtp(String phone, String code) async {
    final response = await api.post<Map<String, dynamic>>(
      '/api/v1/auth/otp/verify',
      data: {'phone': '+57$phone', 'code': code},
      options: Options(extra: {'public': true}),
    );
    await ref.read(sessionProvider).establish(Tokens.fromJson(response.data!));
    await loadProfile();
  }

  Future<void> rename(String name) async {
    await api.patch<dynamic>('/api/v1/me', data: {'name': name});
    await loadProfile();
  }

  void expire() => state = AppState(
    content: state.content,
    ready: true,
    message: 'Tu sesión terminó. Ingresa de nuevo para continuar.',
  );
  Future<void> logout() async {
    final session = ref.read(sessionProvider);
    try {
      await session.waitForRefresh();
      final tokens = await session.credentials();
      if (tokens != null) {
        await api.post<dynamic>(
          '/api/v1/auth/logout',
          data: {'refreshToken': tokens.refreshToken},
          options: Options(extra: {'public': true}),
        );
      }
    } finally {
      // Even without a network, closing the session removes local credentials.
      await session.clear();
      state = AppState(content: state.content, ready: true);
    }
  }

  Future<void> deleteAccount() async {
    await api.delete<dynamic>('/api/v1/me');
    await ref.read(sessionProvider).clear();
    state = AppState(content: state.content, ready: true);
  }
}

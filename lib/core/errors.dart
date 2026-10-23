import 'package:dio/dio.dart';

String userMessage(Object error) {
  if (error is DioException) {
    if ([
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ].contains(error.type)) {
      return 'Revisa tu conexión';
    }
    final body = error.response?.data;
    if (body is Map && body['detail'] is String) {
      final detail = (body['detail'] as String).trim();
      // Only backend-authored user-facing ProblemDetail messages are displayed.
      if (detail.isNotEmpty &&
          !detail.contains('\n') &&
          detail.length <= 500 &&
          !RegExp(
            r'(Exception|StackTrace|java\.|org\.springframework|SELECT |Bearer )',
            caseSensitive: false,
          ).hasMatch(detail)) {
        return detail;
      }
    }
    if (error.response?.statusCode == 404) {
      return 'No encontramos esa barbería. Revisa el código e intenta de nuevo.';
    }
    if (error.response?.statusCode == 401) {
      return 'Tu sesión terminó. Ingresa de nuevo para continuar.';
    }
    if (error.response?.statusCode == 429) {
      return 'Espera un momento antes de intentarlo de nuevo.';
    }
    if (error.response?.statusCode == 503) {
      return 'El servicio no está disponible en este momento. Intenta más tarde.';
    }
  }
  return 'No pudimos completar la solicitud. Intenta de nuevo.';
}

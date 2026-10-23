import 'dart:io';

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.appLinkHost,
    required this.environment,
  });
  final String apiBaseUrl;
  final String appLinkHost;
  final String environment;
  factory AppConfig.fromEnvironment() {
    const environment = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
    const configured = String.fromEnvironment('API_BASE_URL');
    final base = configured.isEmpty && environment == 'dev'
        ? (Platform.isAndroid
              ? 'http://10.0.2.2:8080'
              : 'http://localhost:8080')
        : configured;
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !uri.hasAuthority ||
        (environment != 'dev' && uri.scheme != 'https')) {
      throw StateError('Configura API_BASE_URL para este ambiente.');
    }
    return AppConfig(
      apiBaseUrl: base,
      appLinkHost: const String.fromEnvironment('APP_LINK_HOST'),
      environment: environment,
    );
  }
}

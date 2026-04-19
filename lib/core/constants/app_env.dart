class AppEnv {
  AppEnv._();

  static const String _baseUrl = 'https://api.smart-go.me';
  static const int apiTimeoutMs = 30000;

  static String get baseUrl => _baseUrl;
}

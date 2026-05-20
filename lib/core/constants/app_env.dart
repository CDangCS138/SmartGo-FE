class AppEnv {
  AppEnv._();

  static const String _baseUrl = 'https://api.smart-go.me';
  static const int apiTimeoutMs = 30000;
  static const bool encryptionEnabled =
      bool.fromEnvironment('ENCRYPTION_ENABLED', defaultValue: false);
  static const String encryptionSecret =
      String.fromEnvironment('ENCRYPTION_SECRET', defaultValue: '');
  static const String encryptionAlgorithm = String.fromEnvironment(
      'ENCRYPTION_ALGORITHM',
      defaultValue: 'aes-256-cbc');

  static String get baseUrl => _baseUrl;
}

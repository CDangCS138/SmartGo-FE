class AppConstants {
  static const double defaultLatitude = 10.8231;
  static const double defaultLongitude = 106.6297;
  static const double defaultZoom = 13.0;

  static const String themeKey = 'theme_mode';
  static const String languageKey = 'language_code';
  static const String authTokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user_data';
  static const String chatbotConversationHistoryKey =
      'chatbot_conversation_history';

  static const Duration searchDebounce = Duration(milliseconds: 500);

  static const int minSearchLength = 3;
  static const int maxSuggestions = 5;
}

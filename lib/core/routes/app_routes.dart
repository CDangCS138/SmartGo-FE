class AppRoutes {
  AppRoutes._();
  static const String login = '/login';
  static const String register = '/register';
  static const String onboarding = '/onboarding';
  static const String home = '/';
  static const String map = '/map';
  static const String liveMap = '/live-map';
  static const String routePlanning = '/route-planning';
  static const String pathFindingDemo = '/path-finding-demo';
  static const String routes = '/routes';
  static const String routeDetail = '/routes/:id';
  static const String settings = '/settings';
  static const String usersAdmin = '/settings/users';
  static const String themeSettings = '/settings/theme';
  static const String languageSettings = '/settings/language';
  static const String profile = '/profile';
  static const String chatbot = '/chatbot';
  static const String chatbotAdmin = '/settings/chatbot-admin';
  static const String momoPaymentCallback = '/payment/momo-callback';
  static const String vnpayPaymentCallback = '/payment/vnpay-callback';
  static const String momoPaymentCallbackApiCompat =
      '/api/v1/payments/momo/return';
  static const String vnpayPaymentCallbackApiCompat =
      '/api/v1/payments/vnpay/return';
}

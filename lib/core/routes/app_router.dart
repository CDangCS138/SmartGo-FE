import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/live_map/live_map_screen.dart';
import '../../presentation/screens/route_planning/route_planning_screen.dart';
import '../../presentation/screens/path_finding/path_finding_demo_screen.dart';
import '../../presentation/screens/bus_simulation/bus_simulation_screen.dart';
import '../../presentation/screens/map/map_screen_new.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/settings/theme_settings_screen.dart';
import '../../presentation/screens/settings/language_settings_screen.dart';
import '../../presentation/screens/users/users_admin_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/route/route_list_screen.dart';
import '../../presentation/screens/route/payment_callback_screen.dart';
import '../../presentation/screens/chatbot/chatbot_screen.dart';
import '../../presentation/screens/chatbot/chatbot_admin_screen.dart';
import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/blocs/auth/auth_state.dart';
import 'app_routes.dart';

class AppRouter {
  final AuthBloc authBloc;

  AppRouter({required this.authBloc});

  late final GoRouter router = GoRouter(
    initialLocation: AppRoutes.login,
    debugLogDiagnostics: false,
    redirect: _authGuard,
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.liveMap,
        name: 'live-map',
        builder: (context, state) => const LiveMapScreen(),
      ),
      GoRoute(
        path: AppRoutes.routes,
        name: 'routes',
        builder: (context, state) => const RouteListScreen(),
      ),
      GoRoute(
        path: AppRoutes.routePlanning,
        name: 'route-planning',
        builder: (context, state) => const RoutePlanningScreen(),
      ),
      GoRoute(
        path: AppRoutes.pathFindingDemo,
        name: 'path-finding-demo',
        builder: (context, state) => const PathFindingDemoScreen(),
      ),
      GoRoute(
        path: AppRoutes.busSimulations,
        name: 'bus-simulations',
        builder: (context, state) => BusSimulationScreen(
          initialRouteId: state.uri.queryParameters['routeId'],
          initialTripId: state.uri.queryParameters['tripId'],
          initialStationId: state.uri.queryParameters['stationId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.map,
        name: 'map',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.chatbot,
        name: 'chatbot',
        builder: (context, state) => const ChatbotScreen(),
      ),
      GoRoute(
        path: AppRoutes.momoPaymentCallback,
        name: 'momo-payment-callback',
        builder: (context, state) => PaymentCallbackScreen(
          provider: 'momo',
          callbackParams: state.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: AppRoutes.vnpayPaymentCallback,
        name: 'vnpay-payment-callback',
        builder: (context, state) => PaymentCallbackScreen(
          provider: 'vnpay',
          callbackParams: state.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: AppRoutes.momoPaymentCallbackApiCompat,
        name: 'momo-payment-callback-api-compat',
        builder: (context, state) => PaymentCallbackScreen(
          provider: 'momo',
          callbackParams: state.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: AppRoutes.vnpayPaymentCallbackApiCompat,
        name: 'vnpay-payment-callback-api-compat',
        builder: (context, state) => PaymentCallbackScreen(
          provider: 'vnpay',
          callbackParams: state.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'theme',
            name: 'theme-settings',
            builder: (context, state) => const ThemeSettingsScreen(),
          ),
          GoRoute(
            path: 'language',
            name: 'language-settings',
            builder: (context, state) => const LanguageSettingsScreen(),
          ),
          GoRoute(
            path: 'users',
            name: 'users-admin',
            builder: (context, state) => const UsersAdminScreen(),
          ),
          GoRoute(
            path: 'chatbot-admin',
            name: 'chatbot-admin',
            builder: (context, state) => const ChatbotAdminScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
  String? _authGuard(BuildContext context, GoRouterState state) {
    final currentPath = _normalizePath(state.uri.path);

    if (currentPath == '/api/v1/auth/google/callback') {
      final query = state.uri.query;
      return query.isEmpty ? AppRoutes.login : '${AppRoutes.login}?$query';
    }

    if (currentPath != state.uri.path) {
      final query = state.uri.query;
      return query.isEmpty ? currentPath : '$currentPath?$query';
    }

    if (currentPath == AppRoutes.momoPaymentCallbackApiCompat) {
      final query = state.uri.query;
      return query.isEmpty
          ? AppRoutes.momoPaymentCallback
          : '${AppRoutes.momoPaymentCallback}?$query';
    }

    if (currentPath == AppRoutes.vnpayPaymentCallbackApiCompat) {
      final query = state.uri.query;
      return query.isEmpty
          ? AppRoutes.vnpayPaymentCallback
          : '${AppRoutes.vnpayPaymentCallback}?$query';
    }

    final isAuthenticated = authBloc.state is AuthAuthenticated;
    final isLoginRoute = currentPath == AppRoutes.login;
    final isRegisterRoute = currentPath == AppRoutes.register;
    final isPaymentCallbackRoute =
        currentPath == AppRoutes.momoPaymentCallback ||
            currentPath == AppRoutes.vnpayPaymentCallback ||
            currentPath == AppRoutes.momoPaymentCallbackApiCompat ||
            currentPath == AppRoutes.vnpayPaymentCallbackApiCompat;

    // If not authenticated and trying to access protected route, redirect to login
    if (!isAuthenticated &&
        !isLoginRoute &&
        !isRegisterRoute &&
        !isPaymentCallbackRoute) {
      return AppRoutes.login;
    }

    // If authenticated and trying to access login/register, redirect to home
    if (isAuthenticated && (isLoginRoute || isRegisterRoute)) {
      return AppRoutes.home;
    }

    return null;
  }

  String _normalizePath(String rawPath) {
    var normalizedPath = rawPath;

    if (normalizedPath.length > 1 && normalizedPath.endsWith('/')) {
      normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
    }

    // Support legacy auth links so users do not hit notfound.
    if (normalizedPath == '/auth/login' || normalizedPath == '/signin') {
      return AppRoutes.login;
    }

    return normalizedPath;
  }
}

// Helper class to refresh GoRouter when auth state changes
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (AuthState state) {
        notifyListeners();
      },
    );
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

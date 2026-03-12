import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/live_map/live_map_screen.dart';
import '../../presentation/screens/route_planning/route_planning_screen.dart';
import '../../presentation/screens/path_finding/path_finding_demo_screen.dart';
import '../../presentation/screens/map/map_screen_new.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/settings/theme_settings_screen.dart';
import '../../presentation/screens/settings/language_settings_screen.dart';
import '../../presentation/screens/route/route_list_screen.dart';
import '../../presentation/blocs/auth/auth_bloc.dart';
import '../../presentation/blocs/auth/auth_state.dart';
import 'app_routes.dart';

class AppRouter {
  final AuthBloc authBloc;

  AppRouter({required this.authBloc});

  late final GoRouter router = GoRouter(
    initialLocation: AppRoutes.login,
    debugLogDiagnostics: true,
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
        path: AppRoutes.map,
        name: 'map',
        builder: (context, state) => const MapScreen(),
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
    final isAuthenticated = authBloc.state is AuthAuthenticated;
    final isLoginRoute = state.matchedLocation == AppRoutes.login;
    final isRegisterRoute = state.matchedLocation == AppRoutes.register;

    // If not authenticated and trying to access protected route, redirect to login
    if (!isAuthenticated && !isLoginRoute && !isRegisterRoute) {
      return AppRoutes.login;
    }

    // If authenticated and trying to access login/register, redirect to home
    if (isAuthenticated && (isLoginRoute || isRegisterRoute)) {
      return AppRoutes.home;
    }

    return null;
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartgo/l10n/app_localizations.dart';
import 'package:url_strategy/url_strategy.dart';
import 'core/services/storage_service.dart';
import 'core/services/preload_service.dart';
import 'core/di/injection.dart';
import 'core/logging/app_logger.dart';
import 'core/themes/app_themes.dart';
import 'core/routes/app_router.dart';
import 'presentation/blocs/theme/theme_bloc.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/auth/auth_event.dart';
import 'presentation/blocs/route/route_bloc.dart';
import 'presentation/blocs/station/station_bloc.dart';
import 'presentation/screens/error_app.dart';
import 'core/enums/theme_mode.dart' as app_theme;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();
  try {
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs);
    AppLogger.info('SharedPreferences initialized');
    await configureDependencies();
    AppLogger.info('Dependency injection configured');
    final preloadService = getIt<PreloadService>();
    await preloadService.preloadAll();
    AppLogger.info('Initial route and station preload triggered');
    runApp(MyApp(storageService: storageService));
  } catch (e, stackTrace) {
    AppLogger.error('Failed to initialize app', e, stackTrace);
    runApp(const ErrorApp());
  }
}

class MyApp extends StatefulWidget {
  final StorageService storageService;
  const MyApp({
    super.key,
    required this.storageService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ThemeBloc _themeBloc;
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _themeBloc = ThemeBloc(widget.storageService)..add(const ThemeLoaded());
    getIt<AuthBloc>().add(const CheckAuthStatusEvent());
    _appRouter = AppRouter(authBloc: getIt<AuthBloc>());
  }

  @override
  void dispose() {
    _themeBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _themeBloc),
        BlocProvider.value(value: getIt<AuthBloc>()),
        BlocProvider.value(value: getIt<RouteBloc>()),
        BlocProvider.value(value: getIt<StationBloc>()),
      ],
      child: BlocBuilder<ThemeBloc, ThemeState>(
        bloc: _themeBloc,
        builder: (context, themeState) {
          return MaterialApp.router(
            title: 'SmartGo',
            debugShowCheckedModeBanner: false,
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: _getThemeMode(themeState.themeMode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            routerConfig: _appRouter.router,
          );
        },
      ),
    );
  }

  ThemeMode _getThemeMode(app_theme.ThemeMode mode) {
    switch (mode) {
      case app_theme.ThemeMode.light:
        return ThemeMode.light;
      case app_theme.ThemeMode.dark:
        return ThemeMode.dark;
      case app_theme.ThemeMode.system:
        return ThemeMode.system;
    }
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:dio/dio.dart' as _i361;
import 'package:get_it/get_it.dart' as _i174;
import 'package:http/http.dart' as _i519;
import 'package:injectable/injectable.dart' as _i526;
import 'package:shared_preferences/shared_preferences.dart' as _i460;

import '../../data/datasources/auth_remote_data_source.dart' as _i716;
import '../../data/datasources/route_remote_data_source.dart' as _i366;
import '../../data/datasources/station_remote_data_source.dart' as _i400;
import '../../data/repositories/auth_repository_impl.dart' as _i895;
import '../../data/repositories/route_repository_impl.dart' as _i589;
import '../../data/repositories/station_repository_impl.dart' as _i70;
import '../../domain/repositories/auth_repository.dart' as _i1073;
import '../../domain/repositories/route_repository.dart' as _i872;
import '../../domain/repositories/station_repository.dart' as _i248;
import '../../domain/usecases/find_path_usecase.dart' as _i478;
import '../../domain/usecases/get_current_user_usecase.dart' as _i771;
import '../../domain/usecases/login_usecase.dart' as _i253;
import '../../domain/usecases/logout_usecase.dart' as _i981;
import '../../domain/usecases/refresh_token_usecase.dart' as _i755;
import '../../domain/usecases/register_usecase.dart' as _i35;
import '../../presentation/blocs/auth/auth_bloc.dart' as _i141;
import '../../presentation/blocs/route/route_bloc.dart' as _i217;
import '../../presentation/blocs/station/station_bloc.dart' as _i565;
import '../services/authenticated_http_client.dart' as _i484;
import '../services/preload_service.dart' as _i637;
import '../services/route_geometry_service.dart' as _i1035;
import '../services/storage_service.dart' as _i306;
import 'register_module.dart' as _i291;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final registerModule = _$RegisterModule();
    await gh.factoryAsync<_i460.SharedPreferences>(
      () => registerModule.sharedPreferences,
      preResolve: true,
    );
    gh.lazySingleton<_i361.Dio>(() => registerModule.dio);
    gh.lazySingleton<_i306.StorageService>(
        () => _i306.StorageService(gh<_i460.SharedPreferences>()));
    gh.lazySingleton<_i519.Client>(
      () => registerModule.innerHttpClient,
      instanceName: 'innerClient',
    );
    gh.lazySingleton<_i1035.RouteGeometryService>(
        () => _i1035.RouteGeometryService(gh<_i361.Dio>()));
    gh.lazySingleton<_i519.Client>(() => _i484.AuthenticatedHttpClient(
          gh<_i519.Client>(instanceName: 'innerClient'),
          gh<_i306.StorageService>(),
        ));
    gh.lazySingleton<_i716.AuthRemoteDataSource>(
        () => _i716.AuthRemoteDataSourceImpl(client: gh<_i519.Client>()));
    gh.lazySingleton<_i1073.AuthRepository>(() => _i895.AuthRepositoryImpl(
          remoteDataSource: gh<_i716.AuthRemoteDataSource>(),
          storageService: gh<_i306.StorageService>(),
        ));
    gh.lazySingleton<_i366.RouteRemoteDataSource>(
        () => _i366.RouteRemoteDataSourceImpl(client: gh<_i519.Client>()));
    gh.lazySingleton<_i400.StationRemoteDataSource>(
        () => _i400.StationRemoteDataSourceImpl(client: gh<_i519.Client>()));
    gh.factory<_i771.GetCurrentUserUseCase>(
        () => _i771.GetCurrentUserUseCase(gh<_i1073.AuthRepository>()));
    gh.factory<_i253.LoginUseCase>(
        () => _i253.LoginUseCase(gh<_i1073.AuthRepository>()));
    gh.factory<_i981.LogoutUseCase>(
        () => _i981.LogoutUseCase(gh<_i1073.AuthRepository>()));
    gh.factory<_i755.RefreshTokenUseCase>(
        () => _i755.RefreshTokenUseCase(gh<_i1073.AuthRepository>()));
    gh.factory<_i35.RegisterUseCase>(
        () => _i35.RegisterUseCase(gh<_i1073.AuthRepository>()));
    gh.lazySingleton<_i141.AuthBloc>(() => _i141.AuthBloc(
          loginUseCase: gh<_i253.LoginUseCase>(),
          registerUseCase: gh<_i35.RegisterUseCase>(),
          logoutUseCase: gh<_i981.LogoutUseCase>(),
          getCurrentUserUseCase: gh<_i771.GetCurrentUserUseCase>(),
          refreshTokenUseCase: gh<_i755.RefreshTokenUseCase>(),
          authRepository: gh<_i1073.AuthRepository>(),
        ));
    gh.lazySingleton<_i872.RouteRepository>(() => _i589.RouteRepositoryImpl(
        remoteDataSource: gh<_i366.RouteRemoteDataSource>()));
    gh.lazySingleton<_i248.StationRepository>(() => _i70.StationRepositoryImpl(
        remoteDataSource: gh<_i400.StationRemoteDataSource>()));
    gh.lazySingleton<_i565.StationBloc>(
        () => _i565.StationBloc(repository: gh<_i248.StationRepository>()));
    gh.lazySingleton<_i217.RouteBloc>(
        () => _i217.RouteBloc(repository: gh<_i872.RouteRepository>()));
    gh.factory<_i478.FindPathUseCase>(
        () => _i478.FindPathUseCase(gh<_i872.RouteRepository>()));
    gh.lazySingleton<_i637.PreloadService>(() => _i637.PreloadService(
          routeBloc: gh<_i217.RouteBloc>(),
          stationBloc: gh<_i565.StationBloc>(),
        ));
    return this;
  }
}

class _$RegisterModule extends _i291.RegisterModule {}

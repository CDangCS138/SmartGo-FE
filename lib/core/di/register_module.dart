import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../network/http_client_factory.dart';

/// Register external dependencies
@module
abstract class RegisterModule {
  /// Inner HTTP client (not authenticated)
  @Named('innerClient')
  @lazySingleton
  http.Client get innerHttpClient => createInnerHttpClient();

  @lazySingleton
  Dio get dio => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  @preResolve
  Future<SharedPreferences> get sharedPreferences =>
      SharedPreferences.getInstance();
}

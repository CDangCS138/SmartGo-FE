import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/storage_service.dart';

class AuthInterceptor extends Interceptor {
  StorageService? _storageService;
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_storageService == null) {
      final prefs = await SharedPreferences.getInstance();
      _storageService = StorageService(prefs);
    }
    final token = _storageService!.getAuthToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      if (_storageService != null) {
        await _storageService!.clearAuthToken();
      }
    }
    handler.next(err);
  }
}

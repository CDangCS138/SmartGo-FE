import 'package:dio/dio.dart';

import '../../errors/exceptions.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        throw const NetworkException('Connection timeout');
      case DioExceptionType.badResponse:
        throw ServerException(_handleStatusCode(err.response?.statusCode));
      case DioExceptionType.cancel:
        throw const CacheException('Request cancelled');
      default:
        throw const NetworkException('Network error occurred');
    }
  }

  String _handleStatusCode(int? statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not found';
      case 500:
        return 'Internal server error';
      default:
        return 'Unknown error occurred';
    }
  }
}

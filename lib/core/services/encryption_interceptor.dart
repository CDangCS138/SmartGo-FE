import 'dart:convert';
import 'package:dio/dio.dart';
import '../constants/app_env.dart';
import 'encryption_service.dart';

class EncryptionInterceptor extends Interceptor {
  final EncryptionService _service;
  EncryptionInterceptor(this._service);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    try {
      if (!AppEnv.encryptionEnabled) {
        return handler.next(response);
      }
      final contentType = response.headers.value('content-type') ?? '';
      final status = response.statusCode ?? 0;
      if (contentType.contains('text/event-stream')) {
        return handler.next(response);
      }
      if (status >= 300 && status < 400) return handler.next(response);
      if (response.requestOptions.responseType == ResponseType.stream) {
        return handler.next(response);
      }
      final data = response.data;
      Map<String, dynamic>? wrapped;
      if (data is Map<String, dynamic>) {
        wrapped = data;
      } else if (data is String) {
        try {
          final decoded = json.decode(data);
          if (decoded is Map<String, dynamic>) wrapped = decoded;
        } catch (_) {}
      }
      if (wrapped != null) {
        // Giải mã nếu nằm ở ngoài cùng
        if (_service.looksLikeWrapped(wrapped)) {
          final decrypted = await _service.tryDecryptWrappedAsync(wrapped);
          if (decrypted != null) response.data = decrypted;
        }
        // Giải mã nếu bọc bên trong trường 'data'
        else if (wrapped['data'] is Map<String, dynamic> &&
            _service.looksLikeWrapped(wrapped['data'])) {
          final decrypted =
              await _service.tryDecryptWrappedAsync(wrapped['data']);
          if (decrypted != null) {
            wrapped['data'] = decrypted;
            response.data = wrapped;
          }
        }
      }
      handler.next(response);
    } catch (e) {
      try {} catch (_) {}
      handler.next(response);
    }
  }
}

void configureDioForEncryption(Dio dio) {
  if (AppEnv.encryptionEnabled) {
    dio.interceptors.add(EncryptionInterceptor(EncryptionService()));
  }
}

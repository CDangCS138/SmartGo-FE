import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../constants/app_env.dart';
import 'storage_service.dart';

/// HTTP client that automatically adds authentication token to requests
/// and handles token refresh on 401 responses.
@LazySingleton(as: http.Client)
class AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final StorageService _storageService;
  static String get _baseUrl => AppEnv.baseUrl;

  bool _isRefreshing = false;

  AuthenticatedHttpClient(
    @Named('innerClient') this._inner,
    this._storageService,
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _storageService.getAuthToken();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (!request.headers.containsKey('Content-Type')) {
      request.headers['Content-Type'] = 'application/json';
    }

    final response = await _inner.send(request);

    // Intercept 401 – try to refresh token then retry once
    if (response.statusCode == 401 && !_isRefreshing && token != null) {
      final newToken = await _tryRefreshToken(token);
      if (newToken != null) {
        final retryRequest = _copyRequest(request, newToken);
        if (retryRequest != null) {
          return _inner.send(retryRequest);
        }
      }
    }

    return response;
  }

  Future<String?> _tryRefreshToken(String currentToken) async {
    _isRefreshing = true;
    try {
      final response = await _inner.post(
        Uri.parse('$_baseUrl/api/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'accessToken': currentToken}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        final data = jsonData['data'] as Map<String, dynamic>? ?? jsonData;
        final newToken = data['accessToken'] as String?;
        if (newToken != null) {
          await _storageService.saveAuthToken(newToken);
          final newRefresh = data['refreshToken'] as String?;
          if (newRefresh != null) {
            await _storageService.saveRefreshToken(newRefresh);
          }
          return newToken;
        }
      } else {
        // Refresh token itself is expired – clear credentials
        await _storageService.clearAuthToken();
        await _storageService.clearRefreshToken();
      }
    } catch (_) {
      // Network error during refresh – do nothing, return null
    } finally {
      _isRefreshing = false;
    }
    return null;
  }

  /// Creates a copy of [original] with the new [token] in the Authorization header.
  /// Only supports [http.Request] (standard GET/POST/etc with string body).
  http.BaseRequest? _copyRequest(http.BaseRequest original, String token) {
    if (original is http.Request) {
      final copy = http.Request(original.method, original.url);
      copy.headers.addAll(original.headers);
      copy.headers['Authorization'] = 'Bearer $token';
      copy.body = original.body;
      copy.encoding = original.encoding;
      return copy;
    }
    return null;
  }

  @override
  void close() {
    _inner.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../constants/app_env.dart';
import 'encryption_service.dart';
import 'storage_service.dart';

/// HTTP client that automatically adds authentication token to requests
/// and handles token refresh on 401 responses.
@LazySingleton(as: http.Client)
class AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final StorageService _storageService;
  final EncryptionService _encryptionService = EncryptionService();
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

    var response = await _inner.send(request);

    // Intercept 401 – try to refresh token then retry once
    if (response.statusCode == 401 && !_isRefreshing && token != null) {
      final newToken = await _tryRefreshToken(token);
      if (newToken != null) {
        final retryRequest = _copyRequest(request, newToken);
        if (retryRequest != null) {
          response = await _inner.send(retryRequest);
        }
      }
    }

    return _maybeDecryptResponse(response);
  }

  bool _isEventStream(http.StreamedResponse response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    return contentType.contains('text/event-stream');
  }

  Future<http.StreamedResponse> _maybeDecryptResponse(
    http.StreamedResponse response,
  ) async {
    if (_isEventStream(response)) {
      return response;
    }

    final bytes = await response.stream.toBytes();
    if (bytes.isEmpty) {
      return _cloneResponse(response, bytes);
    }

    final body = utf8.decode(bytes);
    final decryptedBody = await _tryDecryptBody(body);
    if (decryptedBody == null) {
      return _cloneResponse(response, bytes);
    }

    final decryptedBytes = utf8.encode(decryptedBody);
    return _cloneResponse(response, decryptedBytes);
  }

  http.StreamedResponse _cloneResponse(
    http.StreamedResponse response,
    List<int> bodyBytes,
  ) {
    final headers = Map<String, String>.from(response.headers);
    headers['content-length'] = bodyBytes.length.toString();

    return http.StreamedResponse(
      Stream<List<int>>.value(bodyBytes),
      response.statusCode,
      contentLength: bodyBytes.length,
      headers: headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }

  Future<String?> _tryDecryptBody(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    dynamic parsed;
    try {
      parsed = json.decode(trimmed);
    } catch (_) {
      return null;
    }

    if (parsed is! Map<String, dynamic>) {
      return null;
    }

    // Trường hợp 1: Toàn bộ response bị mã hóa (cấp ngoài cùng)
    if (_encryptionService.looksLikeWrapped(parsed)) {
      final decrypted =
          await _encryptionService.tryDecryptWrappedToStringAsync(parsed);
      if (decrypted != null) {
        return decrypted;
      }
    }

    // Trường hợp 2: Chỉ phần 'data' bị mã hóa (bọc trong cấu trúc chuẩn của server)
    final dataNode = parsed['data'];
    if (dataNode is Map<String, dynamic> &&
        _encryptionService.looksLikeWrapped(dataNode)) {
      final decrypted =
          await _encryptionService.tryDecryptWrappedToStringAsync(dataNode);
      if (decrypted != null) {
        try {
          parsed['data'] = json.decode(decrypted);
        } catch (_) {
          return null;
        }
        return json.encode(parsed);
      }
    }

    return null;
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

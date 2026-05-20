import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_env.dart';
import '../../core/errors/exceptions.dart';
import '../models/users_models.dart';

class UserFavoritesRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  UserFavoritesRemoteDataSource({
    required this.client,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? AppEnv.baseUrl;

  Future<AdminUserModel> getUserById({
    required String userId,
    String? accessToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/users/$userId');
    http.Response response;

    try {
      response = await client.get(
        uri,
        headers: _authHeaders(accessToken),
      );
    } catch (error) {
      throw NetworkException('Không lấy được dữ liệu người dùng: $error');
    }

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Không lấy được dữ liệu người dùng');
    }

    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'] as Map<String, dynamic>? ?? decoded;
      return AdminUserModel.fromJson(data);
    }

    throw const ServerException('Phản hồi không hợp lệ');
  }

  Future<void> updateFavorites({
    required String userId,
    required List<String> favoriteRouteIds,
    required List<String> favoriteStationIds,
    String? accessToken,
  }) async {
    final payload = {
      'favoriteRouteIds': favoriteRouteIds,
      'favoriteStationIds': favoriteStationIds,
    };

    final uri = Uri.parse('$baseUrl/api/v1/users/$userId');
    http.Response response;

    try {
      response = await client.put(
        uri,
        headers: {
          ..._jsonHeaders(),
          ..._authHeaders(accessToken),
        },
        body: json.encode(payload),
      );
    } catch (error) {
      throw NetworkException('Không cập nhật được yêu thích: $error');
    }

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const UnauthorizedException('Chưa được xác thực');
    }

    throw _errorFromResponse(response, 'Cập nhật yêu thích thất bại');
  }

  Map<String, String> _jsonHeaders() {
    return const {
      'Content-Type': 'application/json',
    };
  }

  Map<String, String> _authHeaders(String? accessToken) {
    if (accessToken == null || accessToken.isEmpty) {
      return const {};
    }
    return {
      'Authorization': 'Bearer $accessToken',
    };
  }

  Exception _errorFromResponse(http.Response response, String fallback) {
    final body = response.body;
    if (body.trim().isNotEmpty) {
      try {
        final parsed = json.decode(body);
        if (parsed is Map<String, dynamic>) {
          final message =
              parsed['message']?.toString() ?? parsed['error']?.toString();
          if (message != null && message.isNotEmpty) {
            return ServerException(message);
          }
        }
      } catch (_) {
        // Ignore parse errors and use fallback.
      }
    }

    return ServerException('$fallback: ${response.statusCode}');
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_env.dart';
import '../../core/errors/exceptions.dart';

class UserFavoritesRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  UserFavoritesRemoteDataSource({
    required this.client,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? AppEnv.baseUrl;

  Future<void> updateFavorites({
    required String userId,
    required List<String> favoriteRouteIds,
    required List<String> favoriteStationIds,
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
        headers: _jsonHeaders(),
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

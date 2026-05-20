import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_env.dart';
import '../../core/errors/exceptions.dart';
import '../models/notification_models.dart';

class NotificationsRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  NotificationsRemoteDataSource({
    required this.client,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? AppEnv.baseUrl;

  Future<NotificationsPageResponse> getNotifications({
    int page = 1,
    int limit = 20,
    String orderBy = 'createdAt',
    String orderDirection = 'desc',
    String? search,
    String? searchFields,
    String? type,
    String? accessToken,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': '$page',
        'limit': '$limit',
        'orderBy': orderBy,
        'orderDirection': orderDirection,
      };

      final normalizedSearch = search?.trim() ?? '';
      if (normalizedSearch.isNotEmpty) {
        queryParams['search'] = normalizedSearch;
      }

      final normalizedFields = searchFields?.trim() ?? '';
      if (normalizedFields.isNotEmpty) {
        queryParams['searchFields'] = normalizedFields;
      }

      final normalizedType = type?.trim() ?? '';
      if (normalizedType.isNotEmpty) {
        queryParams['type'] = normalizedType;
      }

      final uri = Uri.parse('$baseUrl/api/v1/notifications')
          .replace(queryParameters: queryParams);

      final response = await client.get(
        uri,
        headers: _buildHeaders(accessToken),
      );

      if (response.statusCode == 200) {
        final decoded = _decodeBody(response.body);
        return NotificationsPageResponse.fromJson(decoded);
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const UnauthorizedException('Chưa được xác thực');
      }

      throw _errorFromResponse(response, 'Lấy danh sách thông báo thất bại');
    } catch (e) {
      if (e is ServerException || e is UnauthorizedException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  Map<String, String> _buildHeaders(String? accessToken) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (accessToken != null && accessToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${accessToken.trim()}';
    }

    return headers;
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final parsed = json.decode(body);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    if (parsed is Map) {
      return Map<String, dynamic>.from(parsed);
    }
    if (parsed is List) {
      return {
        'data': parsed,
      };
    }

    throw const ServerException('Phản hồi không hợp lệ');
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

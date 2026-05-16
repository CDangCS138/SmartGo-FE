import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_env.dart';
import '../../core/errors/exceptions.dart';
import '../models/favorite_route_model.dart';

class FavoriteRoutesRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  FavoriteRoutesRemoteDataSource({
    required this.client,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? AppEnv.baseUrl;

  Future<FavoriteRoutesResponse> getFavoriteRoutes({
    int page = 1,
    int limit = 10,
    String orderBy = 'createdAt',
    String orderDirection = 'desc',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/favorite-routes').replace(
      queryParameters: {
        'page': '$page',
        'limit': '$limit',
        'orderBy': orderBy,
        'orderDirection': orderDirection,
      },
    );

    final response = await client.get(uri, headers: _jsonHeaders());
    if (response.statusCode != 200) {
      throw _errorFromResponse(
          response, 'Lay danh sach tuyen yeu thich that bai');
    }

    final decoded = _decodeBody(response.body);
    return FavoriteRoutesResponse.fromJson(decoded);
  }

  Future<FavoriteRouteModel> createFavoriteRoute({
    required FavoriteRouteModel request,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/api/v1/favorite-routes'),
      headers: _jsonHeaders(),
      body: json.encode(request.toJson()),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _errorFromResponse(response, 'Luu tuyen yeu thich that bai');
    }

    final decoded = _decodeBody(response.body);
    final data = _extractDataMap(decoded);
    return FavoriteRouteModel.fromJson(data);
  }

  Future<FavoriteRouteModel> getFavoriteRouteById({
    required String id,
  }) async {
    final response = await client.get(
      Uri.parse('$baseUrl/api/v1/favorite-routes/$id'),
      headers: _jsonHeaders(),
    );

    if (response.statusCode == 404) {
      throw const NotFoundException('Khong tim thay tuyen yeu thich');
    }

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Lay tuyen yeu thich that bai');
    }

    final decoded = _decodeBody(response.body);
    final data = _extractDataMap(decoded);
    return FavoriteRouteModel.fromJson(data);
  }

  Future<void> deleteFavoriteRoute({
    required String id,
  }) async {
    final response = await client.delete(
      Uri.parse('$baseUrl/api/v1/favorite-routes/$id'),
      headers: _jsonHeaders(),
    );

    if (response.statusCode == 404) {
      throw const NotFoundException('Khong tim thay tuyen yeu thich');
    }

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Xoa tuyen yeu thich that bai');
    }
  }

  Map<String, String> _jsonHeaders() {
    return const {
      'Content-Type': 'application/json',
    };
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final parsed = json.decode(body);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }

    throw const ServerException('Response khong hop le');
  }

  Map<String, dynamic> _extractDataMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return decoded;
    }
    throw const ServerException('Response khong hop le');
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

    if (response.statusCode == 401 || response.statusCode == 403) {
      return const UnauthorizedException('Chua duoc xac thuc');
    }

    return ServerException('$fallback: ${response.statusCode}');
  }
}

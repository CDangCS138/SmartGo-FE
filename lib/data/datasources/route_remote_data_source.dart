import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/constants/app_env.dart';
import 'package:smartgo/core/errors/exceptions.dart';
import 'package:smartgo/data/models/route_model.dart';
import 'package:smartgo/data/models/path_finding_model.dart';
import 'package:smartgo/domain/entities/route.dart';

abstract class RouteRemoteDataSource {
  Future<RouteListResponse> getAllRoutes({
    int page = 1,
    int limit = 200,
    RouteDirection? direction,
  });

  Future<RouteResponse> getRouteById({
    required String id,
    RouteDirection? direction,
  });

  Future<PathResponse> findPath(PathRequest request);
}

@LazySingleton(as: RouteRemoteDataSource)
class RouteRemoteDataSourceImpl implements RouteRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  RouteRemoteDataSourceImpl({
    required this.client,
  }) : baseUrl = AppEnv.baseUrl;

  @override
  Future<RouteListResponse> getAllRoutes({
    int page = 1,
    int limit = 200,
    RouteDirection? direction,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (direction != null) {
        queryParams['direction'] = direction.toApiString();
      }

      final uri = Uri.parse('$baseUrl/api/v1/routes')
          .replace(queryParameters: queryParams);

      final response = await client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return RouteListResponse.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw const NotFoundException('Routes not found');
      } else {
        throw ServerException('Failed to fetch routes: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is NotFoundException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  @override
  Future<RouteResponse> getRouteById({
    required String id,
    RouteDirection? direction,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (direction != null) {
        queryParams['direction'] = direction.toApiString();
      }

      final uri = Uri.parse('$baseUrl/api/v1/routes/$id').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return RouteResponse.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw NotFoundException('Route with ID $id not found');
      } else {
        throw ServerException('Failed to fetch route: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is NotFoundException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  @override
  Future<PathResponse> findPath(PathRequest request) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/routing/find-path');

      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        final dataJson = jsonData['data'] as Map<String, dynamic>? ?? jsonData;
        return PathResponse.fromJson(dataJson);
      } else if (response.statusCode == 404) {
        throw const NotFoundException('No path found between the stations');
      } else {
        final message = _extractApiErrorMessage(response.body);
        if (message != null && message.isNotEmpty) {
          throw ServerException(
            'Failed to find path (${response.statusCode}): $message',
          );
        }
        throw ServerException('Failed to find path: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is NotFoundException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  String? _extractApiErrorMessage(String rawBody) {
    final body = rawBody.trim();
    if (body.isEmpty) {
      return null;
    }

    try {
      final parsed = json.decode(body);
      if (parsed is Map<String, dynamic>) {
        final direct = parsed['message']?.toString();
        if ((direct ?? '').isNotEmpty) {
          return direct;
        }

        final error = parsed['error'];
        if (error is String && error.isNotEmpty) {
          return error;
        }

        if (error is List && error.isNotEmpty) {
          final first = error.first?.toString();
          if ((first ?? '').isNotEmpty) {
            return first;
          }
        }
      }
    } catch (_) {
      // Ignore parsing errors and use fallback.
    }

    return body;
  }
}

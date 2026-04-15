import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_env.dart';
import '../../core/errors/exceptions.dart';
import '../models/message_models.dart';

class MessageRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  MessageRemoteDataSource({
    required this.client,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? AppEnv.baseUrl;

  Future<MessageListResponse> getMessages({
    required String conversationId,
    String? accessToken,
    int page = 1,
    int limit = 10,
    String? search,
    String? orderBy = 'createdAt',
    String? orderDirection = 'desc',
    String? searchFields = 'content',
  }) async {
    final query = <String, String>{
      'conversationId': conversationId,
      'page': '$page',
      'limit': '$limit',
      if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      if ((orderBy ?? '').trim().isNotEmpty) 'orderBy': orderBy!.trim(),
      if ((orderDirection ?? '').trim().isNotEmpty)
        'orderDirection': orderDirection!.trim(),
      if ((searchFields ?? '').trim().isNotEmpty)
        'searchFields': searchFields!.trim(),
    };

    final uri = Uri.parse('$baseUrl/api/v1/messages').replace(
      queryParameters: query,
    );

    final response = await client.get(
      uri,
      headers: _jsonHeaders(accessToken),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Lay danh sach messages that bai');
    }

    final jsonBody = _decodeBody(response.body);
    return MessageListResponse.fromJson(jsonBody);
  }

  Future<MessageModel> createMessage({
    required CreateMessageRequest request,
    String? accessToken,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/api/v1/messages'),
      headers: _jsonHeaders(accessToken),
      body: json.encode(request.toJson()),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _errorFromResponse(response, 'Tao message that bai');
    }

    final jsonBody = _decodeBody(response.body);
    return MessageModel.fromJson(jsonBody);
  }

  Future<MessageModel> getMessageById({
    required String id,
    String? accessToken,
  }) async {
    final response = await client.get(
      Uri.parse('$baseUrl/api/v1/messages/$id'),
      headers: _jsonHeaders(accessToken),
    );

    if (response.statusCode == 404) {
      throw const NotFoundException('Message khong ton tai');
    }

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Lay message theo id that bai');
    }

    final jsonBody = _decodeBody(response.body);
    return MessageModel.fromJson(jsonBody);
  }

  Future<MessageModel> updateMessageById({
    required String id,
    required UpdateMessageRequest request,
    String? accessToken,
  }) async {
    final response = await client.put(
      Uri.parse('$baseUrl/api/v1/messages/$id'),
      headers: _jsonHeaders(accessToken),
      body: json.encode(request.toJson()),
    );

    if (response.statusCode == 404) {
      throw const NotFoundException('Message khong ton tai');
    }

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Cap nhat message that bai');
    }

    final jsonBody = _decodeBody(response.body);
    return MessageModel.fromJson(jsonBody);
  }

  Future<void> deleteMessageById({
    required String id,
    String? accessToken,
  }) async {
    final response = await client.delete(
      Uri.parse('$baseUrl/api/v1/messages/$id'),
      headers: _jsonHeaders(accessToken),
    );

    if (response.statusCode == 404) {
      throw const NotFoundException('Message khong ton tai');
    }

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Xoa message that bai');
    }
  }

  Map<String, String> _jsonHeaders(String? accessToken) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if ((accessToken ?? '').isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
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
        // Keep fallback.
      }
    }

    return ServerException('$fallback: ${response.statusCode}');
  }
}

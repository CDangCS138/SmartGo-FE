import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/errors/exceptions.dart';
import '../models/chatbot_models.dart';

class ChatbotRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  ChatbotRemoteDataSource({
    required this.client,
    this.baseUrl = 'http://20.6.128.105:8000',
  });

  Future<ChatbotChatResponse> chat({
    required String message,
    String? conversationId,
    String? accessToken,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      if ((conversationId ?? '').trim().isNotEmpty)
        'conversationId': conversationId,
    };

    final response = await client.post(
      Uri.parse('$baseUrl/api/v1/chatbot/chat'),
      headers: _jsonHeaders(accessToken),
      body: json.encode(body),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response, 'Gui tin nhan chatbot that bai');
    }

    final jsonBody = _decodeBody(response.body);
    return ChatbotChatResponse.fromJson(jsonBody);
  }

  Future<ChatbotEmbeddedVector> embedKnowledge({
    required ChatbotEmbedRequest request,
    required String accessToken,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/api/v1/chatbot/embed'),
      headers: _jsonHeaders(accessToken),
      body: json.encode(request.toJson()),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _errorFromResponse(response, 'Embed knowledge that bai');
    }

    final jsonBody = _decodeBody(response.body);
    return ChatbotEmbeddedVector.fromJson(jsonBody);
  }

  Future<ChatbotBulkEmbedResponse> embedKnowledgeFile({
    required String accessToken,
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/chatbot/embed/file'),
    );

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _errorFromResponse(response, 'Embed file JSON that bai');
    }

    final jsonBody = _decodeBody(response.body);
    return ChatbotBulkEmbedResponse.fromJson(jsonBody);
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

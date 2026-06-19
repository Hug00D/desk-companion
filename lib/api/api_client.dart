import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://100.119.136.81:8080/api/v1',
  );

  ApiClient({http.Client? httpClient, this.baseUrl = defaultBaseUrl})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String baseUrl;

  Future<Map<String, dynamic>> get(String path, {String? accessToken}) async {
    final response = await _httpClient.get(
      _uri(path),
      headers: _headers(accessToken),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final response = await _httpClient.post(
      _uri(path),
      headers: _headers(accessToken),
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final response = await _httpClient.put(
      _uri(path),
      headers: _headers(accessToken),
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    String? accessToken,
  }) async {
    final response = await _httpClient.delete(
      _uri(path),
      headers: _headers(accessToken),
    );
    return _decodeResponse(response);
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }

  Map<String, String> _headers(String? accessToken) {
    return {
      'Content-Type': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final data = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw ApiException.fromResponse(response.statusCode, data);
  }
}

class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.errorCode,
    this.details,
  });

  final int statusCode;
  final String message;
  final String? errorCode;
  final Object? details;

  factory ApiException.fromResponse(int statusCode, Map<String, dynamic> data) {
    var message = data['message']?.toString() ?? '未知錯誤';
    final details = data['details'];
    if (data['errorCode'] == 'VALIDATION_ERROR' && details != null) {
      message = '驗證失敗: $details';
    }

    return ApiException(
      statusCode: statusCode,
      message: message,
      errorCode: data['errorCode']?.toString(),
      details: details,
    );
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}

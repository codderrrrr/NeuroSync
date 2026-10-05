import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/session_token_store.dart';
import 'api_exception.dart';

/// JSON client for the NeuroSync API.
///
/// Owns the base URL, the bearer session token, JSON encoding/decoding and
/// error translation so repositories never deal with HTTP details. A single
/// instance is shared for the whole application so the underlying
/// [http.Client] can reuse connections.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required http.Client httpClient,
    required this.sessionToken,
    Duration? timeout,
  })  : _httpClient = httpClient,
        _timeout = timeout ?? const Duration(seconds: 20);

  final String baseUrl;
  final SessionTokenCache sessionToken;

  final http.Client _httpClient;
  final Duration _timeout;

  Future<Map<String, dynamic>> getObject(String path) async {
    final response =
        await _send(() => _httpClient.get(_uri(path), headers: _headers()));
    return _decodeObject(response);
  }

  Future<List<dynamic>> getList(String path) async {
    final response =
        await _send(() => _httpClient.get(_uri(path), headers: _headers()));
    _ensureSuccess(response);
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const ApiException('Unexpected response from the server.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> postObject(
      String path, Map<String, dynamic> body) async {
    final response = await _send(() => _post(path, body));
    return _decodeObject(response);
  }

  Future<void> postEmpty(String path) async {
    final response = await _send(() => _post(path, null));
    _ensureSuccess(response);
  }

  /// Sends a partial update. Used for editing an exercise already assigned.
  Future<Map<String, dynamic>> patchObject(
      String path, Map<String, dynamic> body) async {
    final response = await _send(() => _sendWith('PATCH', path, body));
    return _decodeObject(response);
  }

  /// Removes something. The API answers 204, so there is nothing to decode.
  Future<void> delete(String path) async {
    final response =
        await _send(() => _httpClient.delete(_uri(path), headers: _headers()));
    _ensureSuccess(response);
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers() {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json'
    };
    final String? token = sessionToken.value;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _sendWith(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) {
    final Map<String, String> headers = _headers();
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    final Uri uri = _uri(path);
    return switch (method) {
      'PATCH' => _httpClient.patch(uri,
          headers: headers, body: body == null ? null : jsonEncode(body)),
      _ => _httpClient.post(uri,
          headers: headers, body: body == null ? null : jsonEncode(body)),
    };
  }

  Future<http.Response> _post(String path, Map<String, dynamic>? body) =>
      _sendWith('POST', path, body);

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach the server (${error.message}).');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    _ensureSuccess(response);
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Unexpected response from the server.');
    }
    return decoded;
  }

  void _ensureSuccess(http.Response response) {
    final int statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    throw ApiException(_errorMessage(response), statusCode: statusCode);
  }

  /// Extracts a readable message from FastAPI's `detail` payloads.
  String _errorMessage(http.Response response) {
    final String fallback = 'Request failed (${response.statusCode}).';
    if (response.body.isEmpty) {
      return fallback;
    }
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final Object? detail = decoded['detail'];
        if (detail is String) {
          return detail;
        }
        if (detail is List && detail.isNotEmpty) {
          final Object? first = detail.first;
          if (first is Map<String, dynamic>) {
            final Object? message = first['msg'];
            if (message is String) {
              return message;
            }
          }
        }
      }
    } on FormatException {
      return fallback;
    }
    return fallback;
  }
}

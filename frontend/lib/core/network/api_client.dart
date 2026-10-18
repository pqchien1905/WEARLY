import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_tokens.dart';

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.details});
  final String code, message;
  final int? status;
  final Object? details;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? client,
    SessionTokens? tokens,
    this.timeout = const Duration(seconds: 15),
  }) : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _client = client ?? http.Client(),
       tokens = tokens ?? SessionTokens() {
    if (!['http', 'https'].contains(_base.scheme) ||
        _base.host.isEmpty ||
        _base.userInfo.isNotEmpty ||
        _base.hasQuery ||
        _base.hasFragment) {
      throw ArgumentError(
        'API_BASE_URL phải là địa chỉ HTTP/HTTPS hợp lệ, gồm /api/v1.',
      );
    }
  }
  final Uri _base;
  final http.Client _client;
  final SessionTokens tokens;
  final Duration timeout;
  Future<Object?> get(String path, {Map<String, String>? query}) =>
      request('GET', path, query: query);
  Future<Object?> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    if (path.startsWith('/') ||
        path.contains('://') ||
        path.split('/').contains('..')) {
      throw ArgumentError('API path must be relative.');
    }
    final uri = _base.resolve(path).replace(queryParameters: query);
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    if (tokens.accessToken != null) {
      req.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      final response = await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(timeout);
      Object? data;
      try {
        data = response.bodyBytes.isEmpty
            ? null
            : jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw ApiException(
          'INVALID_RESPONSE',
          'Máy chủ trả dữ liệu không hợp lệ. Hãy thử lại.',
          status: response.statusCode,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) tokens.clear();
        final error = data is Map ? data['error'] : null;
        final code = error is Map
            ? error['code']?.toString() ?? 'REQUEST_FAILED'
            : 'REQUEST_FAILED';
        final message = switch (response.statusCode) {
          400 => 'Thông tin chưa hợp lệ. Kiểm tra lại các trường đã nhập.',
          401 => 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
          403 => 'Bạn không có quyền thực hiện thao tác này.',
          404 => 'Không tìm thấy nội dung này.',
          409 => 'Dữ liệu đã thay đổi. Tải lại trước khi tiếp tục.',
          429 => 'Bạn thao tác quá nhanh. Vui lòng thử lại sau.',
          _ => 'Chưa thể kết nối dịch vụ. Vui lòng thử lại.',
        };
        throw ApiException(
          code,
          message,
          status: response.statusCode,
          details: error,
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException(
        'TIMEOUT',
        'Kết nối quá thời gian chờ. Hãy thử lại.',
      );
    } on http.ClientException {
      throw const ApiException(
        'CONNECTION_ERROR',
        'Không kết nối được máy chủ. Kiểm tra mạng và thử lại.',
      );
    }
  }

  void close() {
    _client.close();
    tokens.clear();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'session_tokens.dart';
import 'platform_http_client.dart';

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.details});
  final String code, message;
  final int? status;
  final Object? details;
  @override
  String toString() => message;
}

const sessionChanged = ApiException(
  'SESSION_CHANGED',
  'Phiên tài khoản đã thay đổi. Vui lòng thử lại.',
);

class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? client,
    SessionTokens? tokens,
    this.browserScope,
    this.timeout = const Duration(seconds: 15),
  }) : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _client =
           client ?? platformHttpClient(credentials: browserScope != null),
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
  final String? browserScope;
  Future<void> _browserRequests = Future<void>.value();
  Future<void>? _refreshing;
  int? _refreshGeneration;
  bool get _canRefresh => browserScope != null
      ? tokens.userId != null
      : tokens.refreshToken != null;

  /// Cookie mutations are ordered through actual network completion, including
  /// after a caller timeout. Discarded successful logins are revoked before the
  /// next queued login/logout can run, preventing late cookie resurrection.
  Future<Object?> browserAuth(
    String action, {
    Map<String, Object?>? body,
    bool Function()? isCurrent,
  }) async {
    if (!const ['customer', 'admin'].contains(browserScope) ||
        !const ['login', 'register', 'refresh', 'logout'].contains(action)) {
      throw ArgumentError('Invalid browser authentication operation');
    }
    var expired = false;
    Future<http.Response> send(String operation) async {
      final request = http.Request(
        'POST',
        _base.resolve('auth/browser/$browserScope/$operation'),
      );
      request.headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Wearly-Browser': '1',
      });
      request.body = jsonEncode(operation == action ? body ?? {} : {});
      return http.Response.fromStream(await _client.send(request));
    }

    final transport = _browserRequests.then((_) async {
      if (expired && action != 'logout') {
        throw TimeoutException('Queued authentication expired');
      }
      if (isCurrent != null && !isCurrent()) throw sessionChanged;
      final response = await send(action);
      if ((action == 'login' || action == 'register') &&
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          (expired || (isCurrent != null && !isCurrent()))) {
        await send('logout');
        throw sessionChanged;
      }
      return response;
    });
    _browserRequests = transport.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      final response = await transport.timeout(
        timeout,
        onTimeout: () {
          expired = true;
          throw TimeoutException('Browser authentication timed out');
        },
      );
      return _decode(response, login: action == 'login');
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

  Future<Object?> get(String path, {Map<String, String>? query}) =>
      request('GET', path, query: query);

  Future<Object?> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    Map<String, String>? headers,
    bool authenticated = true,
    bool refresh = true,
    void Function()? onLateCompletion,
  }) async {
    _validatePath(path);
    final generation = tokens.generation;
    final access = authenticated ? tokens.accessToken : null;
    final response = await _send(
      method,
      path,
      query: query,
      body: body,
      onLateCompletion: onLateCompletion,
      headers: {
        if (access != null) 'Authorization': 'Bearer $access',
        ...?headers,
      },
    );
    if (authenticated && tokens.generation != generation) throw sessionChanged;
    if (response.statusCode == 401 &&
        authenticated &&
        refresh &&
        !path.startsWith('auth/') &&
        _canRefresh) {
      if (tokens.accessToken == access) await _refresh(generation);
      if (tokens.generation != generation) throw sessionChanged;
      return request(
        method,
        path,
        query: query,
        body: body,
        headers: headers,
        authenticated: true,
        refresh: false,
        onLateCompletion: onLateCompletion,
      );
    }
    if (response.statusCode == 401 && authenticated) tokens.clear();
    return _decode(
      response,
      login: path == 'auth/login' || path == 'auth/admin/login',
    );
  }

  void _validatePath(String path) {
    if (path.startsWith('/') ||
        path.contains('://') ||
        path.split('/').contains('..') ||
        Uri.parse(path).hasScheme ||
        path.contains('\\')) {
      throw ArgumentError('API path must be relative.');
    }
  }

  Future<Object?> uploadImage(
    String path, {
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> fields,
    required String key,
    void Function()? onLateCompletion,
  }) async {
    _validatePath(path);
    final generation = tokens.generation;
    // Freeze the payload before awaiting refresh or network IO.
    final payload = Uint8List.fromList(bytes);
    final metadata = Map<String, String>.of(fields);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (tokens.generation != generation) throw sessionChanged;
      final access = tokens.accessToken;
      final request = http.MultipartRequest('POST', _base.resolve(path))
        ..headers.addAll({
          'Accept': 'application/json',
          'Idempotency-Key': key,
          if (access != null) 'Authorization': 'Bearer $access',
        })
        ..fields.addAll(metadata)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            payload,
            filename: mimeType == 'image/png' ? 'catalog.png' : 'catalog.jpg',
            contentType: MediaType.parse(mimeType),
          ),
        );
      final response = await _sendRequest(
        request,
        onLateCompletion: onLateCompletion,
      );
      if (tokens.generation != generation) throw sessionChanged;
      if (response.statusCode == 401 && attempt == 0 && _canRefresh) {
        if (tokens.accessToken == access) await _refresh(generation);
        continue;
      }
      if (response.statusCode == 401) tokens.clear();
      return _decode(response);
    }
    throw sessionChanged;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    Map<String, String>? headers,
    void Function()? onLateCompletion,
  }) async {
    final request = http.Request(
      method,
      _base.resolve(path).replace(queryParameters: query),
    );
    request.headers.addAll({'Accept': 'application/json', ...?headers});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _sendRequest(request, onLateCompletion: onLateCompletion);
  }

  Future<http.Response> _sendRequest(
    http.BaseRequest request, {
    void Function()? onLateCompletion,
  }) async {
    var timedOut = false;
    try {
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .whenComplete(() {
            // A timeout stops waiting, but the server may still commit a write.
            if (timedOut) onLateCompletion?.call();
          })
          .timeout(
            timeout,
            onTimeout: () {
              timedOut = true;
              throw TimeoutException('API request timed out', timeout);
            },
          );
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

  Future<void> _refresh(int generation) async {
    if (_refreshing != null && _refreshGeneration == generation) {
      return _refreshing;
    }
    final future = _rotate(generation);
    _refreshGeneration = generation;
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) {
        _refreshing = null;
        _refreshGeneration = null;
      }
    }
  }

  Future<void> _rotate(int generation) async {
    final refreshToken = tokens.refreshToken;
    try {
      final data = browserScope != null
          ? await browserAuth('refresh')
          : _decode(
              await _send(
                'POST',
                'auth/refresh',
                body: {'refreshToken': refreshToken},
              ),
            );
      if (tokens.generation != generation) throw sessionChanged;
      if (data is! Map ||
          data['accessToken'] is! String ||
          (browserScope == null && data['refreshToken'] is! String)) {
        throw const ApiException(
          'INVALID_RESPONSE',
          'Phiên đăng nhập không hợp lệ. Hãy đăng nhập lại.',
        );
      }
      if (browserScope != null &&
          (data['user'] is! Map || data['user']['id'] != tokens.userId)) {
        throw sessionChanged;
      }
      if (!tokens.rotate(
        generation: generation,
        accessToken: data['accessToken'],
        refreshToken: data['refreshToken'],
      )) {
        throw sessionChanged;
      }
    } catch (error) {
      final terminal =
          browserScope == null ||
          error is! ApiException ||
          error.status == 401 ||
          error.status == 403 ||
          error.code == 'SESSION_CHANGED' ||
          error.code == 'INVALID_RESPONSE';
      if (tokens.generation == generation && terminal) tokens.clear();
      rethrow;
    }
  }

  Object? _decode(http.Response response, {bool login = false}) {
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
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final error = data is Map ? data['error'] : null;
    final code = error is Map
        ? error['code']?.toString() ?? 'REQUEST_FAILED'
        : 'REQUEST_FAILED';
    final message = switch (response.statusCode) {
      400 => 'Thông tin chưa hợp lệ. Kiểm tra lại các trường đã nhập.',
      401 =>
        login
            ? 'Email hoặc mật khẩu chưa đúng.'
            : 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
      403 => 'Bạn không có quyền thực hiện thao tác này.',
      404 => 'Không tìm thấy nội dung này.',
      409 => 'Dữ liệu đã thay đổi. Tải lại trước khi tiếp tục.',
      429 => 'Bạn thao tác quá nhanh. Vui lòng thử lại.',
      _ => 'Chưa thể kết nối dịch vụ. Vui lòng thử lại.',
    };
    throw ApiException(
      code,
      message,
      status: response.statusCode,
      details: error,
    );
  }

  void close() {
    _client.close();
    tokens.clear();
  }
}

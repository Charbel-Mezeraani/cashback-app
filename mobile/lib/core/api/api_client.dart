import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';

/// Central Dio client.
///
/// - Attaches Bearer token to every request automatically.
/// - On 401, attempts one silent token refresh then retries.
/// - All errors are rethrown as [ApiException].
class ApiClient {
  static const _baseUrl = 'https://fearless-freedom-production-71ec.up.railway.app';

  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl:        _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers:        {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(_AuthInterceptor(_dio));
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    try {
      final res = await _dio.get(path, queryParameters: params);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    try {
      final res = await _dio.post(path, data: body);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body}) async {
    try {
      final res = await _dio.patch(path, data: body);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Direct PUT to a presigned S3 URL (no auth header, raw bytes).
  Future<void> putBytes(String url, List<int> bytes, String mimeType) async {
    try {
      final plain = Dio();
      await plain.put(
        url,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            'Content-Type':   mimeType,
            'Content-Length': bytes.length,
          },
        ),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await SecureStorage.getRefreshToken();
        if (refreshToken == null) {
          await SecureStorage.clearAll();
          return handler.next(err);
        }

        final res = await _dio.post('/auth/refresh',
            data: {'refresh_token': refreshToken});
        final newAccess  = res.data['access_token']  as String;
        final newRefresh = res.data['refresh_token'] as String;

        await SecureStorage.saveTokens(
          accessToken:  newAccess,
          refreshToken: newRefresh,
        );

        // Retry original request with new token
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retried = await _dio.fetch(err.requestOptions);
        return handler.resolve(retried);
      } catch (_) {
        await SecureStorage.clearAll();
      } finally {
        _isRefreshing = false;
      }
    }
    handler.next(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException({this.statusCode, required this.message});

  factory ApiException.fromDio(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    final msg  = (body is Map ? body['error'] as String? : null)
        ?? e.message
        ?? 'Unknown error';
    return ApiException(statusCode: code, message: msg);
  }

  /// User-facing string for specific status codes.
  String get userMessage => switch (statusCode) {
        400 => message,
        401 => 'Session expired. Please log in again.',
        404 => 'Not found.',
        409 => message, // duplicate — always pass through
        422 => message, // validation — always pass through
        500 => 'Server error. Please try again.',
        _   => message,
      };

  @override
  String toString() => 'ApiException($statusCode): $message';
}

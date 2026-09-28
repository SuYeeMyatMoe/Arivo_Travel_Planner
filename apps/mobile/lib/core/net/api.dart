import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';

/// A readable error the UI can show as-is ("what happened, what still works").
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message, [this.extra = const {}]);
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> extra;

  bool get isOffline => status == 0;

  @override
  String toString() => message;
}

/// Thin Dio wrapper: auth, request ids, idempotency keys and error mapping. HTTPS only outside localhost.
class ArivoApi {
  ArivoApi({String? baseUrl, String? devUser, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? ArivoConfig.apiBase,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 45),
              headers: {'Content-Type': 'application/json'},
            )) {
    final base = _dio.options.baseUrl;
    assert(base.startsWith('https://') || base.contains('localhost') || base.contains('10.0.2.2') || base.contains('127.0.0.1'),
        'Plain HTTP is only allowed for local development');
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      options.headers['X-Request-Id'] = _uuid.v4();
      final token = accessToken;
      options.headers['Authorization'] = token != null ? 'Bearer $token' : 'Dev ${devUser ?? ArivoConfig.devUser}';
      handler.next(options);
    }));
  }

  final Dio _dio;
  static const _uuid = Uuid();

  /// Supabase session access token (short-lived, refreshed by supabase_flutter). Null → dev auth locally.
  String? accessToken;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query, String? idempotencyKey}) => _send(() => _dio.post(
        path,
        data: body,
        queryParameters: query,
        options: idempotencyKey == null ? null : Options(headers: {'Idempotency-Key': idempotencyKey}),
      ));

  /// New key per user intent (e.g. one per "Book this" tap). Reusing it makes retries safe.
  static String newIdempotencyKey() => _uuid.v4();

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final r = await call();
      return r.data;
    } on DioException catch (e) {
      if (e.response == null) {
        throw ApiError(0, 'offline', "You're offline or the server is unreachable. Your saved trip still works.");
      }
      final data = e.response!.data;
      final detail = data is Map ? (data['detail'] ?? data) : null;
      if (detail is Map) {
        return Future.error(ApiError(
          e.response!.statusCode ?? 500,
          '${detail['code'] ?? 'error'}',
          '${detail['message'] ?? 'Something went wrong.'}',
          Map<String, dynamic>.from(detail),
        ));
      }
      throw ApiError(e.response!.statusCode ?? 500, 'error', detail is String ? detail : 'Something went wrong. Your trip is safe.');
    }
  }
}

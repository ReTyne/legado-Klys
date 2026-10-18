import 'package:dio/dio.dart';
import '../../constant/app_constants.dart';
import 'cookie_manager.dart';

/// 统一 HTTP 客户端，预置超时、UA、Cookie 拦截器
class HttpClient {
  HttpClient._();
  static final Dio _dio = _create();

  static Dio get instance => _dio;

  static Dio _create() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConstants.readTimeout),
      headers: {'User-Agent': AppConstants.defaultUserAgent},
      followRedirects: true,
      validateStatus: (s) => s != null && s < 400,
    ));

    final cookies = CookieManager();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final cookie = cookies.cookieHeader(options.uri.toString());
        if (cookie != null) options.headers['Cookie'] = cookie;
        handler.next(options);
      },
      onResponse: (response, handler) {
        final raw = response.headers.map['set-cookie'];
        cookies.saveFromResponse(response.realUri.toString(), raw);
        handler.next(response);
      },
    ));
    return dio;
  }

  /// 创建一个独立配置的 Dio（书源自定义 header/编码时使用）
  static Dio create({Map<String, dynamic>? headers, String? userAgent, ResponseType? responseType}) {
    return Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConstants.readTimeout),
      responseType: responseType,
      headers: {
        'User-Agent': userAgent ?? AppConstants.defaultUserAgent,
        ...?headers,
      },
    ));
  }
}

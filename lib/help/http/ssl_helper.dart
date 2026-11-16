import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// SSL/TLS 证书放行：书源常访问自签名或证书链不完整的站点，
/// 由 [attach] 为 Dio 配置全信任与主机名宽松校验。
class SslHelper {
  SslHelper._();

  /// 全局总开关：为 false 时 [attach] 一律不放行证书（安全默认）。
  /// 仅当本开关与 [attach] 的 trustAll 同时为 true 才启用放行。
  static bool allowAll = true;

  /// 为 [dio] 挂载证书放行适配器。
  ///
  /// 通过 [IOHttpClientAdapter.createHttpClient] 的
  /// [HttpClient.badCertificateCallback] 全信任证书链，并以
  /// [IOHttpClientAdapter.validateCertificate] 放行叶证书（含主机名宽松
  /// 校验）。Web / 无 dart:io 环境以 try/catch 安全降级，不抛异常。
  static void attach(Dio dio, {bool trustAll = true}) {
    final trust = allowAll && trustAll;
    try {
      final adapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          if (trust) {
            client.badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;
          }
          return client;
        },
        validateCertificate: trust
            ? (X509Certificate? cert, String host, int port) => true
            : null,
      );
      dio.httpClientAdapter = adapter;
    } catch (_) {
      // Web / 无 dart:io 环境：安全降级，不替换适配器也不抛异常
    }
  }
}

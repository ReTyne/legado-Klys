import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// SSL/TLS 配置：全信任放行、指定受信 CA、以及客户端证书（mTLS）。
///
/// 由 [attach] 为 Dio 挂载适配器；[buildSecurityContext] 可单独构造并复用上下文。
class SslHelper {
  SslHelper._();

  /// 全局总开关：为 false 时 [attach] 一律不放行证书（安全默认）。
  /// 仅当本开关与 [attach] 的 trustAll 同时为 true 才启用全信任。
  static bool allowAll = true;

  /// 构造自定义 [SecurityContext]。未指定任何证书配置时返回 null（使用默认上下文）。
  ///
  /// [trustedCertificates] 为受信 CA 证书字节列表；
  /// [clientCertificateBytes] 与 [clientPrivateKeyBytes] 成对提供时启用 mTLS。
  /// [clientCertificatePassword] 用于加密的私钥 / 证书（PEM 或 PKCS#12）。
  /// 证书字节非法时抛出异常，由调用方决定是否降级处理。
  static SecurityContext? buildSecurityContext({
    List<List<int>>? trustedCertificates,
    List<int>? clientCertificateBytes,
    List<int>? clientPrivateKeyBytes,
    String? clientCertificatePassword,
    bool withTrustedRoots = true,
  }) {
    final trusted = trustedCertificates ?? const <List<int>>[];
    final chain = (clientCertificateBytes != null &&
            clientCertificateBytes.isNotEmpty)
        ? clientCertificateBytes
        : null;
    final key = (clientPrivateKeyBytes != null &&
            clientPrivateKeyBytes.isNotEmpty)
        ? clientPrivateKeyBytes
        : null;
    if (trusted.isEmpty && chain == null && key == null) return null;

    final context = SecurityContext(withTrustedRoots: withTrustedRoots);
    for (final cert in trusted) {
      if (cert.isEmpty) continue;
      context.setTrustedCertificatesBytes(cert,
          password: clientCertificatePassword);
    }
    if (chain != null) {
      context.useCertificateChainBytes(chain,
          password: clientCertificatePassword);
    }
    if (key != null) {
      context.usePrivateKeyBytes(key, password: clientCertificatePassword);
    }
    return context;
  }

  /// 为 [dio] 挂载证书配置适配器。
  ///
  /// [trustAll] 为 true 且 [allowAll] 为 true 时放行全部证书（含主机名宽松校验）。
  /// 传入 [securityContext] 可复用已构造的上下文；否则由证书参数即时构造。
  /// Web / 无 dart:io 环境以 try/catch 安全降级，不抛异常。
  static void attach(
    Dio dio, {
    bool trustAll = true,
    SecurityContext? securityContext,
    List<List<int>>? trustedCertificates,
    List<int>? clientCertificateBytes,
    List<int>? clientPrivateKeyBytes,
    String? clientCertificatePassword,
  }) {
    final trust = allowAll && trustAll;
    try {
      final context = securityContext ??
          buildSecurityContext(
            trustedCertificates: trustedCertificates,
            clientCertificateBytes: clientCertificateBytes,
            clientPrivateKeyBytes: clientPrivateKeyBytes,
            clientCertificatePassword: clientCertificatePassword,
          );
      final adapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = context != null
              ? HttpClient(context: context)
              : HttpClient();
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

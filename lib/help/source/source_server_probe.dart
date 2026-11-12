import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// 单个备用服务器的探测结果。
class ServerProbeResult {
  const ServerProbeResult({
    required this.host,
    this.statusCode,
    required this.latencyMs,
    this.error,
  });

  final String host;
  final int? statusCode;
  final int latencyMs;
  final String? error;

  /// 能否收到 HTTP 响应（404 也算「服务器活着」）。
  bool get reachable => error == null && statusCode != null;

  /// 5xx：服务器/网关异常，书源通常会返回 502。
  bool get unhealthy => statusCode != null && statusCode! >= 500;

  String get label {
    if (error != null) return '不可达';
    final s = statusCode;
    if (s == null) return '未知';
    if (s >= 500) return '服务异常 ($s)';
    if (s >= 400) return '可达 ($s)';
    return '正常 ($s)';
  }
}

/// 聚合类书源（大灰狼 / 书山等）的备用服务器诊断与切换。
///
/// 这类书源把服务器列表写在 jsLib 的 `var host = [...]` 里，登录时若默认
/// 服务器 502，书源自带的「切换服务器」按钮也依赖网络才能工作。这里提供一个
/// 不依赖书源 JS 的本地诊断：逐个探测并直接改写 `source.variable` 的
/// `server` 字段（书源 JS 用 getArguments(variable,'server') 读取）。
class SourceServerProbe {
  SourceServerProbe._();

  /// 从书源 jsLib / loginUrl 中提取备用服务器地址。
  static List<String> extractHosts(BookSource source) {
    final out = <String>[];
    final lib = source.jsLib ?? '';
    final array = RegExp(r'(?:var|let|const)\s+host\s*=\s*\[([\s\S]*?)\]')
        .firstMatch(lib);
    if (array != null) {
      for (final m in RegExp(r'''['"](https?://[^'"]+)['"]''')
          .allMatches(array.group(1)!)) {
        final u = m.group(1)!.trim();
        if (!out.contains(u)) out.add(u);
      }
    }
    if (out.isEmpty) {
      // 回退：从 jsLib / loginUrl / exploreUrl 的 URL 字面量取 origin
      final text = '${source.jsLib ?? ''}\n${source.loginUrl ?? ''}\n'
          '${source.exploreUrl ?? ''}';
      for (final m in RegExp(r'''['"`](https?://[^'"`\s,]+)''')
          .allMatches(text)) {
        final u = Uri.tryParse(m.group(1)!);
        if (u == null || !u.hasAuthority) continue;
        final origin = '${u.scheme}://${u.host}'
            '${u.hasPort ? ':${u.port}' : ''}';
        if (!out.contains(origin)) out.add(origin);
        if (out.length >= 12) break;
      }
    }
    return out.take(12).toList();
  }

  /// 并发探测所有服务器（8 秒超时，接受任意 HTTP 状态码以便区分 404/502）。
  static Future<List<ServerProbeResult>> probeAll(List<String> hosts) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (s) => s != null && s < 600,
      followRedirects: true,
    ));
    return Future.wait(hosts.map((h) => _probeOne(dio, h)));
  }

  static Future<ServerProbeResult> _probeOne(Dio dio, String host) async {
    final sw = Stopwatch()..start();
    ServerProbeResult? best;
    String? lastError;
    final base = host.replaceAll(RegExp(r'/+$'), '');
    // 根路径常被 CDN / 网关挡成 502，而应用接口其实正常（大灰狼 v5 实测：
    // "/" → 502，"user_api" → 404，"login_api" POST → 200 且返回业务 JSON）。
    // 同时探测根与常见应用端点，取最健康的一次响应，避免把「根路径 502」
    // 误判成整台服务器不可用。
    for (final path in const ['/user_api', '/']) {
      try {
        final resp = await dio.getUri<List<int>>(
          Uri.parse('$base$path'),
          options: Options(responseType: ResponseType.bytes),
        );
        final r = ServerProbeResult(
            host: host,
            statusCode: resp.statusCode,
            latencyMs: sw.elapsedMilliseconds);
        if (best == null || _health(r) > _health(best)) best = r;
        if (_health(r) == 2) break;
      } catch (e) {
        lastError = _shortError(e);
      }
    }
    sw.stop();
    return best ??
        ServerProbeResult(
            host: host,
            latencyMs: sw.elapsedMilliseconds,
            error: lastError ?? '探测失败');
  }

  /// 健康度：2xx=2、4xx（服务在、路径不对）=1、5xx=0、无响应=-1。
  static int _health(ServerProbeResult r) {
    final s = r.statusCode;
    if (s == null) return -1;
    if (s >= 500) return 0;
    if (s >= 400) return 1;
    return 2;
  }

  static String _shortError(Object e) {
    final s = e.toString();
    return s.length > 120 ? s.substring(0, 120) : s;
  }

  /// 把选中的服务器写回书源 variable 并落库，返回新的 variable 字符串。
  ///
  /// variable 是书源 JS 的持久化 KV（JSON 字符串），合并写入而不整体覆盖，
  /// 避免丢掉书源设置中心保存的 tab/sources/tone_id 等其它字段。
  static Future<String> applyServer(
      BookSource source, String host, DatabaseService db) async {
    Map<String, dynamic> data;
    final raw = (source.variable ?? '').trim();
    try {
      final parsed = raw.isEmpty ? {} : jsonDecode(raw);
      data = parsed is Map
          ? Map<String, dynamic>.from(parsed)
          : <String, dynamic>{};
    } catch (_) {
      data = <String, dynamic>{};
    }
    data['server'] = host;
    final next = jsonEncode(data);
    source.variable = next;
    try {
      await db.updateSourceVariable(source.jsUrl, next);
    } catch (_) {}
    try {
      await db.updateSource(source);
    } catch (_) {}
    // 让 JS 运行时下次求值重新读取 variable（否则仍是旧服务器）
    try {
      await JsRuntimeManager.instance.invalidate(source.bookSourceUrl);
    } catch (_) {}
    return next;
  }

  /// 当前生效的服务器（从 variable 读）。
  static String currentServer(BookSource source) {
    final raw = (source.variable ?? '').trim();
    if (raw.isEmpty) return '';
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map && parsed['server'] != null) {
        return parsed['server'].toString();
      }
    } catch (_) {}
    return '';
  }
}

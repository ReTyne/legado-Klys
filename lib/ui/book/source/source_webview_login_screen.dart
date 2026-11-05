import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';

/// WebView 登录结果：对齐 E WebViewLoginFragment 回收 Cookie 后回写书源的产物。
class SourceWebLoginResult {
  /// 收集到的 Cookie 头字符串（`k=v; k2=v2`）
  final String cookie;

  /// 登录结束停留的地址（书源可据此判断登录回调 URL）
  final String finalUrl;

  /// Cookie 条目数
  final int cookieCount;

  const SourceWebLoginResult({
    required this.cookie,
    required this.finalUrl,
    required this.cookieCount,
  });
}

/// 特殊书源 WebView 登录页（对齐 legado-E ui/login/WebViewLoginFragment.kt）。
///
/// E 的链路：SourceLoginActivity 在 `loginUi` 为空时改用 Fragment →
/// 注入书源 headerMap（含 UA）加载绝对化 loginUrl → WebViewClient 在
/// onPageStarted/onPageFinished 用 `CookieManager.getCookie(url)` 收 Cookie，
/// `CookieStore.setCookie(source.getKey(), cookie)` 回写书源 → 网络层与 JS 复用。
///
/// 本页等价落地为：
///  1. 用书源 header（含 `loginHeader_$srcUrl`）与 UA 注入 InAppWebView；
///  2. shouldOverrideUrlLoading 拦截非 http(s) scheme（对齐 E 跳转外部 App 提示）；
///  3. onLoadStart/onLoadStop 通过全局 `iw.CookieManager` 收集当前域 + 书源域 Cookie；
///  4. 回写三处形成闭环：内存 [CookieManager]（source_engine 立即消费）、
///     cookies 表按 host 与书源 key 各存一份（跨启动持久化，对齐 E CookieStore）、
///     置 `source.enabledCookieJar=true` 让网络层从 DB 恢复会话；
///  5. JS 侧由 legado_js_runtime 的 `_collectCookies` 读同一份
///     `iw.CookieManager.instance()`，故登录后书源脚本也拿到 Cookie。
class SourceWebViewLoginScreen extends StatefulWidget {
  const SourceWebViewLoginScreen({
    super.key,
    required this.source,
    required this.loginUrl,
  });

  final BookSource source;
  final String loginUrl;

  @override
  State<SourceWebViewLoginScreen> createState() =>
      _SourceWebViewLoginScreenState();
}

class _SourceWebViewLoginScreenState extends State<SourceWebViewLoginScreen> {
  final DatabaseService _db = DatabaseService();
  iw.InAppWebViewController? _controller;
  int _progress = 0;
  String _currentUrl = '';
  int _cookieCount = 0;
  bool _finishing = false;

  /// 请求头只解析一次：避免在 build() 里反复创建 Future 导致
  /// FutureBuilder 重建 InAppWebView（会丢失登录态）。
  late final Future<Map<String, String>> _headersFuture;

  @override
  void initState() {
    super.initState();
    _currentUrl = _absoluteLoginUrl();
    _headersFuture = _buildHeaders();
  }

  /// 绝对化登录地址：对齐 E NetworkUtils.getAbsoluteURL(source.getKey(), loginUrl)。
  String _absoluteLoginUrl() {
    final raw = widget.loginUrl.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = Uri.tryParse(widget.source.bookSourceUrl);
    if (base != null && base.hasScheme && base.host.isNotEmpty) {
      return base.resolve(raw).toString();
    }
    return raw;
  }

  /// 书源请求头 + 登录头：对齐 E SourceLoginViewModel.headerMap =
  /// `source.getHeaderMap(true)`（hasLoginHeader=true 合并 loginHeader）。
  Future<Map<String, String>> _buildHeaders() async {
    final out = <String, String>{};
    void merge(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      try {
        final v = jsonDecode(raw);
        if (v is Map) {
          v.forEach((k, val) => out[k.toString()] = val?.toString() ?? '');
        }
      } catch (_) {
        // 非 JSON 头（如 @js: 规则）：忽略，UA 由 WebView 默认提供
      }
    }

    merge(widget.source.header);
    try {
      final prefs = await SharedPreferences.getInstance();
      merge(prefs.getString('loginHeader_${widget.source.bookSourceUrl}'));
    } catch (_) {}
    // 已保存的会话 Cookie 一并带上（对齐 E WebView 复用 CookieStore）
    final saved = CookieManager().cookieHeader(_currentUrl);
    if (saved != null && saved.isNotEmpty && !out.containsKey('Cookie')) {
      out['Cookie'] = saved;
    }
    return out;
  }

  /// 从全局 WebView CookieManager 收集当前页 + 书源域的全部 Cookie。
  /// 对齐 E onPageStarted/onPageFinished 的 `cookieManager.getCookie(url)`，
  /// 这里额外合并书源主域，避免登录回调跳到别的路径时漏 Cookie。
  Future<String> _collectCookies(String url) async {
    final jar = <String, String>{};
    final urls = <String>{url, _absoluteLoginUrl(), widget.source.bookSourceUrl};
    for (final u in urls) {
      if (u.isEmpty) continue;
      try {
        final list = await iw.CookieManager.instance()
            .getCookies(url: iw.WebUri(u));
        for (final c in list) {
          if (c.name.isNotEmpty && c.value != null) {
            jar[c.name] = c.value!;
          }
        }
      } catch (_) {}
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 回写登录结果：内存 CookieJar + cookies 表（按 host 与书源 key）+ 开启持久化开关。
  /// 对齐 E CookieStore.setCookie(source.getKey(), cookie) 与网络层 getHeaderMap。
  Future<void> _persist(String cookieStr, String url) async {
    if (cookieStr.isEmpty) return;
    CookieManager().saveFromResponse(url, [cookieStr]);
    try {
      final host = Uri.tryParse(url)?.host ?? '';
      if (host.isNotEmpty) await _db.saveCookie(host, cookieStr);
      // 按书源 key 再存一份（对齐 E 按 source.getKey 隔离 Cookie）
      await _db.saveCookie(widget.source.bookSourceUrl, cookieStr);
      if (!widget.source.enabledCookieJar) {
        widget.source.enabledCookieJar = true;
        await _db.updateSource(widget.source);
      }
    } catch (_) {}
  }

  /// 每次页面加载结束都实时回收 Cookie（对齐 E onPageFinished 的 setCookie）。
  Future<void> _onPageLoaded(String url) async {
    if (url.isEmpty) return;
    final str = await _collectCookies(url);
    await _persist(str, url);
    if (!mounted) return;
    setState(() {
      _cookieCount = str.isEmpty ? 0 : str.split(';').length;
    });
  }

  /// 完成登录：最终回收一次并带结果返回，供 SourceLoginScreen 刷新登录状态。
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final url = _currentUrl.isNotEmpty ? _currentUrl : _absoluteLoginUrl();
    final str = await _collectCookies(url);
    await _persist(str, url);
    if (!mounted) return;
    Navigator.of(context).pop(SourceWebLoginResult(
      cookie: str,
      finalUrl: url,
      cookieCount: str.isEmpty ? 0 : str.split(';').length,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('网页登录 - ${widget.source.bookSourceName}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller?.reload(),
            ),
            // 对齐 E source_webview_login.xml 的 menu_ok（检查 host Cookie 并结束）
            FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成登录'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(value: _progress / 100, minHeight: 2),
            // 状态条：当前地址与已收集 Cookie 数（登录过程可见，入口点了有反应）
            Container(
              width: double.infinity,
              color: cs.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.cookie_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('已回收 $_cookieCount 项 Cookie',
                      style: TextStyle(fontSize: 12, color: cs.primary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Map<String, String>>(
                future: _headersFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final headers = snap.data!;
                  final ua = headers['User-Agent'] ??
                      headers['user-agent'] ??
                      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
                  return iw.InAppWebView(
                    initialUrlRequest: iw.URLRequest(
                      url: iw.WebUri(_absoluteLoginUrl()),
                      headers: headers.isEmpty ? null : headers,
                    ),
                    initialSettings: iw.InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      useWideViewPort: true,
                      loadWithOverviewMode: true,
                      mixedContentMode:
                          iw.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                      userAgent: ua,
                    ),
                    onWebViewCreated: (c) => _controller = c,
                    onProgressChanged: (c, v) {
                      if (mounted) setState(() => _progress = v);
                    },
                    onLoadStart: (c, url) {
                      final u = url?.toString() ?? '';
                      if (u.startsWith('http') && mounted) {
                        setState(() => _currentUrl = u);
                      }
                      _onPageLoaded(u);
                    },
                    onLoadStop: (c, url) async {
                      final u = url?.toString() ?? '';
                      if (u.startsWith('http') && mounted) {
                        setState(() => _currentUrl = u);
                      }
                      await _onPageLoaded(u.isNotEmpty ? u : _absoluteLoginUrl());
                    },
                    // 对齐 E shouldOverrideUrlLoading：http/https 放行，
                    // 其它 scheme 提示用外部 App 打开（拦截跳转）。
                    shouldOverrideUrlLoading: (c, action) async {
                      final uri = action.request.url;
                      if (uri == null) return iw.NavigationActionPolicy.CANCEL;
                      final scheme = uri.scheme.toLowerCase();
                      if (scheme == 'http' || scheme == 'https') {
                        return iw.NavigationActionPolicy.ALLOW;
                      }
                      final external = uri.toString();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('跳转到其它应用：$external'),
                          action: SnackBarAction(
                            label: '打开',
                            onPressed: () async {
                              final u = Uri.tryParse(external);
                              if (u != null && await canLaunchUrl(u)) {
                                await launchUrl(u,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ));
                      }
                      return iw.NavigationActionPolicy.CANCEL;
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

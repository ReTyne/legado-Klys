/// 由 rss_read_screen.dart 按「一类一文件」拆出的 _HtmlBody。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rss_read_screen.dart';


/// HTML 正文：WebView 渲染（片段自动包裹为完整文档）。
/// * [style]：自定义 CSS，注入 <style>（完整文档插到 </head> 前）。
/// * [injectJs]：注入脚本，页面加载后执行（完整文档插到 </body> 前）。
/// * [preloadJs]：预加载脚本，文档开始加载前执行（AT_DOCUMENT_START）。
/// * [shouldOverrideUrlLoading]：链接拦截 JS，返回 false 的链接交外部浏览器打开。
class _HtmlBody extends StatelessWidget {
  const _HtmlBody({
    required this.html,
    required this.baseUrl,
    this.style,
    this.injectJs,
    this.preloadJs,
    this.shouldOverrideUrlLoading,
  });
  final String html;
  final String baseUrl;
  final String? style;
  final String? injectJs;
  final String? preloadJs;
  final String? shouldOverrideUrlLoading;

  /// 去掉 @js: / <js></js> 包裹，返回纯 JS
  String _jsBody(String rule) {
    var r = rule.trim();
    if (r.startsWith('@js:')) r = r.substring(4);
    if (r.startsWith('<js>')) {
      r = r.substring(4);
      if (r.endsWith('</js>')) r = r.substring(0, r.length - 5);
    }
    return r.trim();
  }

  String _document() {
    final css = (style ?? '').trim();
    final js = (injectJs ?? '').trim();
    final lower = html.toLowerCase();
    if (lower.contains('<html') || lower.contains('<!doctype')) {
      // 完整文档：保持原样，仅把自定义 CSS/脚本插入对应位置
      var doc = html;
      if (css.isNotEmpty) {
        final tag = '<style>\n$css\n</style>';
        final idx = doc.toLowerCase().lastIndexOf('</head>');
        doc = idx >= 0 ? doc.replaceRange(idx, idx, '\n$tag\n') : '$tag\n$doc';
      }
      if (js.isNotEmpty) {
        final tag = '<script>\n$js\n</script>';
        final idx = doc.toLowerCase().lastIndexOf('</body>');
        doc = idx >= 0 ? doc.replaceRange(idx, idx, '\n$tag\n') : '$doc\n$tag';
      }
      return doc;
    }
    final buf = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html><head><meta charset="utf-8">')
      ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    if (css.isNotEmpty) {
      buf.writeln('<style>\n$css\n</style>');
    }
    buf.writeln('''<style>
 body{margin:14px;line-height:1.8;font-size:16px;color:#1c1b1f;word-wrap:break-word;}
 img{max-width:100%;height:auto;border-radius:6px;}
 a{color:#1565c0;}
 pre{white-space:pre-wrap;word-wrap:break-word;}
</style></head>''');
    buf.writeln('<body>');
    buf.write(html);
    if (js.isNotEmpty) {
      buf.writeln('\n<script>\n$js\n</script>');
    }
    buf.writeln('</body></html>');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final preload = (preloadJs ?? '').trim();
    final overrideRule = (shouldOverrideUrlLoading ?? '').trim();
    return iw.InAppWebView(
      initialData: iw.InAppWebViewInitialData(
        data: _document(),
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: baseUrl.isNotEmpty ? iw.WebUri(baseUrl) : null,
      ),
      initialSettings: iw.InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldInterceptRequest: true,
        mixedContentMode: iw.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        supportZoom: true,
      ),
      // preloadJs：文档开始加载前执行（页面加载前的预加载）
      initialUserScripts: preload.isEmpty
          ? null
          : UnmodifiableListView<iw.UserScript>([
              iw.UserScript(
                source: preload,
                injectionTime: iw.UserScriptInjectionTime.AT_DOCUMENT_START,
              )
            ]),
      // shouldOverrideUrlLoading 规则：规则返回 false 的链接不在 WebView 内加载，
      // 转外部浏览器打开；未配置或执行失败时保持默认（WebView 内加载）
      shouldOverrideUrlLoading: overrideRule.isEmpty
          ? null
          : (controller, navigationAction) async {
              final url = navigationAction.request.url?.toString() ?? '';
              // 仅拦截 http(s) 跳转；初始 data: 加载等不拦截
              if (!url.startsWith('http')) return null;
              try {
                final res = await controller.evaluateJavascript(
                  source:
                      '(function(){try{return (function(url){${_jsBody(overrideRule)}})(${jsonEncode(url)});}catch(e){return true;}})()',
                );
                if (res == false) {
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                  return iw.NavigationActionPolicy.CANCEL;
                }
              } catch (_) {
                // 规则执行失败：放行，保持既有行为
              }
              return null;
            },
    );
  }
}

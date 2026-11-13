import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:legado_md3/common/deep_link_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 书籍详情「富文本简介」渲染。
///
/// 542` `showBookIntro`：
/// 简介并不是纯文本，而是按前缀分派三套渲染：
///  - `<useweb>`  → WebView 池 `loadDataWithBaseURL(bookUrl, html, ...)`，
///                   相对图片/链接以书籍地址为 base；
///  - `<usehtml>` → `TextView.setHtml(glideImageGetter, textViewTagHandler, ...)`，
///                   图片可点/可长按；
///  - `<md>`      → Markwon（GlideImagesPlugin / HtmlPlugin / TablePlugin）渲染 Markdown。
/// 另有 `CustomWebViewClient.shouldOverrideUrlLoading`（L503-529）拦截
/// `legado`/`yuedu` scheme 跳在线导入、其它 scheme 经确认跳外部 App。
///
/// 平台差异（显式降级，不伪造）：本工程没有 `flutter_html` / `flutter_markdown`
/// 依赖，也不能改 pubspec，故 `<usehtml>` 与 `<md>` 统一降级为
/// `flutter_inappwebview` 的 `InAppWebView` 渲染：`<usehtml>` 直接包一层
/// 带 viewport/暗色 CSS 的 HTML 文档，`<md>` 先用本项目自带的
/// [markdownToHtml] 转成 HTML 再同样渲染。WebView 无法像 Android
/// `TextView.setHtml` 那样随内容自适应高度，这里退化为固定高度 + 内部滚动。
/// `<useweb>` 依赖的 `WebCacheManager` / `source` / `java` 三个 JS 注入接口
/// 在 Flutter 侧无等价物，故仅开启 JS、不注入这些桥，依赖桥的页面能力受限。

/// 简介分派类型。
enum IntroKind { plain, useweb, usehtml, markdown }

class IntroSpec {
  final IntroKind kind;

  /// 去掉前缀与末尾闭合标签后的正文（plain 时为原始简介全文）。
  final String content;

  const IntroSpec(this.kind, this.content);
}

/// 按前缀解析简介（逐字`startsWith` +
/// `lastIndexOf("<")` + `substring(prefixLen, lastIndex)` 语义）。
///
/// 约定形如 `<useweb>HTML</useweb>`：末尾闭合标签起始的 `<` 即
/// `lastIndexOf("<")`，正文为两标签之间的内容。若找不到闭合标签
/// （`lastIndex < 前缀长度`），E 直接把整段当纯文本展示，此处保持一致。
IntroSpec parseIntro(String? intro) {
  if (intro == null || intro.isEmpty) return const IntroSpec(IntroKind.plain, '');
  const prefixes = <IntroKind, String>{
    IntroKind.useweb: '<useweb>',
    IntroKind.usehtml: '<usehtml>',
    IntroKind.markdown: '<md>',
  };
  for (final e in prefixes.entries) {
    if (intro.startsWith(e.value)) {
      final last = intro.lastIndexOf('<');
      // E: lastIndex < 前缀长度 → 无闭合标签，整段当纯文本展示。
      if (last < e.value.length) return IntroSpec(IntroKind.plain, intro);
      return IntroSpec(e.key, intro.substring(e.value.length, last));
    }
  }
  return IntroSpec(IntroKind.plain, intro);
}

/// `<useweb>` 的 baseUrl： `bookUrl.takeIf { startsWith("http") }
/// ?.substringBefore(",")`，仅 http(s) 且取逗号前第一段。
String? usewebBaseUrl(String? bookUrl) {
  if (bookUrl == null || bookUrl.isEmpty) return null;
  final u = bookUrl.split(',').first.trim();
  if (!u.toLowerCase().startsWith('http')) return null;
  return u;
}

/// 简介内链接的处理方式。
enum IntroLinkAction {
  /// http/https：WebView 内正常加载。
  allow,

  /// legado/yuedu：跳在线导入（`OnLineImportActivity`）。
  onlineImport,

  /// 其它 scheme：经用户确认后用外部 App 打开。
  external,
}

IntroLinkAction classifyIntroUri(Uri uri) {
  final s = uri.scheme.toLowerCase();
  if (s == 'http' || s == 'https') return IntroLinkAction.allow;
  if (s == 'legado' || s == 'yuedu') return IntroLinkAction.onlineImport;
  return IntroLinkAction.external;
}

/// 把 `legado`/`yuedu` scheme 归一化为 [DeepLinkService] 可识别的链接。
/// 其中两者都进 `OnLineImportActivity`；本项目 `handleLink` 仅认 `legado:`，
/// 故 `yuedu:` 改写为 `legado:` 后复用在线导入分派。
String onlineImportLink(Uri uri) {
  if (uri.scheme.toLowerCase() == 'yuedu') {
    return uri.replace(scheme: 'legado').toString();
  }
  return uri.toString();
}

/// 极简 Markdown → HTML 转换器（供 `<md>` 降级渲染，纯函数便于回归）。
///
/// 覆盖书源简介最常见子集：标题、`**粗**`/`*斜*`/`` `码` ``、链接、图片、
/// 无序/有序列表、引用、分隔线、围栏代码块、表格、段落。够用即可，
/// 不追求 CommonMark 全兼容，采用轻量的降级实现。
String markdownToHtml(String md) {
  final lines = const LineSplitter().convert(md.replaceAll('\r\n', '\n'));
  final buf = StringBuffer();
  final codeBuf = StringBuffer();
  bool inUl = false, inOl = false, inQuote = false, inCode = false;
  bool inTable = false, tableHeaderDone = false;

  void closeUl() {
    if (inUl) {
      buf.writeln('</ul>');
      inUl = false;
    }
  }

  void closeOl() {
    if (inOl) {
      buf.writeln('</ol>');
      inOl = false;
    }
  }

  void closeQuote() {
    if (inQuote) {
      buf.writeln('</blockquote>');
      inQuote = false;
    }
  }

  void closeTable() {
    if (inTable) {
      buf.writeln('</table>');
      inTable = false;
      tableHeaderDone = false;
    }
  }

  void closeBlocks() {
    closeUl();
    closeOl();
    closeQuote();
    closeTable();
  }

  for (final line in lines) {
    final trimmed = line.trim();

    // 围栏代码块
    if (trimmed.startsWith('```')) {
      if (inCode) {
        buf.writeln('<pre><code>${_escapeHtml(codeBuf.toString())}</code></pre>');
        codeBuf.clear();
        inCode = false;
      } else {
        closeBlocks();
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      codeBuf.writeln(line);
      continue;
    }

    if (trimmed.isEmpty) {
      closeBlocks();
      continue;
    }

    // 表格行（含 `| --- |` 分隔行）
    if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.length > 2) {
      final raw = trimmed.substring(1, trimmed.length - 1).split('|');
      final isSep = raw.every((c) => RegExp(r'^\s*:?-{2,}:?\s*$').hasMatch(c));
      if (isSep) continue;
      if (!inTable) {
        closeUl();
        closeOl();
        closeQuote();
        buf.writeln('<table border="1" style="border-collapse:collapse">');
        inTable = true;
        tableHeaderDone = false;
      }
      final tag = tableHeaderDone ? 'td' : 'th';
      buf.writeln('<tr>${raw.map((c) => '<$tag>${_inline(c.trim())}</$tag>').join()}</tr>');
      tableHeaderDone = true;
      continue;
    }
    closeTable();

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      closeBlocks();
      final n = heading.group(1)!.length;
      buf.writeln('<h$n>${_inline(heading.group(2)!)}</h$n>');
      continue;
    }
    if (RegExp(r'^(\*{3,}|-{3,}|_{3,})$').hasMatch(trimmed)) {
      closeBlocks();
      buf.writeln('<hr/>');
      continue;
    }
    if (trimmed.startsWith('> ')) {
      closeUl();
      closeOl();
      if (!inQuote) {
        buf.writeln('<blockquote>');
        inQuote = true;
      }
      buf.writeln('${_inline(trimmed.substring(2))}<br/>');
      continue;
    }
    closeQuote();

    final ul = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    if (ul != null) {
      closeOl();
      if (!inUl) {
        buf.writeln('<ul>');
        inUl = true;
      }
      buf.writeln('<li>${_inline(ul.group(1)!)}</li>');
      continue;
    }
    closeUl();

    final ol = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
    if (ol != null) {
      if (!inOl) {
        buf.writeln('<ol>');
        inOl = true;
      }
      buf.writeln('<li>${_inline(ol.group(1)!)}</li>');
      continue;
    }
    closeOl();

    buf.writeln('<p>${_inline(trimmed)}</p>');
  }
  if (inCode) {
    buf.writeln('<pre><code>${_escapeHtml(codeBuf.toString())}</code></pre>');
  }
  closeBlocks();
  return buf.toString();
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _inline(String s) {
  var out = _escapeHtml(s);
  out = out.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)'),
      (m) => '<img src="${m.group(2)}" alt="${m.group(1)}"/>');
  out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'),
      (m) => '<a href="${m.group(2)}">${m.group(1)}</a>');
  out = out.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => '<b>${m.group(1)}</b>');
  out = out.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => '<b>${m.group(1)}</b>');
  out = out.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => '<i>${m.group(1)}</i>');
  out = out.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m.group(1)}</code>');
  return out;
}

/// 把正文包成带 viewport / 暗色感知 CSS 的 HTML 文档；
/// `<useweb>` 用原始 HTML（相对资源靠 [usewebBaseUrl] 解析），不包裹。
String buildIntroDocument(String body,
    {required bool dark, required bool useweb}) {
  if (useweb) return body;
  final bg = dark ? '#121212' : '#ffffff';
  final fg = dark ? '#e0e0e0' : '#222222';
  return '<!DOCTYPE html><html><head>'
      '<meta name="viewport" content="width=device-width, initial-scale=1"/>'
      '<style>body{background:$bg;color:$fg;font-size:15px;line-height:1.7;'
      'margin:12px;word-break:break-word;}'
      'img{max-width:100%;height:auto;} a{color:#3f7ac0;}'
      'table{max-width:100%;} pre{white-space:pre-wrap;background:#8882;'
      'padding:8px;border-radius:6px;} code{font-family:monospace;}'
      'blockquote{border-left:3px solid #888;margin:4px 0;padding-left:10px;}'
      '</style></head><body>$body</body></html>';
}

/// 富文本简介视图。plain 退化为普通 [Text]；其余用固定高度 WebView 渲染。
class IntroRichView extends StatelessWidget {
  final IntroSpec spec;
  final String? bookUrl;
  final double height;
  final TextStyle? plainStyle;

  const IntroRichView({
    super.key,
    required this.spec,
    this.bookUrl,
    this.height = 360,
    this.plainStyle,
  });

  @override
  Widget build(BuildContext context) {
    final kind = spec.kind;
    if (kind == IntroKind.plain) {
      return Text(
        spec.content.isEmpty ? '暂无简介' : spec.content,
        style: plainStyle,
      );
    }
    final useweb = kind == IntroKind.useweb;
    final body = kind == IntroKind.markdown
        ? markdownToHtml(spec.content)
        : spec.content;
    final html = buildIntroDocument(body,
        dark: Theme.of(context).brightness == Brightness.dark, useweb: useweb);
    final base = useweb ? usewebBaseUrl(bookUrl) : null;
    return ClipRRect(
      borderRadius: AppRadius.sAll,
      child: SizedBox(
        height: height,
        // 平台差异：WebView 无内容自适应高度，退化为固定高 + 内部滚动。
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: html,
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: base != null ? WebUri(base) : null,
          ),
          initialSettings: InAppWebViewSettings(
            // 仅 <useweb> 开 JS；<usehtml>/<md> 不需脚本。
            javaScriptEnabled: useweb,
            useShouldOverrideUrlLoading: true,
            supportZoom: true,
            builtInZoomControls: true,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          ),
          shouldOverrideUrlLoading: (controller, action) =>
              _onNavigate(context, action.request.url),
          onLongPressHitTestResult: (controller, hit) =>
              _onLongPress(context, hit),
        ),
      ),
    );
  }

  Future<NavigationActionPolicy> _onNavigate(BuildContext context, Uri? uri) async {
    if (uri == null) return NavigationActionPolicy.CANCEL;
    // initialData / baseUrl 加载本身是 about/data，放行避免误弹外部确认。
    final s = uri.scheme.toLowerCase();
    if (s.isEmpty || s == 'about' || s == 'data' || s == 'file') {
      return NavigationActionPolicy.ALLOW;
    }
    switch (classifyIntroUri(uri)) {
      case IntroLinkAction.allow:
        return NavigationActionPolicy.ALLOW;
      case IntroLinkAction.onlineImport:
        // E: legado/yuedu → OnLineImportActivity（在线导入）。
        await DeepLinkService.instance.handleLink(onlineImportLink(uri));
        return NavigationActionPolicy.CANCEL;
      case IntroLinkAction.external:
        // E: longSnackbar(R.string.jump_to_another_app, confirm) { openUrl }。
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text('跳转到其它应用：$uri'),
          action: SnackBarAction(
            label: '打开',
            onPressed: () async {
              final u = Uri.tryParse(uri.toString());
              if (u != null && await canLaunchUrl(u)) {
                await launchUrl(u, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ));
        return NavigationActionPolicy.CANCEL;
    }
  }

  /// 长按图片看大图。
  Future<void> _onLongPress(
      BuildContext context, InAppWebViewHitTestResult hit) async {
    final t = hit.type;
    final isImage = t == InAppWebViewHitTestResultType.IMAGE_TYPE ||
        t == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;
    final src = hit.extra;
    if (!isImage || src == null || src.isEmpty || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => IntroImagePreview(url: src),
    ));
  }
}

/// 图片长按大图预览。
class IntroImagePreview extends StatelessWidget {
  final String url;
  const IntroImagePreview({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('查看图片')),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: _image(),
        ),
      ),
    );
  }

  Widget _image() {
    if (url.startsWith('data:')) {
      try {
        final comma = url.indexOf(',');
        if (comma >= 0) {
          return Image.memory(base64Decode(url.substring(comma + 1)),
              fit: BoxFit.contain);
        }
      } catch (_) {}
    }
    // 本地封面路径（E: PhotoDialog(path, isBook=true)）。
    if (!url.startsWith('http')) {
      return Image.file(
        File(url),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const AppEmptyState(
          icon: Icons.broken_image_outlined,
          title: '图片加载失败',
          message: '请返回后重试',
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const AppEmptyState(
        icon: Icons.broken_image_outlined,
        title: '图片加载失败',
        message: '请检查书源图片规则或网络后重试',
      ),
    );
  }
}

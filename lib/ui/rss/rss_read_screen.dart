import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iw;
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/http/rss_service.dart';

/// RSS文章阅读页面 - 对齐原版RssReadScreen
/// * ruleContent 为空：以文本展示描述。
/// * ruleContent 产出 HTML：用 WebView 渲染（适配 articleStyle=2 等特殊源）。
class RssReadScreen extends StatefulWidget {
  const RssReadScreen({
    super.key,
    required this.article,
    this.source,
  });
  final RssArticle article;
  final RssSource? source;

  @override
  State<RssReadScreen> createState() => _RssReadScreenState();
}

class _RssReadScreenState extends State<RssReadScreen> {
  final _db = DatabaseService();
  late RssArticle _article;
  bool _isFavorite = false;
  double _fontSize = 18;

  bool _loading = true;
  String _body = '';
  bool _isHtml = false;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _isFavorite = _article.favorite == 1;
    _load();
  }

  bool get _hasContentRule =>
      (widget.source?.ruleContent ?? '').trim().isNotEmpty;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      String? body;
      if (widget.source != null && _hasContentRule) {
        body = await RssService()
            .fetchArticleContent(widget.source!, _article);
        _article.content = body;
      } else {
        body = _article.content ?? _article.description ?? '';
      }
      final trimmed = (body ?? '').trim();
      final html = _looksLikeHtml(trimmed);
      if (mounted) {
        setState(() {
          _body = trimmed;
          _isHtml = html;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _body = '内容加载失败: $e';
          _isHtml = false;
          _loading = false;
        });
      }
    }
  }

  bool _looksLikeHtml(String s) {
    if (!s.contains('<')) return false;
    final lower = s.toLowerCase();
    return lower.contains('<html') ||
        lower.contains('<body') ||
        lower.contains('<div') ||
        lower.contains('<p') ||
        lower.contains('<script') ||
        lower.contains('<img');
  }

  Future<void> _toggleFavorite() async {
    setState(() => _isFavorite = !_isFavorite);
    if (_article.id != null) {
      await _db.toggleRssFavorite(_article.id!, _isFavorite ? 1 : 0);
    }
  }

  void _showTextMenu() {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: const Icon(Icons.text_increase), title: const Text('增大字体'),
        onTap: () { setState(() => _fontSize = (_fontSize + 2).clamp(12, 36)); Navigator.pop(context); },
      ),
      ListTile(
        leading: const Icon(Icons.text_decrease), title: const Text('减小字体'),
        onTap: () { setState(() => _fontSize = (_fontSize - 2).clamp(12, 36)); Navigator.pop(context); },
      ),
      ListTile(
        leading: const Icon(Icons.copy), title: const Text('复制全文'),
        onTap: () { Clipboard.setData(ClipboardData(text: '${_article.title}\n\n$_body')); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
      ),
      ListTile(
        leading: const Icon(Icons.open_in_browser), title: const Text('浏览器打开'),
        onTap: () { Navigator.pop(context); _openOriginal(); },
      ),
    ])));
  }

  void _openOriginal() {
    if (_article.link.isEmpty) return;
    launchUrl(Uri.parse(_article.link), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_article.sourceName ?? '文章', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
            onPressed: _toggleFavorite,
          ),
          if (!_isHtml)
            IconButton(icon: const Icon(Icons.text_fields), onPressed: _showTextMenu),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'browser') _openOriginal();
              if (v == 'share') Share.share('${_article.title}\n${_article.link}');
              if (v == 'copy_link') { Clipboard.setData(ClipboardData(text: _article.link)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制'))); }
              if (v == 'reload') _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'browser', child: Text('浏览器打开')),
              PopupMenuItem(value: 'share', child: Text('分享')),
              PopupMenuItem(value: 'copy_link', child: Text('复制链接')),
              PopupMenuItem(value: 'reload', child: Text('重新加载')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isHtml
              ? _HtmlBody(html: _body, baseUrl: _article.link)
              : _TextBody(
                  article: _article,
                  body: _body,
                  fontSize: _fontSize,
                  onOriginal: _openOriginal,
                ),
    );
  }
}

/// HTML 正文：WebView 渲染（片段自动包裹为完整文档）。
class _HtmlBody extends StatelessWidget {
  const _HtmlBody({required this.html, required this.baseUrl});
  final String html;
  final String baseUrl;

  String _document() {
    final lower = html.toLowerCase();
    if (lower.contains('<html') || lower.contains('<!doctype')) return html;
    return '''<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
 body{margin:14px;line-height:1.8;font-size:16px;color:#1c1b1f;word-wrap:break-word;}
 img{max-width:100%;height:auto;border-radius:6px;}
 a{color:#1565c0;}
 pre{white-space:pre-wrap;word-wrap:break-word;}
</style></head>
<body>$html</body></html>''';
  }

  @override
  Widget build(BuildContext context) {
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
    );
  }
}

/// 文本正文
class _TextBody extends StatelessWidget {
  const _TextBody({
    required this.article,
    required this.body,
    required this.fontSize,
    required this.onOriginal,
  });
  final RssArticle article;
  final String body;
  final double fontSize;
  final VoidCallback onOriginal;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(article.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4)),
        const SizedBox(height: 12),
        if ((article.image ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Image.network(article.image!,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        Row(children: [
          if (article.author != null) ...[
            Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(article.author!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(width: 12),
          ],
          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(article.pubDate != null ? DateTime.fromMillisecondsSinceEpoch(article.pubDate!).toString().substring(0, 16) : '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
        const Divider(height: 24),
        if (body.isNotEmpty)
          Text(body, style: TextStyle(fontSize: fontSize, height: 1.8)),
        const SizedBox(height: 24),
        if (article.link.isNotEmpty)
          Center(child: TextButton.icon(
            onPressed: onOriginal,
            icon: const Icon(Icons.open_in_browser), label: const Text('阅读原文'),
          )),
        const SizedBox(height: 40),
      ]),
    );
  }
}

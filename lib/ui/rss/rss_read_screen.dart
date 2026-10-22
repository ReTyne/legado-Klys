import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iw;
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/readaloud/tts_service.dart';
import 'package:legado_md3/ui/book/read/tts_player_screen.dart';

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

  // ===== 朗读（TTS）=====
  final TtsService _tts = TtsService();
  /// 朗读模式是否开启（迷你控制条可见）
  bool _aloudOn = false;
  /// 是否正在播放（非暂停）
  bool _aloudPlaying = false;
  /// 当前朗读段落索引
  int _aloudIndex = 0;
  /// 正文段落列表（按 \n 切分）
  List<String> _aloudParagraphs = [];
  final GlobalKey _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _isFavorite = _article.favorite == 1;
    _load();
  }

  @override
  void dispose() {
    _tts.onSegmentStart = null;
    _tts.onComplete = null;
    _tts.onError = null;
    _tts.stop();
    _tts.dispose();
    super.dispose();
  }

  /// 朗读进度持久化 key（按文章）
  String get _ttsProgressKey => 'rss_tts_${_article.id ?? _article.link}';

  Future<void> _saveAloudProgress(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_ttsProgressKey, index);
    } catch (_) {}
  }

  Future<void> _startAloud() async {
    if (_loading || _body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无可朗读的正文')));
      return;
    }
    // 正文可能带 HTML（WebView 渲染的源），先剥标签再按段切分
    final plain = _isHtml ? TtsService.stripHtml(_body) : _body;
    final paragraphs = TtsService.splitParagraphs(plain);
    if (paragraphs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无可朗读的正文')));
      return;
    }
    _aloudParagraphs = paragraphs;
    // 恢复上次朗读进度
    var start = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      start = prefs.getInt(_ttsProgressKey) ?? 0;
    } catch (_) {}
    if (start < 0 || start >= paragraphs.length) start = 0;

    _tts.onSegmentStart = (i, text) {
      if (!mounted) return;
      setState(() => _aloudIndex = i);
      _saveAloudProgress(i);
      _scrollToCurrentParagraph();
    };
    _tts.onComplete = () {
      _saveAloudProgress(0); // 读完后重进从头开始
      if (!mounted) return;
      setState(() { _aloudOn = false; _aloudPlaying = false; });
    };
    _tts.onError = (msg) {
      if (!mounted) return;
      setState(() => _aloudPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('朗读出错: $msg')));
    };
    _tts.setTextSegments(paragraphs, startIndex: start);
    setState(() { _aloudOn = true; _aloudPlaying = true; _aloudIndex = start; });
    await _tts.play();
  }

  /// 朗读中自动滚动到当前段
  void _scrollToCurrentParagraph() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _highlightKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.1,
          curve: Curves.easeInOut);
    });
  }

  /// AppBar 朗读按钮 / 迷你条播放键：开始 / 暂停 / 恢复
  Future<void> _toggleAloud() async {
    if (!_aloudOn) {
      await _startAloud();
      return;
    }
    if (_aloudPlaying) {
      await _tts.pause();
      if (mounted) setState(() => _aloudPlaying = false);
    } else {
      await _tts.resume();
      if (mounted) setState(() => _aloudPlaying = _tts.isSpeaking);
    }
  }

  /// 退出朗读（停止并收起迷你条，保留进度）
  Future<void> _exitAloud() async {
    await _tts.stop();
    await _saveAloudProgress(_tts.currentIndex);
    if (mounted) setState(() { _aloudOn = false; _aloudPlaying = false; });
  }

  /// 迷你朗读控制条
  Widget _buildAloudBar() {
    if (!_aloudOn) return const SizedBox.shrink();
    final total = _aloudParagraphs.isNotEmpty ? _aloudParagraphs.length : _tts.totalCount;
    return TtsControlBar(
      isPlaying: _aloudPlaying,
      progressText: total > 0 ? '正在朗读第 ${_aloudIndex + 1} / $total 段' : null,
      progress: total > 0 ? (_aloudIndex + 1) / total : null,
      onPlayPause: _toggleAloud,
      onPrev: () => _tts.previous(),
      onNext: () => _tts.next(),
      onExit: _exitAloud,
    );
  }

  bool get _hasContentRule =>
      (widget.source?.ruleContent ?? '').trim().isNotEmpty;

  /// 源是否配置了 WebView 增强（自定义 CSS / 注入脚本 / 预加载脚本）。
  /// 配置了任一项即走 HTML 渲染，保证这些字段真正生效。
  bool get _hasWebAssets {
    final s = widget.source;
    if (s == null) return false;
    return (s.style ?? '').trim().isNotEmpty ||
        (s.injectJs ?? '').trim().isNotEmpty ||
        (s.preloadJs ?? '').trim().isNotEmpty;
  }

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
      // 配了 style/injectJs/preloadJs 时即使正文不是典型 HTML 也走 WebView，
      // 否则自定义 CSS/脚本无处生效
      final html = _looksLikeHtml(trimmed) ||
          (_hasWebAssets && trimmed.isNotEmpty);
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
    return PopScope(
      // 朗读中返回需确认，避免误触退出丢失朗读
      canPop: !_aloudOn,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('退出阅读'),
            content: const Text('正在朗读正文，要停止朗读并退出吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('停止并退出')),
            ],
          ),
        );
        if (leave != true || !mounted) return;
        await _exitAloud();
        // 等一帧让 PopScope 的 canPop 更新后再退栈
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_article.sourceName ?? '文章', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: Icon(_aloudOn
                  ? (_aloudPlaying ? Icons.pause : Icons.play_arrow)
                  : Icons.volume_up_outlined),
              tooltip: _aloudOn
                  ? (_aloudPlaying ? '暂停朗读' : '继续朗读')
                  : '朗读',
              onPressed: _loading ? null : _toggleAloud,
            ),
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
            : Column(
                children: [
                  Expanded(
                    child: _isHtml
                        ? _HtmlBody(
                            html: _body,
                            baseUrl: _article.link,
                            style: widget.source?.style,
                            injectJs: widget.source?.injectJs,
                            preloadJs: widget.source?.preloadJs,
                            shouldOverrideUrlLoading:
                                widget.source?.shouldOverrideUrlLoading,
                          )
                        : _TextBody(
                            article: _article,
                            paragraphs: TtsService.splitParagraphs(_body),
                            fontSize: _fontSize,
                            onOriginal: _openOriginal,
                            highlightIndex: _aloudOn ? _aloudIndex : -1,
                            highlightKey: _highlightKey,
                          ),
                  ),
                  _buildAloudBar(),
                ],
              ),
      ),
    );
  }
}

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

/// 文本正文（按段渲染，朗读时高亮当前段）
class _TextBody extends StatelessWidget {
  const _TextBody({
    required this.article,
    required this.paragraphs,
    required this.fontSize,
    required this.onOriginal,
    this.highlightIndex = -1,
    this.highlightKey,
  });
  final RssArticle article;
  final List<String> paragraphs;
  final double fontSize;
  final VoidCallback onOriginal;
  /// 朗读中的段落索引，-1 表示未朗读
  final int highlightIndex;
  final GlobalKey? highlightKey;

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
        for (var i = 0; i < paragraphs.length; i++)
          Container(
            key: i == highlightIndex ? highlightKey : null,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: i == highlightIndex
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                : null,
            decoration: i == highlightIndex
                ? BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.45),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(paragraphs[i],
                style: TextStyle(fontSize: fontSize, height: 1.8)),
          ),
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

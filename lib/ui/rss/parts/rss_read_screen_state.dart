/// 由 rss_read_screen.dart 按「一类一文件」拆出的 _RssReadScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rss_read_screen.dart';


class _RssReadScreenState extends State<RssReadScreen> {
  final _db = DatabaseService();
  late RssArticle _article;
  bool _isFavorite = false;
  double _fontSize = 18;

  bool _loading = true;
  String _body = '';
  bool _isHtml = false;
  String? _error;

  // ===== 阅读记录 / 续读 =====
  static const _recordEnabledKey = 'rss_read_record_enabled';
  final ScrollController _scrollController = ScrollController();
  double _lastOffset = 0;
  bool _recordEnabled = true; // 全局「开启记录」开关
  bool _recordAllowed = true; // 该 link 的记录开关
  double? _pendingRestorePos;
  bool _restored = false;
  Timer? _persistTimer;

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
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    unawaited(_persistRecord());
    _tts.onSegmentStart = null;
    _tts.onComplete = null;
    _tts.onError = null;
    _tts.stop();
    _tts.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ===== 阅读记录 / 续读 =====

  void _onScroll() {
    if (_scrollController.hasClients) {
      _lastOffset = _scrollController.offset;
      _schedulePersist();
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persistRecord());
    });
  }

  /// 读取全局「开启记录」开关与该文章的记录（续读位置、per-link 开关）。
  Future<void> _initRecordSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recordEnabled = prefs.getBool(_recordEnabledKey) ?? true;
    } catch (_) {}
    try {
      final rec = await _db.getRssReadRecord(_article.link);
      _recordAllowed = rec?.enabled != 0;
      _pendingRestorePos = rec?.durPos;
    } catch (_) {}
  }

  /// 内容渲染后把滚动位置恢复到上次记录的 durPos。
  void _applyRestore() {
    if (_restored || _pendingRestorePos == null) return;
    if (_isHtml || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final pos = _pendingRestorePos!.clamp(0.0, max);
    _scrollController.jumpTo(pos);
    _lastOffset = pos;
    _pendingRestorePos = null;
    _restored = true;
  }

  /// 上报 durPos（ScrollController.offset）。全局开关或该 link 关闭记录时跳过。
  Future<void> _persistRecord() async {
    if (_article.link.isEmpty || !_recordEnabled || !_recordAllowed) return;
    try {
      final rec = await _db.getRssReadRecord(_article.link);
      await _db.upsertRssReadRecord(RssReadRecord(
        id: rec?.id,
        link: _article.link,
        title: _article.title,
        sourceUrl: _article.sourceUrl ?? '',
        durPos: _lastOffset,
        readTime: DateTime.now().millisecondsSinceEpoch,
        enabled: rec?.enabled ?? 1,
      ));
    } catch (_) {}
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _initRecordSettings();
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
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _applyRestore());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
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
    showAppMenuSheet(context, title: '正文选项', items: [
      AppMenuSheetItem(
        title: '增大字体',
        icon: Icons.text_increase,
        onTap: () => setState(() => _fontSize = (_fontSize + 2).clamp(12, 36)),
      ),
      AppMenuSheetItem(
        title: '减小字体',
        icon: Icons.text_decrease,
        onTap: () => setState(() => _fontSize = (_fontSize - 2).clamp(12, 36)),
      ),
      AppMenuSheetItem(
        title: '复制全文',
        icon: Icons.copy,
        onTap: () {
          Clipboard.setData(ClipboardData(text: '${_article.title}\n\n$_body'));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已复制')));
        },
      ),
      AppMenuSheetItem(
        title: '浏览器打开',
        icon: Icons.open_in_browser,
        onTap: _openOriginal,
      ),
    ]);
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
        if (didPop) {
          await _persistRecord();
          return;
        }
        final leave = await showAppConfirmDialog(
          context,
          title: '退出阅读',
          content: '正在朗读正文，要停止朗读并退出吗？',
          confirmText: '停止并退出',
          danger: true,
        );
        if (!leave || !mounted) return;
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
              tooltip: _isFavorite ? '取消收藏' : '收藏',
              onPressed: _toggleFavorite,
            ),
            if (!_isHtml)
              IconButton(
                icon: const Icon(Icons.text_fields),
                tooltip: '正文选项',
                onPressed: _showTextMenu,
              ),
            PopupMenuButton<String>(
              tooltip: '更多',
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
            ? const AppLoadingIndicator()
            : _error != null
                ? AppErrorState(message: _error!, onRetry: _load)
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
                                scrollController: _scrollController,
                              ),
                      ),
                      _buildAloudBar(),
                    ],
                  ),
      ),
    );
  }
}

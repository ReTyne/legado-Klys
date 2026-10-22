import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 视频播放器（对齐 legado-E 的视频播放能力，含弹幕基础支持）。
///
/// 说明（与原生能力的差异，均为缺少插件导致的降级）：
/// * 画中画：无 pip 插件，用「当前页面内可拖拽悬浮小窗」降级替代；
/// * 手势调亮度：无 screen_brightness 插件，改为叠加一层黑色遮罩模拟，并持久化；
/// * 手势调音量：无 volume_controller 插件，左侧竖向手势不生效。
class VideoPlayerScreen extends StatefulWidget {
  final Book book;
  final int initialChapter;
  const VideoPlayerScreen({super.key, required this.book, this.initialChapter = 0});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  static const List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  /// 亮度遮罩不透明度（0 不压暗，0.8 最暗）
  static const String _prefDim = 'video_dim_value';
  static const double _maxDim = 0.8;
  static final RegExp _videoExt =
      RegExp(r'\.(mp4|m3u8|webm|flv|ts|mkv|mov|avi)(\?|#|$)', caseSensitive: false);
  static final RegExp _urlRe = RegExp(r'''https?://[^\s"'<>\\]+''');

  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  VideoPlayerController? _controller;
  BookSource? _source;
  List<BookChapter> _chapters = [];
  int _index = 0;
  bool _loading = true;
  String? _error;
  bool _showControls = true;
  bool _playing = false;
  double _rate = 1.0;

  /// 同一集解析出的多个播放地址（线路）
  List<String> _lines = [];
  int _lineIndex = 0;
  final Map<int, List<String>> _lineCache = {};

  // 弹幕
  List<_DanmakuItem> _danmaku = [];
  bool _danmakuOn = true;

  // 全屏 / 悬浮小窗 / 锁定 / 亮度遮罩
  bool _isFullscreen = false;
  bool _pip = false;
  Offset? _pipOffset;
  bool _locked = false;
  double _dim = 0.0;
  bool _volumeHintShown = false;

  // 手势快进预览
  Duration? _seekPreview;
  Duration _seekBase = Duration.zero;

  // 进度条拖动中锁定，避免被 100ms 轮询覆盖造成抖动
  bool _seeking = false;
  double _seekValue = 0;
  Timer? _hideTimer;
  int _lastSaveMs = 0;

  String _positionKey(int idx) => 'video_position_${widget.book.name}_$idx';

  @override
  void initState() {
    super.initState();
    _index = widget.initialChapter;
    _load();
  }

  @override
  void dispose() {
    unawaited(_savePosition(force: true));
    _hideTimer?.cancel();
    final c = _controller;
    _controller = null;
    unawaited(c?.dispose());
    unawaited(_restoreSystemUi());
    super.dispose();
  }

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
  }

  Future<void> _load() async {
    await _loadPrefs();
    final list = await _db.getChapters(widget.book.name, widget.book.author);
    if (!mounted) return;
    _chapters = list.where((c) => !c.isVolume).toList();
    if (_index < 0 || _index >= _chapters.length) _index = 0;
    setState(() {});
    final saved = await _loadPosition(_index);
    await _playAt(_index, line: saved?.line ?? 0, startAt: saved?.position);
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      _dim = (p.getDouble(_prefDim) ?? 0.0).clamp(0.0, _maxDim).toDouble();
    } catch (_) {}
  }

  Future<void> _persistDim() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_prefDim, _dim);
    } catch (_) {}
  }

  // ==================== 进度记忆 ====================

  Future<void> _savePosition({bool force = false}) async {
    final c = _controller;
    if (_chapters.isEmpty || c == null || !c.value.isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastSaveMs < 3000) return;
    _lastSaveMs = now;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _positionKey(_index), '$_lineIndex|${c.value.position.inMilliseconds}');
    } catch (_) {}
  }

  Future<_VideoResume?> _loadPosition(int idx) async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_positionKey(idx));
      if (v == null) return null;
      final parts = v.split('|');
      if (parts.length != 2) return null;
      final line = int.tryParse(parts[0]) ?? 0;
      final ms = int.tryParse(parts[1]) ?? 0;
      if (line <= 0 && ms <= 0) return null;
      return _VideoResume(line, Duration(milliseconds: ms));
    } catch (_) {
      return null;
    }
  }

  // ==================== 数据源 ====================

  bool _looksVideo(String s) => _videoExt.hasMatch(s.trim());

  static List<String> _parseUrls(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const [];
    if (text.startsWith('[')) {
      try {
        final arr = jsonDecode(text);
        if (arr is List) {
          final out = <String>[];
          for (final e in arr) {
            if (e is String) {
              if (e.startsWith('http')) out.add(e);
            } else if (e is Map) {
              final u = (e['url'] ?? e['src'] ?? e['playUrl'])?.toString();
              if (u != null && u.startsWith('http')) out.add(u);
            }
          }
          if (out.isNotEmpty) return out;
        }
      } catch (_) {}
    }
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.startsWith('http'))
        .toList();
    if (lines.isNotEmpty) return lines;
    final m = _urlRe.firstMatch(text);
    if (m != null) {
      final u = m.group(0)!;
      if (_videoExt.hasMatch(u) || !text.contains('<')) return [u];
    }
    return const [];
  }

  Future<List<String>> _resolveLines(int idx) async {
    final ch = _chapters[idx];
    final fromContent = _parseUrls(ch.content);
    if (fromContent.isNotEmpty) return fromContent;
    if (ch.url.startsWith('http') && _looksVideo(ch.url)) return [ch.url];
    try {
      _source ??= await _db.getSource(widget.book.origin ?? '');
      final source = _source;
      if (source != null) {
        final raw = await _engine.getVideoContent(source, ch.url,
            bookInfo: {'name': widget.book.name, 'author': widget.book.author},
            chapter: {'index': idx, 'title': ch.title, 'url': ch.url});
        final parsed = _parseUrls(raw);
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _playAt(int idx, {int line = 0, Duration? startAt}) async {
    if (idx < 0 || idx >= _chapters.length) return;
    await _savePosition(force: true);
    final ch = _chapters[idx];
    setState(() {
      _index = idx;
      _loading = true;
      _error = null;
    });
    _tryParseDanmaku(ch.content);
    var urls = _lineCache[idx];
    if (urls == null || urls.isEmpty) {
      urls = await _resolveLines(idx);
      _lineCache[idx] = urls;
    }
    if (!mounted) return;
    if (urls.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无法解析视频地址';
      });
      return;
    }
    _lines = urls;
    final li = line.clamp(0, urls.length - 1);
    setState(() => _lineIndex = li);
    await _initController(urls[li], startAt: startAt);
  }

  Future<void> _switchLine(int line) async {
    if (line == _lineIndex) return;
    await _playAt(_index, line: line);
  }

  Future<void> _initController(String url, {Duration? startAt}) async {
    final old = _controller;
    _controller = null;
    await old?.dispose();
    final lower = url.toLowerCase();
    final formatHint = lower.contains('.m3u8')
        ? VideoFormat.hls
        : lower.contains('.mpd')
            ? VideoFormat.dash
            : VideoFormat.other;
    final c = VideoPlayerController.networkUrl(Uri.parse(url), formatHint: formatHint);
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) return;
      c.addListener(_onControllerUpdate);
      await c.setPlaybackSpeed(_rate);
      if (startAt != null && startAt > Duration.zero && startAt < c.value.duration) {
        await c.seekTo(startAt);
      }
      await c.play();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playing = true;
      });
      _scheduleHideControls();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '视频加载失败: $e';
      });
    }
  }

  void _onControllerUpdate() {
    final c = _controller;
    if (c == null || !mounted) return;
    if (c.value.isPlaying != _playing) {
      setState(() => _playing = c.value.isPlaying);
    }
    if (c.value.hasError && _error == null) {
      setState(() => _error = c.value.errorDescription);
    }
  }

  // ==================== 播放控制 ====================

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      unawaited(c.pause());
      unawaited(_savePosition(force: true));
    } else {
      unawaited(c.play());
      _scheduleHideControls();
    }
    setState(() => _playing = !c.value.isPlaying);
  }

  Future<void> _seekTo(Duration d) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(d);
    setState(() {});
    await _savePosition(force: true);
  }

  void _seekBy(int sec) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final target = c.value.position + Duration(seconds: sec);
    final max = c.value.duration;
    unawaited(_seekTo(target > max ? max : (target.isNegative ? Duration.zero : target)));
  }

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setPlaybackSpeed(rate);
    } catch (_) {}
  }

  void _showRateSheet() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('播放倍速',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _rates
                  .map((r) => ChoiceChip(
                        label: Text('${r}x'),
                        selected: r == _rate,
                        onSelected: (_) {
                          Navigator.pop(c);
                          unawaited(_setRate(r));
                        },
                      ))
                  .toList(),
            ),
          ]),
        ),
      ),
    );
  }

  // ==================== 全屏 / 悬浮小窗 / 锁定 ====================

  Future<void> _setFullscreen(bool v) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
          v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(v
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values);
    } catch (_) {}
    if (mounted) setState(() => _isFullscreen = v);
  }

  void _onBack() {
    if (_isFullscreen) {
      unawaited(_setFullscreen(false));
      return;
    }
    Navigator.of(context).pop();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && !_locked) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  // ==================== 弹幕 ====================

  /// 尝试从章节内容解析弹幕（JSON 数组 [{t/time, text/content}]）。
  void _tryParseDanmaku(String? content) {
    final list = <_DanmakuItem>[];
    final c = content?.trim() ?? '';
    if (c.isEmpty || c.startsWith('http') || c.startsWith('<')) {
      _danmaku = list;
      return;
    }
    try {
      final arr = jsonDecode(c);
      if (arr is List) {
        for (final e in arr) {
          if (e is Map) {
            final t = (e['t'] ?? e['time'] ?? e['seconds']);
            final time = t is num ? t.toDouble() : 0.0;
            final text = (e['text'] ?? e['content'] ?? e['m'] ?? '').toString();
            if (text.isNotEmpty) list.add(_DanmakuItem(time, text));
          }
        }
      }
    } catch (_) {}
    _danmaku = list;
  }

  /// 当前播放位置的弹幕
  List<_DanmakuItem> _danmakuAt(Duration pos) {
    if (!_danmakuOn) return const [];
    final sec = pos.inMilliseconds / 1000.0;
    return _danmaku.where((d) => (d.time - sec).abs() < 3.0).toList();
  }

  void _showDanmakuList() {
    if (_danmaku.isEmpty) {
      _toast('当前视频暂无弹幕');
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('弹幕列表',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ..._danmaku.map((d) => ListTile(
                  dense: true,
                  leading: Text('${d.time.toStringAsFixed(1)}s',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  title: Text(d.text, style: const TextStyle(fontSize: 13)),
                )),
          ],
        ),
      ),
    );
  }

  // ==================== 手势 ====================

  void _onHorizontalDragStart(BoxConstraints cons) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _locked) return;
    _seekBase = c.value.position;
    setState(() => _seekPreview = _seekBase);
  }

  void _onHorizontalDragUpdate(double dx, double width) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _locked) return;
    if (_seekPreview == null) return;
    final delta = Duration(milliseconds: (dx / width * 120000).round());
    var target = _seekBase + delta;
    if (target.isNegative) target = Duration.zero;
    if (target > c.value.duration) target = c.value.duration;
    setState(() => _seekPreview = target);
  }

  void _onHorizontalDragEnd() {
    final target = _seekPreview;
    setState(() => _seekPreview = null);
    if (target != null) unawaited(_seekTo(target));
  }

  void _onVerticalDragUpdate(double dy, double dx, double width) {
    if (_locked) return;
    if (dx < width / 2) {
      // 左侧：系统音量需要 volume_controller 之类的插件，本项目未引入
      if (!_volumeHintShown) {
        _volumeHintShown = true;
        _toast('未集成系统音量插件，不支持手势调节音量');
      }
      return;
    }
    // 右侧：无 screen_brightness 插件，用黑色遮罩模拟亮度调节
    final next = (_dim + dy / 300).clamp(0.0, _maxDim).toDouble();
    if (next == _dim) return;
    setState(() => _dim = next);
  }

  void _onVerticalDragEnd() {
    unawaited(_persistDim());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_setFullscreen(false));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          if (_isFullscreen)
            _buildFullscreenBody()
          else
            SafeArea(child: _buildNormalBody()),
          if (_pip) _buildPipWindow(),
        ]),
      ),
    );
  }

  Widget _buildNormalBody() {
    return Column(children: [
      _buildStage(),
      Expanded(child: _buildInfoPanel()),
    ]);
  }

  Widget _buildFullscreenBody() {
    final c = _controller;
    final ar = c != null && c.value.isInitialized ? c.value.aspectRatio : 16 / 9;
    return Stack(fit: StackFit.expand, children: [
      Center(child: AspectRatio(aspectRatio: ar, child: _buildSurface())),
      ..._buildOverlays(),
    ]);
  }

  Widget _buildStage() {
    final c = _controller;
    final ar = c != null && c.value.isInitialized ? c.value.aspectRatio : 16 / 9;
    return Container(
      color: Colors.black,
      child: Stack(children: [
        AspectRatio(aspectRatio: ar, child: _buildSurface()),
        ..._buildOverlays(),
      ]),
    );
  }

  /// 画面本体：视频纹理 + 亮度遮罩 + 弹幕 + 手势 + 状态提示
  Widget _buildSurface() {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final body = _pip
        ? const Center(
            child: Text('悬浮小窗播放中', style: TextStyle(color: Colors.white70)))
        : (ready
            ? VideoPlayer(c)
            : const Center(child: CircularProgressIndicator(color: Colors.white)));
    return LayoutBuilder(builder: (context, cons) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_locked) return;
          _toggleControls();
        },
        onDoubleTap: () {
          if (_locked) return;
          _togglePlay();
        },
        onHorizontalDragStart: (_) => _onHorizontalDragStart(cons),
        onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d.delta.dx, cons.maxWidth),
        onHorizontalDragEnd: (_) => _onHorizontalDragEnd(),
        onVerticalDragUpdate: (d) =>
            _onVerticalDragUpdate(d.delta.dy, d.globalPosition.dx, cons.maxWidth),
        onVerticalDragEnd: (_) => _onVerticalDragEnd(),
        child: Stack(children: [
          Positioned.fill(child: body),
          // 亮度遮罩（模拟系统亮度，非真实背光）
          IgnorePointer(
            child: Container(color: Color.fromRGBO(0, 0, 0, _dim)),
          ),
          if (ready && !_pip)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: Stack(
                    children: [
                      for (final d in _danmakuAt(c.value.position))
                        _DanmakuText(key: ValueKey(d), text: d.text),
                    ],
                  ),
                ),
              ),
            ),
          if (_loading && !_pip)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => unawaited(_playAt(_index, line: _lineIndex)),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('重试', style: TextStyle(color: Colors.white)),
                  ),
                ]),
              ),
            ),
        ]),
      );
    });
  }

  List<Widget> _buildOverlays() {
    final c = _controller;
    return [
      if (_seekPreview != null)
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Text(
              '${_fmt(_seekPreview!)} / ${_fmt(c?.value.duration ?? Duration.zero)}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      if (_locked)
        Center(
          child: Container(
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(24)),
            child: IconButton(
              icon: const Icon(Icons.lock, color: Colors.white),
              tooltip: '点击解锁',
              onPressed: () => setState(() {
                _locked = false;
                _showControls = true;
              }),
            ),
          ),
        ),
      if (_showControls && !_locked)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showControls = false),
            child: Container(
              color: Colors.black45,
              child: SafeArea(
                child: Column(children: [
                  _buildTopBar(),
                  const Spacer(),
                  _buildBottomBar(),
                ]),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildTopBar() {
    final current = _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _onBack,
        ),
        Expanded(
          child: Text(widget.book.name + (current != null ? ' · ${current.title}' : ''),
              style: const TextStyle(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          icon: Icon(_danmakuOn ? Icons.subtitles : Icons.subtitles_off,
              color: Colors.white),
          tooltip: '弹幕开关',
          onPressed: () => setState(() => _danmakuOn = !_danmakuOn),
        ),
        IconButton(
          icon: const Icon(Icons.lock_outline, color: Colors.white),
          tooltip: '锁定',
          onPressed: () => setState(() => _locked = true),
        ),
        IconButton(
          icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white),
          tooltip: '全屏',
          onPressed: () => unawaited(_setFullscreen(!_isFullscreen)),
        ),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final c = _controller;
    final pos = c?.value.position ?? Duration.zero;
    final dur = c?.value.duration ?? Duration.zero;
    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    final value = (_seeking ? _seekValue : pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);
    var buffered = 0.0;
    if (c != null && c.value.buffered.isNotEmpty) {
      buffered = c.value.buffered.last.end.inMilliseconds.toDouble();
    }
    final buffering = c?.value.isBuffering ?? false;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (buffering)
        const LinearProgressIndicator(minHeight: 2, color: Colors.white),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
            onPressed: _togglePlay,
          ),
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white),
            onPressed: () => _seekBy(-10),
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: maxMs,
              value: value,
              secondaryTrackValue: buffered.clamp(0.0, maxMs),
              activeColor: Colors.white,
              inactiveColor: Colors.white30,
              onChangeStart: (v) => setState(() {
                _seeking = true;
                _seekValue = v;
              }),
              onChanged: (v) => setState(() => _seekValue = v),
              onChangeEnd: (v) {
                setState(() => _seeking = false);
                unawaited(_seekTo(Duration(milliseconds: v.toInt())));
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.forward_10, color: Colors.white),
            onPressed: () => _seekBy(10),
          ),
          Text(_fmt(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton(
            onPressed: _showRateSheet,
            child: Text('${_rate}x', style: const TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: _showEpisodeSheet,
            icon: const Icon(Icons.playlist_play, color: Colors.white, size: 18),
            label: const Text('选集', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: _showDanmakuList,
            icon: const Icon(Icons.subtitles_outlined, color: Colors.white, size: 18),
            label: const Text('弹幕', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _pip = true),
            icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 18),
            label: const Text('悬浮窗', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _buildInfoPanel() {
    final current = _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ListView(
        children: [
          Text(widget.book.name,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('第 ${_index + 1} / ${_chapters.length} 集${current != null ? ' · ${current.title}' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 12),
          _buildChipRow(
            label: '选集',
            count: _chapters.length,
            selected: _index,
            titleOf: (i) => '${i + 1}',
            onTap: (i) => unawaited(_playAt(i)),
          ),
          if (_lines.length > 1) ...[
            const SizedBox(height: 12),
            _buildChipRow(
              label: '线路',
              count: _lines.length,
              selected: _lineIndex,
              titleOf: (i) => '线路 ${i + 1}',
              onTap: (i) => unawaited(_switchLine(i)),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Text('亮度遮罩 ${(_dim * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Expanded(
              child: Slider(
                value: _dim,
                min: 0,
                max: _maxDim,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
                onChanged: (v) => setState(() => _dim = v),
                onChangeEnd: (_) => unawaited(_persistDim()),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildChipRow({
    required String label,
    required int count,
    required int selected,
    required String Function(int) titleOf,
    required ValueChanged<int> onTap,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      const SizedBox(height: 6),
      SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (c, i) => ChoiceChip(
            label: Text(titleOf(i)),
            selected: i == selected,
            onSelected: (_) => onTap(i),
          ),
        ),
      ),
    ]);
  }

  /// 全屏下的选集/线路面板（与竖屏信息面板共用同一套横向列表）
  void _showEpisodeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _buildChipRow(
              label: '选集',
              count: _chapters.length,
              selected: _index,
              titleOf: (i) => '${i + 1}',
              onTap: (i) {
                Navigator.pop(c);
                unawaited(_playAt(i));
              },
            ),
            if (_lines.length > 1) ...[
              const SizedBox(height: 12),
              _buildChipRow(
                label: '线路',
                count: _lines.length,
                selected: _lineIndex,
                titleOf: (i) => '线路 ${i + 1}',
                onTap: (i) {
                  Navigator.pop(c);
                  unawaited(_switchLine(i));
                },
              ),
            ],
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  /// 悬浮小窗：本项目无 pip 插件，这里在当前 Route 上叠一层可拖拽小窗作为降级实现。
  Widget _buildPipWindow() {
    final size = MediaQuery.of(context).size;
    final w = (size.width / 4).clamp(100.0, 200.0).toDouble();
    final h = w * 9 / 16 + 28;
    final base = _pipOffset ?? Offset(size.width - w - 12, size.height - h - 120);
    final c = _controller;
    return Positioned(
      left: base.dx.clamp(0.0, size.width - w),
      top: base.dy.clamp(0.0, size.height - h),
      width: w,
      height: h,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _pipOffset = Offset(
            (base.dx + d.delta.dx).clamp(0.0, size.width - w).toDouble(),
            (base.dy + d.delta.dy).clamp(0.0, size.height - h).toDouble(),
          );
        }),
        child: Material(
          color: Colors.black,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            SizedBox(
              height: h - 28,
              width: w,
              child: GestureDetector(
                onTap: () => setState(() => _pip = false),
                child: c != null && c.value.isInitialized
                    ? VideoPlayer(c)
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
            SizedBox(
              height: 28,
              child: Row(children: [
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.white),
                    onPressed: _togglePlay,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                    tooltip: '返回全屏',
                    onPressed: () => setState(() => _pip = false),
                  ),
                ),
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '关闭并停止',
                    onPressed: () async {
                      final ctrl = _controller;
                      if (ctrl != null) await ctrl.pause();
                      unawaited(_savePosition(force: true));
                      if (mounted) setState(() => _pip = false);
                    },
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 断点续听读取结果：线路下标 + 位置。
class _VideoResume {
  final int line;
  final Duration position;
  const _VideoResume(this.line, this.position);
}

/// 单条弹幕数据。
class _DanmakuItem {
  final double time;
  final String text;
  const _DanmakuItem(this.time, this.text);
}

/// 单条弹幕（从右向左滚动的动画文本）。
class _DanmakuText extends StatefulWidget {
  final String text;
  const _DanmakuText({super.key, required this.text});

  @override
  State<_DanmakuText> createState() => _DanmakuTextState();
}

class _DanmakuTextState extends State<_DanmakuText> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 6))..forward();
    _ac.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        return Positioned(
          top: (widget.text.hashCode % 200).abs().toDouble(),
          left: MediaQuery.of(context).size.width * (1 - t),
          child: Text(widget.text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 视频播放器（对齐 legado-E 的视频播放能力，含弹幕基础支持）。
class VideoPlayerScreen extends StatefulWidget {
  final Book book;
  final int initialChapter;
  const VideoPlayerScreen({super.key, required this.book, this.initialChapter = 0});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  VideoPlayerController? _controller;
  List<BookChapter> _chapters = [];
  int _index = 0;
  bool _loading = true;
  bool _showMenu = false;
  bool _playing = false;
  double _rate = 1.0;
  final List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  // 弹幕列表
  List<_DanmakuItem> _danmaku = [];
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _index = widget.initialChapter;
    _load();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _db.getChapters(widget.book.name, widget.book.author);
    if (!mounted) return;
    setState(() => _chapters = list.where((c) => !c.isVolume).toList());
    _playAt(_index);
  }

  bool _looksVideo(String s) =>
      RegExp(r'\.(mp4|m3u8|webm|flv|ts|mkv|mov)(\?|$)', caseSensitive: false).hasMatch(s.trim());

  /// 尝试从章节内容解析弹幕（JSON 数组 [{t/time, text/content}]）。
  void _tryParseDanmaku(String? content) {
    final list = <_DanmakuItem>[];
    final c = content?.trim() ?? '';
    if (c.isEmpty || c.startsWith('http') || c.startsWith('<')) {
      setState(() => _danmaku = list);
      return;
    }
    try {
      final arr = jsonDecode(c);
      if (arr is List) {
        for (final e in arr) {
          if (e is Map) {
            final t = (e['t'] ?? e['time'] ?? e['seconds']).toDouble() ?? 0.0;
            final text = (e['text'] ?? e['content'] ?? e['m'] ?? '').toString();
            if (text.isNotEmpty) list.add(_DanmakuItem(t, text));
          }
        }
      }
    } catch (_) {}
    setState(() => _danmaku = list);
  }

  Future<void> _playAt(int idx) async {
    if (idx < 0 || idx >= _chapters.length) return;
    setState(() { _index = idx; _loading = true; });
    final ch = _chapters[idx];
    _tryParseDanmaku(ch.content);
    try {
      String? url;
      if (ch.url.startsWith('http') && _looksVideo(ch.url)) {
        url = ch.url;
      } else if (ch.content != null && _looksVideo(ch.content!)) {
        url = ch.content;
      } else {
        final source = await _db.getSource(widget.book.origin ?? '');
        if (source != null) {
          url = await _engine.getVideoContent(source, ch.url,
              bookInfo: {'name': widget.book.name, 'author': widget.book.author},
              chapter: {'index': idx, 'title': ch.title, 'url': ch.url});
        }
      }
      if (url != null && url.isNotEmpty) {
        await _initController(url.trim());
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法解析视频地址')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('视频加载失败: $e')));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _initController(String url) async {
    await _controller?.dispose();
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    await c.initialize();
    await c.play();
    await c.setPlaybackSpeed(_rate);
    c.addListener(() {
      if (mounted) setState(() => _playing = c.value.isPlaying);
    });
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) { c.pause(); } else { c.play(); }
    setState(() {});
  }

  void _cycleRate() {
    final i = (_rates.indexOf(_rate) + 1) % _rates.length;
    setState(() => _rate = _rates[i]);
    _controller?.setPlaybackSpeed(_rate);
  }

  void _seekBy(int sec) {
    final c = _controller;
    if (c == null) return;
    c.seekTo(c.value.position + Duration(seconds: sec));
  }

  void _showDanmakuList() {
    if (_danmaku.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前视频暂无弹幕')));
      return;
    }
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: ListView(
      children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('弹幕列表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ..._danmaku.map((d) => ListTile(
          dense: true,
          leading: Text('${d.time.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          title: Text(d.text, style: const TextStyle(fontSize: 13)),
        )),
      ],
    )));
  }

  void _showChapterList() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (c) => DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.9, expand: false,
      builder: (c, ctrl) => Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('选集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        Expanded(child: ListView.builder(controller: ctrl, itemCount: _chapters.length, itemBuilder: (c, i) => ListTile(
          dense: true,
          selected: i == _index,
          title: Text(_chapters[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: i == _index ? const Icon(Icons.play_arrow, size: 18) : null,
          onTap: () { Navigator.pop(c); _playAt(i); },
        ))),
      ]),
    ));
  }

  /// 当前播放位置的弹幕
  List<_DanmakuItem> _danmakuAt(Duration pos) {
    final sec = pos.inMilliseconds / 1000.0;
    return _danmaku.where((d) => (d.time - sec).abs() < 3.0).toList();
  }

  @override
  Widget build(BuildContext context) {
    final current = _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
    final c = _controller;
    final pos = c?.value.position ?? Duration.zero;
    final dur = c?.value.duration ?? Duration.zero;
    final activeDanmaku = c != null && c.value.isInitialized ? _danmakuAt(pos) : const <_DanmakuItem>[];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showMenu = !_showMenu),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (c != null && c.value.isInitialized)
              Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
            else
              const Center(child: Text('无法播放该视频', style: TextStyle(color: Colors.white))),
            // 弹幕层（当前时刻的弹幕，从右向左滚动）
            if (c != null && c.value.isInitialized)
              Positioned.fill(child: IgnorePointer(child: ClipRect(child: Stack(children: [
                for (final d in activeDanmaku)
                  _DanmakuText(text: d.text),
              ])))),
            if (_showMenu)
              Positioned.fill(child: Container(color: Colors.black54, child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(color: Colors.black87, child: SafeArea(top: false, child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.arrow_back, color: Colors.white),
                      title: Text(current?.title ?? '', style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.subtitles_outlined, color: Colors.white), onPressed: _showDanmakuList),
                        IconButton(icon: const Icon(Icons.playlist_play, color: Colors.white), onPressed: _showChapterList),
                      ]),
                    ),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
                      Text(_fmt(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(child: Slider(
                        value: dur.inMilliseconds > 0 ? pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble() : 0,
                        max: dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1,
                        onChanged: (v) => c?.seekTo(Duration(milliseconds: v.toInt())),
                      )),
                      Text(_fmt(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ])),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      IconButton(onPressed: _cycleRate, icon: Text('${_rate}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      IconButton(onPressed: () => _seekBy(-15), iconSize: 32, icon: const Icon(Icons.replay_10, color: Colors.white)),
                      IconButton(onPressed: () => _playAt(_index - 1), iconSize: 34, icon: const Icon(Icons.skip_previous, color: Colors.white)),
                      FloatingActionButton.large(backgroundColor: Colors.white, onPressed: _togglePlay, child: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 36)),
                      IconButton(onPressed: () => _playAt(_index + 1), iconSize: 34, icon: const Icon(Icons.skip_next, color: Colors.white)),
                      IconButton(onPressed: () => _seekBy(15), iconSize: 32, icon: const Icon(Icons.forward_10, color: Colors.white)),
                      IconButton(onPressed: _showChapterList, icon: const Icon(Icons.queue_music, color: Colors.white)),
                    ]),
                    const SizedBox(height: 8),
                  ]))),
                ],
              ))),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }
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
  const _DanmakuText({required this.text});

  @override
  State<_DanmakuText> createState() => _DanmakuTextState();
}

class _DanmakuTextState extends State<_DanmakuText> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 6))..forward();
    _ac.addStatusListener((s) { if (s == AnimationStatus.completed && mounted) setState(() {}); });
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
          top: (widget.text.hashCode % 300).abs().toDouble(),
          left: MediaQuery.of(context).size.width * (1 - t),
          child: Text(widget.text, style: const TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
        );
      },
    );
  }
}

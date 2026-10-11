import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';

/// 有声书播放器，对齐原版 AudioPlayScreen
class AudioPlayerScreen extends StatefulWidget {
  final Book book;
  final int initialIndex;
  const AudioPlayerScreen({super.key, required this.book, this.initialIndex = 0});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  final DatabaseService _db = DatabaseService();
  List<BookChapter> _chapters = [];
  int _index = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _rate = 1.0;
  Timer? _sleepTimer;
  int _sleepLeft = 0;
  final List<double> _rates = [0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  StreamSubscription? _posSub, _durSub, _stateSub, _completeSub;

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _bind();
    _load();
  }

  void _bind() {
    _posSub = _player.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _durSub = _player.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) => _next());
  }

  Future<void> _load() async {
    final list = await _db.getChapters(widget.book.name, widget.book.author);
    if (!mounted) return;
    setState(() => _chapters = list.where((c) => !c.isVolume).toList());
    _playAt(_index);
  }

  Future<void> _playAt(int idx) async {
    if (idx < 0 || idx >= _chapters.length) return;
    setState(() => _index = idx);
    final ch = _chapters[idx];
    try {
      if (ch.url.startsWith('http')) {
        await _player.play(UrlSource(ch.url));
      } else if (ch.content != null && ch.content!.startsWith('http')) {
        await _player.play(UrlSource(ch.content!));
      }
      await _player.setPlaybackRate(_rate);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
    }
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  void _prev() => _playAt(_index - 1);
  void _next() => _playAt(_index + 1);

  Future<void> _seekBy(int sec) async {
    await _player.seek(_position + Duration(seconds: sec));
  }

  void _cycleRate() {
    final i = (_rates.indexOf(_rate) + 1) % _rates.length;
    setState(() => _rate = _rates[i]);
    _player.setPlaybackRate(_rate);
  }

  void _startSleep(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepLeft = minutes);
    if (minutes == 0) return;
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (t) {
      setState(() => _sleepLeft--);
      if (_sleepLeft <= 0) { _player.pause(); t.cancel(); }
    });
  }

  void _showSleepDialog() {
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('定时停止', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      ...[0, 15, 30, 60, 90].map((m) => ListTile(
        title: Text(m == 0 ? '关闭定时' : '$m 分钟后停止'),
        trailing: _sleepLeft == m && m > 0 ? const Icon(Icons.check, color: Colors.green) : null,
        onTap: () { _startSleep(m); Navigator.pop(c); },
      )),
    ])));
  }

  void _showChapterList() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (c) => DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.9, expand: false,
      builder: (c, ctrl) => Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('章节列表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        Expanded(child: ListView.builder(controller: ctrl, itemCount: _chapters.length, itemBuilder: (c, i) => ListTile(
          dense: true,
          selected: i == _index,
          title: Text(_chapters[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: i == _index ? const Icon(Icons.volume_up, size: 18) : null,
          onTap: () { Navigator.pop(c); _playAt(i); },
        ))),
      ]),
    ));
  }

  @override
  void dispose() {
    _posSub?.cancel(); _durSub?.cancel(); _stateSub?.cancel(); _completeSub?.cancel();
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: [
          IconButton(icon: const Icon(Icons.playlist_play), tooltip: '章节列表', onPressed: _showChapterList),
          IconButton(icon: const Icon(Icons.timer_outlined), tooltip: '定时', onPressed: _showSleepDialog),
        ],
      ),
      body: SafeArea(child: Column(children: [
        const SizedBox(height: 24),
        Center(child: Container(
          width: 200, height: 200,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [theme.colorScheme.primaryContainer, theme.colorScheme.secondaryContainer])),
          child: const Icon(Icons.graphic_eq, size: 72),
        )),
        const SizedBox(height: 24),
        Text(widget.book.name, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(current?.title ?? '加载中...', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey), textAlign: TextAlign.center),
        if (_sleepLeft > 0) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('$_sleepLeft 分钟后停止', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12))),
        const Spacer(),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(
              min: 0, max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
              value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
            )),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(_fmt(_position), style: const TextStyle(fontSize: 12)), Text(_fmt(_duration), style: const TextStyle(fontSize: 12))])),
        ])),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton(onPressed: _cycleRate, icon: Text('${_rate}x', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary))),
          IconButton(onPressed: () => _seekBy(-15), iconSize: 32, icon: const Icon(Icons.replay_10)),
          IconButton(onPressed: _prev, iconSize: 36, icon: const Icon(Icons.skip_previous)),
          FloatingActionButton.large(onPressed: _toggle, child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 40)),
          IconButton(onPressed: _next, iconSize: 36, icon: const Icon(Icons.skip_next)),
          IconButton(onPressed: () => _seekBy(15), iconSize: 32, icon: const Icon(Icons.forward_10)),
          IconButton(onPressed: _showChapterList, icon: const Icon(Icons.queue_music)),
        ]),
        const SizedBox(height: 24),
      ])),
    );
  }
}

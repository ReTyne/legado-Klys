import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/audio/audio_playback_controller.dart';
import 'package:legado_md3/help/readaloud/lrc_parser.dart';

/// 有声书播放器界面，对齐原版 AudioPlayActivity。
///
/// 播放逻辑全部在 [AudioPlaybackController]（对应原版 AudioPlayService）中：
/// 本页只负责展示与交互。退出页面时若选择「继续后台播放」，控制器保留会话，
/// 并由 Android 前台服务 + 媒体通知栏继续控制（见 `audio_notify_service.dart`）。
class AudioPlayerScreen extends StatefulWidget {
  final Book book;
  final int initialIndex;
  const AudioPlayerScreen({super.key, required this.book, this.initialIndex = 0});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  static const List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
  static const List<int> _sleepPresets = [15, 30, 60, 90];
  static const String _prefBackground = 'audio_background_play';

  final DatabaseService _db = DatabaseService();
  final AudioPlaybackController _audio = AudioPlaybackController.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<StreamSubscription> _subs = [];

  /// 是否在恢复一个后台续播会话（只同步 UI，不重新解析）
  late final bool _restoring;

  // ---- 以下为控制器状态的 UI 镜像 ----
  List<BookChapter> _chapters = [];
  int _index = 0;
  bool _isPlaying = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _rate = 1.0;
  AudioPlayMode _mode = AudioPlayMode.sequence;
  List<String> _segments = [];
  int _segIndex = 0;
  int _skipStart = 0;
  int _skipEnd = 0;

  /// 拖动进度条期间为 true，避免 position 事件回写造成抖动
  bool _seeking = false;
  double _seekValue = 0;

  /// 退出页面时是否继续后台播放（保留前台服务 + 通知栏控制）
  bool _backgroundPlay = false;
  /// 迷你悬浮播放窗（页内 PiP 式降级入口）
  bool _miniMode = false;
  Offset? _miniOffset;

  // 歌词
  List<LrcLine> _lyrics = [];
  int _lyricIndex = -1;

  // 定时关闭
  Timer? _sleepTimer;
  DateTime? _sleepEnd;

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  bool get _stopAfterCurrent => _audio.stopAfterCurrent;

  @override
  void initState() {
    super.initState();
    _restoring = _audio.hasSessionFor(widget.book);
    _bindStreams();
    _load();
  }

  void _bindStreams() {
    _subs.add(_audio.positions.listen((p) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!_seeking) {
          _position = p;
          if (_lyrics.isNotEmpty) _lyricIndex = LrcParser.indexAt(_lyrics, p);
        }
      });
    }));
    _subs.add(_audio.durations.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    }));
    _subs.add(_audio.playingStates.listen((p) {
      if (!mounted) return;
      setState(() => _isPlaying = p);
    }));
    _subs.add(_audio.loadingStates.listen((l) {
      if (!mounted) return;
      setState(() => _loading = l);
    }));
    _subs.add(_audio.trackChanges.listen((_) {
      if (!mounted) return;
      setState(() {
        _index = _audio.index;
        _segments = _audio.segments;
        _segIndex = _audio.segIndex;
        _syncLyricOfCurrent();
      });
    }));
    _subs.add(_audio.messages.listen((m) {
      if (!mounted) return;
      _toast(m);
      // 同步被引擎重置的标志（如「播完当前集停止」）
      setState(() {});
    }));
  }

  Future<void> _load() async {
    await _loadPrefs();
    final list = await _db.getChapters(widget.book.name, widget.book.author);
    if (!mounted) return;
    final chapters = list.where((c) => !c.isVolume).toList();
    await _audio.attach(
        book: widget.book, chapters: chapters, initialIndex: widget.initialIndex);
    if (!mounted) return;
    _syncFromController();
    if (_restoring) {
      // 复用后台续播中的会话：只同步 UI，不重新解析、不重头播放
      return;
    }
    final saved = await _audio.loadPosition(_audio.index);
    if (!mounted) return;
    await _audio.playAt(_audio.index,
        segment: saved?.segment ?? 0, startAt: saved?.position);
  }

  void _syncFromController() {
    _chapters = _audio.chapters;
    _index = _audio.index;
    _segments = _audio.segments;
    _segIndex = _audio.segIndex;
    _isPlaying = _audio.isPlaying;
    _loading = _audio.loading;
    _position = _audio.position;
    _duration = _audio.duration;
    _rate = _audio.rate;
    _mode = _audio.mode;
    _skipStart = _audio.skipStart;
    _skipEnd = _audio.skipEnd;
    _syncLyricOfCurrent();
  }

  void _syncLyricOfCurrent() {
    final content =
        _index >= 0 && _index < _chapters.length ? _chapters[_index].content : null;
    if (LrcParser.looksLikeLrc(content)) {
      _lyrics = LrcParser.parse(content!);
      _lyricIndex = LrcParser.indexAt(_lyrics, _position);
    } else {
      _lyrics = const [];
      _lyricIndex = -1;
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      _backgroundPlay = p.getBool(_prefBackground) ?? false;
    } catch (_) {}
  }

  Future<void> _persistBool(String key, bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  // ==================== 播放控制（转发控制器） ====================

  Future<void> _playAt(int idx) => _audio.playAt(idx);

  Future<void> _toggle() => _audio.toggle();

  Future<void> _next() => _audio.next();

  Future<void> _prev() => _audio.prev();

  Future<void> _seekTo(Duration d) => _audio.seekTo(d);

  Future<void> _seekBy(int sec) => _audio.seekBy(sec);

  Future<void> _setRate(double rate) => _audio.setRate(rate);

  void _cycleMode() {
    final mode = _audio.mode.next;
    setState(() => _mode = mode);
    unawaited(_audio.setMode(mode));
    _toast(mode.label);
  }

  // ==================== 倍速 / 播放模式 / 定时 ====================

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

  void _startSleep(int minutes) {
    _cancelSleep();
    if (minutes <= 0) {
      if (mounted) setState(() {});
      return;
    }
    final end = DateTime.now().add(Duration(minutes: minutes));
    _sleepEnd = end;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (DateTime.now().isAfter(end)) {
        _sleepEnd = null;
        t.cancel();
        unawaited(_audio.pause());
        if (mounted) setState(() {});
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  void _cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEnd = null;
  }

  void _setStopAfterCurrent(bool v) {
    _cancelSleep();
    _audio.setStopAfterCurrent(v);
    setState(() {});
  }

  void _showSleepDialog() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('定时关闭',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined),
            title: const Text('播完当前集停止'),
            trailing: _stopAfterCurrent ? const Icon(Icons.check) : null,
            onTap: () {
              Navigator.pop(c);
              _setStopAfterCurrent(!_stopAfterCurrent);
            },
          ),
          for (final m in _sleepPresets)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('$m 分钟后停止'),
              onTap: () {
                Navigator.pop(c);
                _startSleep(m);
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('自定义分钟'),
            onTap: () {
              Navigator.pop(c);
              unawaited(_showCustomSleepDialog());
            },
          ),
          if (_sleepEnd != null || _stopAfterCurrent)
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: const Text('取消定时'),
              onTap: () {
                Navigator.pop(c);
                setState(() {
                  _cancelSleep();
                  _audio.setStopAfterCurrent(false);
                });
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _showCustomSleepDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('自定义定时'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '分钟', hintText: '1 - 600'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(controller.text.trim())),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null || value <= 0) return;
    _startSleep(value.clamp(1, 600));
  }

  /// 剩余定时时间（无定时返回 null）
  Duration? get _sleepRemaining {
    final end = _sleepEnd;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  // ==================== 片头片尾 / 歌词 / 章节 ====================

  /// 跳过片头片尾配置（对齐 legado-E 的 AudioSkipCredits）。
  void _showSkipConfig() {
    showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setLocal) {
        var start = _skipStart.toDouble();
        var end = _skipEnd.toDouble();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('跳过片头片尾',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(width: 70, child: Text('跳过片头')),
                Expanded(
                  child: Slider(
                    value: start,
                    min: 0,
                    max: 120,
                    divisions: 24,
                    label: '${start.toInt()}s',
                    onChanged: (v) => setLocal(() => start = v),
                  ),
                ),
                SizedBox(
                    width: 40,
                    child: Text('${start.toInt()}s', textAlign: TextAlign.right)),
              ]),
              Row(children: [
                const SizedBox(width: 70, child: Text('跳过片尾')),
                Expanded(
                  child: Slider(
                    value: end,
                    min: 0,
                    max: 120,
                    divisions: 24,
                    label: '${end.toInt()}s',
                    onChanged: (v) => setLocal(() => end = v),
                  ),
                ),
                SizedBox(
                    width: 40,
                    child: Text('${end.toInt()}s', textAlign: TextAlign.right)),
              ]),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await _audio.setSkip(start: start.toInt(), end: end.toInt());
                  if (!mounted) return;
                  setState(() {
                    _skipStart = start.toInt();
                    _skipEnd = end.toInt();
                  });
                  Navigator.pop(context);
                  await _audio.playAt(_audio.index);
                },
                child: const Text('保存并应用'),
              ),
            ]),
          ),
        );
      }),
    );
  }

  /// 歌词列表弹层（高亮当前行，点击跳转）
  void _showLyricList() {
    if (_lyrics.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (c, ctrl) => Column(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('歌词',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              itemCount: _lyrics.length,
              itemBuilder: (c, i) => ListTile(
                dense: true,
                selected: i == _lyricIndex,
                title: Text(_lyrics[i].text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: i == _lyricIndex
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight: i == _lyricIndex ? FontWeight.w600 : null)),
                leading: Text(_fmt(_lyrics[i].time),
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: () {
                  unawaited(_seekTo(_lyrics[i].time));
                  Navigator.pop(c);
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _openChapterDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Widget _buildChapterDrawer() {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.queue_music),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('章节列表（${_chapters.length}）',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _chapters.length,
                itemBuilder: (c, i) => ListTile(
                  dense: true,
                  selected: i == _index,
                  title: Text(_chapters[i].title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: i == _index
                      ? Icon(Icons.volume_up, size: 18, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(c);
                    unawaited(_playAt(i));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ==================== 退出（后台继续播放 / 停止） ====================

  void _handlePop(bool didPop) {
    if (didPop) return;
    if (!_audio.isPlaying) {
      Navigator.of(context).pop();
      return;
    }
    unawaited(_confirmExit());
  }

  Future<void> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('正在播放'),
        content: Text(
            '退出播放页后是否继续后台播放？\n（当前默认：${_backgroundPlay ? '继续播放' : '停止播放'}）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('停止播放')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('继续后台播放')),
        ],
      ),
    );
    if (result == null || !mounted) return;
    _backgroundPlay = result;
    await _persistBool(_prefBackground, result);
    if (!result) await _audio.pause();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _sleepTimer?.cancel();
    // 后台播放：保留会话并交给 Android 前台服务 + 媒体通知栏
    unawaited(_audio.detach(
        backgroundPlay: _backgroundPlay && _audio.isPlaying));
    super.dispose();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final current = _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
    return PopScope(
      canPop: !_audio.isPlaying,
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: _buildChapterDrawer(),
        appBar: AppBar(
          title: const Text('正在播放'),
          actions: [
            IconButton(
                icon: const Icon(Icons.playlist_play),
                tooltip: '章节列表',
                onPressed: _openChapterDrawer),
            IconButton(
                icon: const Icon(Icons.timer_outlined),
                tooltip: '定时关闭',
                onPressed: _showSleepDialog),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'rate':
                    _showRateSheet();
                    break;
                  case 'skip':
                    _showSkipConfig();
                    break;
                  case 'mini':
                    setState(() => _miniMode = true);
                    break;
                  case 'background':
                    final nv = !_backgroundPlay;
                    setState(() => _backgroundPlay = nv);
                    await _persistBool(_prefBackground, nv);
                    break;
                }
              },
              itemBuilder: (c) => [
                const PopupMenuItem(value: 'rate', child: Text('播放倍速')),
                const PopupMenuItem(value: 'skip', child: Text('跳过片头片尾')),
                const PopupMenuItem(value: 'mini', child: Text('迷你悬浮窗')),
                CheckedPopupMenuItem(
                  value: 'background',
                  checked: _backgroundPlay,
                  child: const Text('退出时后台继续播放'),
                ),
              ],
            ),
          ],
        ),
        body: Stack(children: [
          if (_miniMode) _buildMiniPlaceholder() else _buildMainBody(current),
          if (_miniMode) _buildMiniWindow(),
        ]),
      ),
    );
  }

  Widget _buildMainBody(BookChapter? current) {
    final theme = Theme.of(context);
    final remaining = _sleepRemaining;
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final value = (_seeking ? _seekValue : _position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs);
    return SafeArea(
      child: Column(children: [
        const SizedBox(height: 16),
        _buildCover(theme),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(widget.book.name,
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(current?.title ?? '加载中...',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
        // 状态行：缓冲 / 多片段 / 进度记忆
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            if (_loading)
              const Chip(
                avatar: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                label: Text('缓冲中', style: TextStyle(fontSize: 12)),
              ),
            if (_segments.length > 1)
              Chip(
                label: Text('片段 ${_segIndex + 1}/${_segments.length}',
                    style: const TextStyle(fontSize: 12)),
              ),
            if (remaining != null)
              Chip(
                avatar: const Icon(Icons.timer, size: 14),
                label: Text('${_fmt(remaining)} 后停止',
                    style: const TextStyle(fontSize: 12)),
              ),
            if (_stopAfterCurrent)
              const Chip(
                avatar: Icon(Icons.stop_circle_outlined, size: 14),
                label: Text('本集播完停止', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (_lyrics.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: _showLyricList,
              child: Text(
                _lyricIndex >= 0 ? _lyrics[_lyricIndex].text : '（前奏）',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: theme.colorScheme.primary),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Text('点击查看歌词', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                  trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
              child: Slider(
                min: 0,
                max: maxMs,
                value: value,
                onChangeStart: (v) => setState(() {
                  _seeking = true;
                  _seekValue = v;
                }),
                onChanged: (v) => setState(() => _seekValue = v),
                onChangeEnd: (v) {
                  setState(() {
                    _seeking = false;
                    _position = Duration(milliseconds: v.toInt());
                  });
                  unawaited(_seekTo(Duration(milliseconds: v.toInt())));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(_position), style: const TextStyle(fontSize: 12)),
                    Text(_fmt(_duration), style: const TextStyle(fontSize: 12)),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: _mode.label,
              onPressed: _cycleMode,
              icon: Icon(_mode.icon),
            ),
            IconButton(
              onPressed: () => unawaited(_prev()),
              iconSize: 34,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              onPressed: () => unawaited(_seekBy(-15)),
              iconSize: 30,
              icon: const Icon(Icons.replay_10),
            ),
            // 主播放按钮：热区 72dp（> 56dp 要求）
            SizedBox(
              width: 72,
              height: 72,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const CircleBorder()),
                onPressed: () => unawaited(_toggle()),
                child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 36),
              ),
            ),
            IconButton(
              onPressed: () => unawaited(_seekBy(15)),
              iconSize: 30,
              icon: const Icon(Icons.forward_10),
            ),
            IconButton(
              onPressed: () => unawaited(_next()),
              iconSize: 34,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: '倍速 ${_rate}x',
              onPressed: _showRateSheet,
              icon: Text('${_rate}x',
                  style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildCover(ThemeData theme) {
    final url = widget.book.customCoverUrl ?? widget.book.coverUrl;
    if (url != null && url.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          placeholder: (c, u) => SizedBox(
            width: 200,
            height: 200,
            child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
          ),
          errorWidget: (c, u, e) => _buildCoverFallback(theme),
        ),
      );
    }
    return _buildCoverFallback(theme);
  }

  Widget _buildCoverFallback(ThemeData theme) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primaryContainer, theme.colorScheme.secondaryContainer],
        ),
      ),
      child: const Icon(Icons.graphic_eq, size: 72),
    );
  }

  /// 迷你模式下的占位背景（点击悬浮窗可返回完整播放页）
  Widget _buildMiniPlaceholder() {
    return const Center(
      child: Text('迷你播放中 · 点击悬浮窗返回', style: TextStyle(color: Colors.grey)),
    );
  }

  /// 悬浮迷你播放窗（本项目无 pip 插件，用当前页面内可拖拽小窗降级替代）。
  Widget _buildMiniWindow() {
    final size = MediaQuery.of(context).size;
    const w = 190.0;
    const h = 72.0;
    final base = _miniOffset ??
        Offset(size.width - w - 12, size.height - h - 120);
    final current = _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
    return Positioned(
      left: base.dx.clamp(0.0, size.width - w),
      top: base.dy.clamp(0.0, size.height - h),
      width: w,
      height: h,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _miniOffset = Offset(
            (base.dx + d.delta.dx).clamp(0.0, size.width - w).toDouble(),
            (base.dy + d.delta.dy).clamp(0.0, size.height - h).toDouble(),
          );
        }),
        onTap: () => setState(() => _miniMode = false),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(children: [
            const SizedBox(width: 8),
            Icon(Icons.album, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(current?.title ?? widget.book.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(_isPlaying ? '播放中 ${_fmt(_position)}' : '已暂停 ${_fmt(_position)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () => unawaited(_toggle()),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () async {
                await _audio.pause();
                if (mounted) setState(() => _miniMode = false);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

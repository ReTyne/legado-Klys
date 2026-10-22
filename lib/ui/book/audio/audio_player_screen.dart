import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/readaloud/lrc_parser.dart';

/// 播放模式（对齐 legado-E AudioPlay.PlayMode）
enum AudioPlayMode {
  /// 顺序播放，播完最后一集停止
  sequence,
  /// 单曲循环
  singleLoop,
  /// 随机播放
  random,
  /// 列表循环
  listLoop,
}

extension _AudioPlayModeExt on AudioPlayMode {
  String get label => const ['顺序播放', '单曲循环', '随机播放', '列表循环'][index];

  IconData get icon =>
      const [Icons.playlist_play, Icons.repeat_one, Icons.shuffle, Icons.repeat][index];

  AudioPlayMode get next =>
      AudioPlayMode.values[(index + 1) % AudioPlayMode.values.length];
}

/// 后台续播上下文：页面退出时若选择「继续后台播放」，播放器实例与当前轨道信息
/// 保留在这里，再次进入播放页复用，避免重复解析与重头播放。
///
/// 本项目未引入 audio_service / 前台服务，无法做通知栏控制与系统级后台播放，
/// 这里用「进程内保留播放器 + 退出确认开关 + 页内迷你悬浮窗」做降级替代。
class _AudioSession {
  final AudioPlayer player;
  int index;
  List<String> segments;
  int segment;

  _AudioSession(this.player)
      : index = 0,
        segment = 0,
        segments = <String>[];
}

/// 全局保留的后台播放会话（为空表示当前没有后台续播中的音频）。
_AudioSession? _retainedAudio;

_AudioSession _acquireAudio() {
  final retained = _retainedAudio;
  if (retained != null) return retained;
  final created = _AudioSession(AudioPlayer());
  _retainedAudio = created;
  return created;
}

/// 断点续听读取结果：片段下标 + 片段内位置。
class _ResumePoint {
  final int segment;
  final Duration position;
  const _ResumePoint(this.segment, this.position);
}

/// 有声书播放器，对齐原版 AudioPlayActivity + AudioPlayService。
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
  static const String _prefMode = 'audio_play_mode';
  static const String _prefRate = 'audio_play_rate';
  static const String _prefBackground = 'audio_background_play';
  static const String _prefSkipStart = 'audio_skip_start';
  static const String _prefSkipEnd = 'audio_skip_end';
  /// 音频扩展名（用于判断文本里是否直接是媒体地址）
  static final RegExp _audioExt =
      RegExp(r'\.(mp3|m4a|aac|wav|ogg|flac|opus|m3u8)(\?|#|$)', caseSensitive: false);
  static final RegExp _urlRe = RegExp(r'''https?://[^\s"'<>\\]+''');

  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final AudioPlayer _player;
  late final bool _restoring;

  List<BookChapter> _chapters = [];
  BookSource? _source;
  int _index = 0;
  bool _isPlaying = false;
  /// 解析/缓冲中
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _rate = 1.0;
  AudioPlayMode _mode = AudioPlayMode.sequence;

  /// 当前章节的音频片段队列（一段书源正文可能是多个 URL，需顺序播放）
  List<String> _segments = [];
  int _segIndex = 0;

  /// 拖动进度条期间为 true，避免 position 事件回写造成抖动
  bool _seeking = false;
  double _seekValue = 0;

  /// 退出页面时是否继续后台播放（无通知栏，降级为「保留播放器」）
  bool _backgroundPlay = false;
  /// 迷你悬浮播放窗（页内 PiP 式降级入口）
  bool _miniMode = false;
  Offset? _miniOffset;

  // 歌词
  List<LrcLine> _lyrics = [];
  int _lyricIndex = -1;

  // 跳过片头/片尾（秒），对齐 legado-E 的 AudioSkipCredits
  int _skipStart = 0;
  int _skipEnd = 0;
  bool _skipEndDone = false;

  // 定时关闭
  Timer? _sleepTimer;
  DateTime? _sleepEnd;
  bool _stopAfterCurrent = false;

  // 断点续听保存节流
  int _lastSaveMs = 0;
  StreamSubscription? _posSub, _durSub, _stateSub, _completeSub;

  /// 音频书章节正文可能直接就是媒体地址；也可能是需要书源规则解析的页面。
  /// 与 legado-E 一致：解析结果是 "http..." 单地址，或 JSON 数组（多个片段顺序播放）。
  static List<String> _parseUrls(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty || LrcParser.looksLikeLrc(text)) return const [];
    // 1) JSON 数组：legado-E 里 ExoPlayerHelper.getMediaSource 处理的形态
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
    // 2) 多行地址：每行一个片段
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.startsWith('http'))
        .toList();
    if (lines.isNotEmpty) return lines;
    // 3) 文本里内嵌的音频地址
    final m = _urlRe.firstMatch(text);
    if (m != null) {
      final u = m.group(0)!;
      if (_audioExt.hasMatch(u) || !text.contains('<')) return [u];
    }
    return const [];
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  String _positionKey(int idx) => 'audio_position_${widget.book.name}_$idx';

  @override
  void initState() {
    super.initState();
    _restoring = _retainedAudio != null;
    _player = _acquireAudio().player;
    _index = widget.initialIndex;
    _bind();
    _load();
  }

  void _bind() {
    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!_seeking) {
          _position = p;
          if (_lyrics.isNotEmpty) _lyricIndex = LrcParser.indexAt(_lyrics, p);
        }
      });
      unawaited(_savePosition());
      // 跳过片尾：接近结尾时自动切下一集
      if (_skipEnd > 0 &&
          _duration.inSeconds > _skipEnd &&
          !_skipEndDone &&
          p.inSeconds >= _duration.inSeconds - _skipEnd) {
        _skipEndDone = true;
        unawaited(_next());
      }
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = s == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (_segIndex + 1 < _segments.length) {
        unawaited(_playSegment(_segIndex + 1));
      } else {
        unawaited(_handleTrackComplete());
      }
    });
  }

  Future<void> _load() async {
    await _loadPrefs();
    final list = await _db.getChapters(widget.book.name, widget.book.author);
    if (!mounted) return;
    _chapters = list.where((c) => !c.isVolume).toList();
    if (_index < 0 || _index >= _chapters.length) _index = 0;
    setState(() {});

    if (_restoring) {
      // 复用后台续播中的播放器：只同步 UI，不重新解析、不重头播放
      final session = _retainedAudio;
      if (session != null) {
        _index = session.index;
        _segments = session.segments;
        _segIndex = session.segment;
      }
      final pos = await _player.getCurrentPosition();
      final dur = await _player.getDuration();
      if (!mounted) return;
      setState(() {
        _position = pos ?? Duration.zero;
        _duration = dur ?? Duration.zero;
        _isPlaying = _player.state == PlayerState.playing;
        _loading = false;
        _syncLyricOfCurrent();
      });
      return;
    }

    final saved = await _loadPosition(_index);
    await _playAt(_index, segment: saved?.segment ?? 0, startAt: saved?.position);
  }

  void _syncLyricOfCurrent() {
    final content = _index >= 0 && _index < _chapters.length ? _chapters[_index].content : null;
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
      final m = p.getInt(_prefMode) ?? 0;
      _mode = m >= 0 && m < AudioPlayMode.values.length
          ? AudioPlayMode.values[m]
          : AudioPlayMode.sequence;
      _rate = p.getDouble(_prefRate) ?? 1.0;
      _backgroundPlay = p.getBool(_prefBackground) ?? false;
      _skipStart = p.getInt(_prefSkipStart) ?? 0;
      _skipEnd = p.getInt(_prefSkipEnd) ?? 0;
    } catch (_) {}
  }

  Future<void> _persistDouble(String key, double v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(key, v);
    } catch (_) {}
  }

  Future<void> _persistInt(String key, int v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(key, v);
    } catch (_) {}
  }

  Future<void> _persistBool(String key, bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  // ==================== 断点续听 ====================

  Future<void> _savePosition({bool force = false}) async {
    if (_chapters.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastSaveMs < 3000) return;
    _lastSaveMs = now;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _positionKey(_index), '$_segIndex|${_position.inMilliseconds}');
    } catch (_) {}
  }

  Future<_ResumePoint?> _loadPosition(int idx) async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_positionKey(idx));
      if (v == null) return null;
      final parts = v.split('|');
      if (parts.length != 2) return null;
      final seg = int.tryParse(parts[0]) ?? 0;
      final ms = int.tryParse(parts[1]) ?? 0;
      if (seg <= 0 && ms <= 0) return null;
      return _ResumePoint(seg, Duration(milliseconds: ms));
    } catch (_) {
      return null;
    }
  }

  // ==================== 播放 ====================

  /// 解析当前章节的真实音频地址列表。
  Future<List<String>> _resolveSegments(int idx) async {
    final ch = _chapters[idx];
    final fromContent = _parseUrls(ch.content);
    if (fromContent.isNotEmpty) return fromContent;
    if (ch.url.startsWith('http') && _audioExt.hasMatch(ch.url)) return [ch.url];
    // 音频书源：走书源规则解析（等价 legado-E WebBook.getContent）
    try {
      _source ??= await _db.getSource(widget.book.origin ?? '');
      final source = _source;
      if (source != null) {
        final raw = await _engine.getAudioContent(source, ch.url,
            bookInfo: {'name': widget.book.name, 'author': widget.book.author},
            chapter: {'index': idx, 'title': ch.title, 'url': ch.url});
        final parsed = _parseUrls(raw);
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _playAt(int idx, {int segment = 0, Duration? startAt}) async {
    if (idx < 0 || idx >= _chapters.length) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // 切轨前保存上一轨进度
    await _savePosition(force: true);
    final ch = _chapters[idx];
    final hasLrc = LrcParser.looksLikeLrc(ch.content);
    setState(() {
      _index = idx;
      _loading = true;
      _position = startAt ?? Duration.zero;
      _duration = Duration.zero;
      _skipEndDone = false;
      _lyrics = hasLrc ? LrcParser.parse(ch.content!) : const [];
      _lyricIndex = hasLrc ? 0 : -1;
    });
    final urls = await _resolveSegments(idx);
    if (!mounted) return;
    if (urls.isEmpty) {
      setState(() => _loading = false);
      _toast('无法解析音频地址');
      return;
    }
    _segments = urls;
    _retainedAudio?.segments = urls;
    await _playSegment(segment.clamp(0, urls.length - 1), startAt: startAt);
  }

  Future<void> _playSegment(int seg, {Duration? startAt}) async {
    if (seg < 0 || seg >= _segments.length) return;
    final url = _segments[seg];
    var at = startAt ?? Duration.zero;
    if (seg == 0 && _skipStart > 0 && at < Duration(seconds: _skipStart)) {
      at = Duration(seconds: _skipStart);
    }
    setState(() {
      _segIndex = seg;
      _loading = true;
      _position = at;
    });
    _retainedAudio?.segment = seg;
    _retainedAudio?.index = _index;
    try {
      await _player.stop();
      await _player.setSource(UrlSource(url));
      await _player.resume();
      try {
        // 部分平台（尤其 Android 低版本）不支持变速，失败时保持原速
        await _player.setPlaybackRate(_rate);
      } catch (_) {}
      if (at > Duration.zero) await _player.seek(at);
      if (mounted) setState(() => _position = at);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _toast('播放失败: $e');
      }
    }
  }

  /// 一整集（所有片段）播放结束
  Future<void> _handleTrackComplete() async {
    await _savePosition(force: true);
    if (_stopAfterCurrent) {
      _stopAfterCurrent = false;
      _cancelSleep();
      await _player.pause();
      if (mounted) {
        setState(() {});
        _toast('已播完当前集，定时停止生效');
      }
      return;
    }
    await _next();
  }

  int _randomIndex() {
    if (_chapters.length <= 1) return 0;
    final n = math.Random().nextInt(_chapters.length);
    return n == _index ? (n + 1) % _chapters.length : n;
  }

  Future<void> _next() async {
    if (_chapters.isEmpty) return;
    switch (_mode) {
      case AudioPlayMode.sequence:
        if (_index + 1 < _chapters.length) {
          await _playAt(_index + 1);
        } else {
          await _player.pause();
          _toast('已是最后一集');
        }
        break;
      case AudioPlayMode.singleLoop:
        await _playAt(_index);
        break;
      case AudioPlayMode.random:
        await _playAt(_randomIndex());
        break;
      case AudioPlayMode.listLoop:
        await _playAt((_index + 1) % _chapters.length);
        break;
    }
  }

  Future<void> _prev() async {
    if (_chapters.isEmpty) return;
    if (_mode == AudioPlayMode.random) {
      await _playAt(_randomIndex());
      return;
    }
    // 播放超过 3 秒时，「上一曲」先回到本集开头
    if (_position.inSeconds > 3) {
      await _seekTo(Duration.zero);
      return;
    }
    if (_index > 0) await _playAt(_index - 1);
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
      await _savePosition(force: true);
    } else {
      if (_segments.isEmpty) {
        await _playAt(_index);
        return;
      }
      await _player.resume();
      try {
        await _player.setPlaybackRate(_rate);
      } catch (_) {}
    }
  }

  Future<void> _seekTo(Duration d) async {
    setState(() => _position = d);
    await _player.seek(d);
    await _savePosition(force: true);
  }

  Future<void> _seekBy(int sec) async {
    await _seekTo(Duration(
        milliseconds: (_position.inMilliseconds + sec * 1000).clamp(0, 1 << 31)));
  }

  // ==================== 倍速 / 播放模式 / 定时 ====================

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    await _persistDouble(_prefRate, rate);
    try {
      await _player.setPlaybackRate(rate);
    } catch (_) {
      if (mounted) _toast('当前设备不支持变速播放');
    }
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

  void _cycleMode() {
    final mode = _mode.next;
    setState(() => _mode = mode);
    unawaited(_persistInt(_prefMode, mode.index));
    _toast(mode.label);
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
        unawaited(_player.pause());
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
    setState(() => _stopAfterCurrent = v);
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
                  _stopAfterCurrent = false;
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
                  await _persistInt(_prefSkipStart, start.toInt());
                  await _persistInt(_prefSkipEnd, end.toInt());
                  if (!mounted) return;
                  setState(() {
                    _skipStart = start.toInt();
                    _skipEnd = end.toInt();
                    _skipEndDone = false;
                  });
                  Navigator.pop(context);
                  await _playAt(_index);
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
    if (!_isPlaying) {
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
    if (!result) await _player.pause();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(_savePosition(force: true));
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _sleepTimer?.cancel();
    if (_backgroundPlay && _isPlaying) {
      // 保留播放器继续后台播放（无 audio_service，无法做通知栏/前台服务）
      final session = _retainedAudio;
      if (session != null) {
        session.index = _index;
        session.segments = _segments;
        session.segment = _segIndex;
      }
    } else {
      _retainedAudio = null;
      unawaited(_player.dispose());
    }
    super.dispose();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final current = _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
    return PopScope(
      canPop: !_isPlaying,
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
                await _player.pause();
                if (mounted) setState(() => _miniMode = false);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

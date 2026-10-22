import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/audio/audio_notify_service.dart';
import 'package:legado_md3/help/readaloud/lrc_parser.dart';
import 'package:legado_md3/help/source/source_engine.dart';

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

extension AudioPlayModeExt on AudioPlayMode {
  String get label =>
      const ['顺序播放', '单曲循环', '随机播放', '列表循环'][index];

  IconData get icon => const [
        Icons.playlist_play,
        Icons.repeat_one,
        Icons.shuffle,
        Icons.repeat,
      ][index];

  AudioPlayMode get next =>
      AudioPlayMode.values[(index + 1) % AudioPlayMode.values.length];
}

/// 断点续听读取结果：片段下标 + 片段内位置。
class AudioResumePoint {
  final int segment;
  final Duration position;
  const AudioResumePoint(this.segment, this.position);
}

/// 有声书播放引擎（无 UI），对应原版 legado-E 的 AudioPlayService。
///
/// 职责：
///  - 持有 [AudioPlayer] 与章节队列，处理切集 / 多片段 / 播放模式 / 跳过片头片尾；
///  - 断点续听持久化；
///  - 播放页关闭后若用户选择后台播放，本控制器继续存活，并把播放状态同步到
///    Android 媒体通知（见 [AudioNotifyService]），通知栏的播放命令也由这里执行。
///
/// 因为 MainActivity 使用应用级共享 FlutterEngine（不随 Activity 销毁），
/// 页面关闭后 Dart 侧播放器仍然存活，后台播放与通知栏控制才真正有效。
/// 非 Android 平台没有通知服务，[AudioNotifyService] 的所有调用会静默失败。
class AudioPlaybackController {
  AudioPlaybackController._();

  static final AudioPlaybackController instance = AudioPlaybackController._();

  static const String _prefMode = 'audio_play_mode';
  static const String _prefRate = 'audio_play_rate';
  static const String _prefSkipStart = 'audio_skip_start';
  static const String _prefSkipEnd = 'audio_skip_end';

  /// 音频扩展名（用于判断文本里是否直接是媒体地址）
  static final RegExp _audioExt = RegExp(
      r'\.(mp3|m4a|aac|wav|ogg|flac|opus|m3u8)(\?|#|$)',
      caseSensitive: false);
  static final RegExp _urlRe = RegExp(r'''https?://[^\s"'<>\\]+''');

  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();

  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<bool> _loadingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<void> _trackCtrl = StreamController<void>.broadcast();
  final StreamController<String> _messageCtrl =
      StreamController<String>.broadcast();

  /// 播放进度
  Stream<Duration> get positions => _positionCtrl.stream;

  /// 总时长
  Stream<Duration> get durations => _durationCtrl.stream;

  /// 播放 / 暂停状态
  Stream<bool> get playingStates => _playingCtrl.stream;

  /// 解析 / 缓冲中
  Stream<bool> get loadingStates => _loadingCtrl.stream;

  /// 当前集 / 片段变化（UI 需重载歌词与进度）
  Stream<void> get trackChanges => _trackCtrl.stream;

  /// 需要提示用户的消息（解析失败 / 已是最后一集 / 不支持变速…）
  Stream<String> get messages => _messageCtrl.stream;

  AudioPlayer? _player;
  Book? _book;
  List<BookChapter> _chapters = const [];
  BookSource? _source;
  int _index = 0;
  List<String> _segments = const [];
  int _segIndex = 0;
  AudioPlayMode _mode = AudioPlayMode.sequence;
  double _rate = 1.0;
  int _skipStart = 0;
  int _skipEnd = 0;
  bool _skipEndDone = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _stopAfterCurrent = false;

  /// 是否保留后台会话（页面按用户选择退出后为 true）
  bool _background = false;

  StreamSubscription? _posSub, _durSub, _stateSub, _completeSub, _actionSub;
  int _lastSaveMs = 0;
  bool _notifyAsked = false;

  // ==================== 状态读取 ====================

  AudioPlayer? get player => _player;
  Book? get book => _book;
  List<BookChapter> get chapters => _chapters;
  int get index => _index;
  List<String> get segments => _segments;
  int get segIndex => _segIndex;
  AudioPlayMode get mode => _mode;
  double get rate => _rate;
  int get skipStart => _skipStart;
  int get skipEnd => _skipEnd;
  bool get loading => _loading;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get stopAfterCurrent => _stopAfterCurrent;
  bool get hasSession => _player != null;
  bool get background => _background;

  /// 是否存在同一本书的后台会话（用于播放页恢复）
  bool hasSessionFor(Book book) {
    final cur = _book;
    return _player != null &&
        cur != null &&
        cur.name == book.name &&
        cur.author == book.author;
  }

  String positionKey(int idx) => 'audio_position_${_book?.name}_$idx';

  // ==================== 会话生命周期 ====================

  /// 播放页进入：创建或恢复会话。
  ///
  /// 同一本书且已有会话时复用（后台续播），否则销毁旧会话并新建。
  Future<void> attach({
    required Book book,
    required List<BookChapter> chapters,
    int initialIndex = 0,
  }) async {
    _background = false;
    if (hasSessionFor(book)) {
      _chapters = chapters;
      return;
    }
    if (_player != null) await _teardown();
    _book = book;
    _chapters = chapters;
    _source = null;
    _index = chapters.isEmpty
        ? 0
        : initialIndex.clamp(0, chapters.length - 1);
    _segments = const [];
    _segIndex = 0;
    _position = Duration.zero;
    _duration = Duration.zero;
    _loading = false;
    _isPlaying = false;
    _stopAfterCurrent = false;
    _skipEndDone = false;
    final player = AudioPlayer();
    _player = player;
    _bindPlayer(player);
    _initActions();
    await _loadPrefs();
    try {
      // 音频焦点改由 AudioNotifyService 统一管理（失去焦点 / 拔耳机时暂停），
      // 这里关掉 audioplayers 自带的焦点请求，避免两份请求互相打架
      await player.setAudioContext(const AudioContext(
        android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ));
    } catch (_) {}
  }

  /// 播放页退出。
  ///
  /// [backgroundPlay] 为 true 且仍在播放时保留会话与前台服务（通知栏可继续控制），
  /// 否则停止播放并销毁会话。
  Future<void> detach({required bool backgroundPlay}) async {
    if (backgroundPlay && _isPlaying && _player != null) {
      _background = true;
      _syncNotify(start: true);
      return;
    }
    _background = false;
    await _teardown();
  }

  Future<void> _teardown() async {
    _posSub?.cancel();
    _posSub = null;
    _durSub?.cancel();
    _durSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _completeSub?.cancel();
    _completeSub = null;
    final player = _player;
    _player = null;
    _book = null;
    _chapters = const [];
    _segments = const [];
    _index = 0;
    _isPlaying = false;
    _loading = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    await AudioNotifyService.instance.stop();
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  void _bindPlayer(AudioPlayer player) {
    _posSub = player.onPositionChanged.listen((p) {
      _position = p;
      _loading = false;
      _loadingCtrl.add(false);
      _positionCtrl.add(p);
      unawaited(_savePosition());
      // 跳过片尾：接近结尾时自动切下一集
      if (_skipEnd > 0 &&
          _duration.inSeconds > _skipEnd &&
          !_skipEndDone &&
          p.inSeconds >= _duration.inSeconds - _skipEnd) {
        _skipEndDone = true;
        unawaited(next());
      }
    });
    _durSub = player.onDurationChanged.listen((d) {
      _duration = d;
      _durationCtrl.add(d);
    });
    _stateSub = player.onPlayerStateChanged.listen((s) {
      final playing = s == PlayerState.playing;
      if (playing == _isPlaying) return;
      _isPlaying = playing;
      _playingCtrl.add(playing);
      _syncNotify(start: playing);
      if (!playing) unawaited(_savePosition(force: true));
    });
    _completeSub = player.onPlayerComplete.listen((_) {
      if (_segIndex + 1 < _segments.length) {
        unawaited(playSegment(_segIndex + 1));
      } else {
        unawaited(_handleTrackComplete());
      }
    });
  }

  // ==================== 通知栏 ====================

  void _initActions() {
    if (_actionSub != null) return;
    AudioNotifyService.instance.init();
    _actionSub = AudioNotifyService.instance.actions.listen(_onAction);
    _requestNotifyPermission();
  }

  /// Android 13+ 需要运行时通知权限，否则媒体通知不显示（每进程只请求一次）。
  Future<void> _requestNotifyPermission() async {
    if (_notifyAsked) return;
    _notifyAsked = true;
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) await Permission.notification.request();
    } catch (_) {}
  }

  Future<void> _onAction(String action) async {
    switch (action) {
      case 'play':
        if (!_isPlaying) await toggle();
        break;
      case 'pause':
        if (_isPlaying) await toggle();
        break;
      case 'prev':
        await prev();
        break;
      case 'next':
        await next();
        break;
      case 'stop':
        await stopFromNotification();
        break;
    }
  }

  /// 通知栏「停止」：暂停播放并结束前台服务，保留断点。
  Future<void> stopFromNotification() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.pause();
    } catch (_) {}
    _background = false;
    await AudioNotifyService.instance.stop();
  }

  void _syncNotify({bool start = false}) {
    final book = _book;
    if (book == null) return;
    final title = book.name;
    final subtitle = _index >= 0 && _index < _chapters.length
        ? _chapters[_index].title
        : book.author;
    if (start) {
      unawaited(AudioNotifyService.instance.start(
          title: title, subtitle: subtitle, playing: _isPlaying));
    } else {
      unawaited(AudioNotifyService.instance.update(
          title: title, subtitle: subtitle, playing: _isPlaying));
    }
  }

  // ==================== 播放控制 ====================

  Future<void> playAt(int idx, {int segment = 0, Duration? startAt}) async {
    if (idx < 0 || idx >= _chapters.length) {
      _loading = false;
      _loadingCtrl.add(false);
      return;
    }
    // 切轨前保存上一轨进度
    await _savePosition(force: true);
    _index = idx;
    _loading = true;
    _loadingCtrl.add(true);
    _position = startAt ?? Duration.zero;
    _positionCtrl.add(_position);
    _duration = Duration.zero;
    _durationCtrl.add(_duration);
    _skipEndDone = false;
    _trackCtrl.add(null);

    final urls = await resolveSegments(idx);
    // 解析期间会话可能已被销毁（切到别的书 / 退出）
    if (_player == null) return;
    if (urls.isEmpty) {
      _loading = false;
      _loadingCtrl.add(false);
      _messageCtrl.add('无法解析音频地址');
      return;
    }
    _segments = urls;
    await playSegment(segment.clamp(0, urls.length - 1), startAt: startAt);
  }

  Future<void> playSegment(int seg, {Duration? startAt}) async {
    final player = _player;
    if (player == null || seg < 0 || seg >= _segments.length) return;
    final url = _segments[seg];
    var at = startAt ?? Duration.zero;
    if (seg == 0 && _skipStart > 0 && at < Duration(seconds: _skipStart)) {
      at = Duration(seconds: _skipStart);
    }
    _segIndex = seg;
    _loading = true;
    _loadingCtrl.add(true);
    _position = at;
    _positionCtrl.add(at);
    _trackCtrl.add(null);
    try {
      await player.stop();
      await player.setSource(UrlSource(url));
      await player.resume();
      try {
        // 部分平台（尤其 Android 低版本）不支持变速，失败时保持原速
        await player.setPlaybackRate(_rate);
      } catch (_) {}
      if (at > Duration.zero) await player.seek(at);
      _loading = false;
      _loadingCtrl.add(false);
      _syncNotify();
    } catch (e) {
      _loading = false;
      _loadingCtrl.add(false);
      _messageCtrl.add('播放失败: $e');
    }
  }

  /// 一整集（所有片段）播放结束
  Future<void> _handleTrackComplete() async {
    await _savePosition(force: true);
    if (_stopAfterCurrent) {
      _stopAfterCurrent = false;
      await pause();
      _messageCtrl.add('已播完当前集，定时停止生效');
      return;
    }
    await next();
  }

  int _randomIndex() {
    if (_chapters.length <= 1) return 0;
    final n = math.Random().nextInt(_chapters.length);
    return n == _index ? (n + 1) % _chapters.length : n;
  }

  Future<void> next() async {
    if (_chapters.isEmpty) return;
    switch (_mode) {
      case AudioPlayMode.sequence:
        if (_index + 1 < _chapters.length) {
          await playAt(_index + 1);
        } else {
          await pause();
          _messageCtrl.add('已是最后一集');
        }
        break;
      case AudioPlayMode.singleLoop:
        await playAt(_index);
        break;
      case AudioPlayMode.random:
        await playAt(_randomIndex());
        break;
      case AudioPlayMode.listLoop:
        await playAt((_index + 1) % _chapters.length);
        break;
    }
  }

  Future<void> prev() async {
    if (_chapters.isEmpty) return;
    if (_mode == AudioPlayMode.random) {
      await playAt(_randomIndex());
      return;
    }
    // 播放超过 3 秒时，「上一曲」先回到本集开头
    if (_position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    if (_index > 0) await playAt(_index - 1);
  }

  Future<void> toggle() async {
    final player = _player;
    if (player == null) return;
    if (_isPlaying) {
      await pause();
    } else {
      if (_segments.isEmpty) {
        await playAt(_index);
        return;
      }
      try {
        await player.resume();
        try {
          await player.setPlaybackRate(_rate);
        } catch (_) {}
      } catch (e) {
        _messageCtrl.add('播放失败: $e');
      }
    }
  }

  Future<void> pause() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.pause();
    } catch (_) {}
    await _savePosition(force: true);
  }

  Future<void> seekTo(Duration d) async {
    final player = _player;
    if (player == null) return;
    _position = d;
    _positionCtrl.add(d);
    try {
      await player.seek(d);
    } catch (_) {}
    await _savePosition(force: true);
  }

  Future<void> seekBy(int sec) async {
    await seekTo(Duration(
        milliseconds: (_position.inMilliseconds + sec * 1000)
            .clamp(0, 1 << 31)));
  }

  Future<void> setRate(double rate) async {
    _rate = rate;
    await _persistDouble(_prefRate, rate);
    final player = _player;
    if (player == null) return;
    try {
      await player.setPlaybackRate(rate);
    } catch (_) {
      _messageCtrl.add('当前设备不支持变速播放');
    }
  }

  Future<void> setMode(AudioPlayMode mode) async {
    _mode = mode;
    await _persistInt(_prefMode, mode.index);
  }

  Future<void> setSkip({required int start, required int end}) async {
    _skipStart = start;
    _skipEnd = end;
    _skipEndDone = false;
    await _persistInt(_prefSkipStart, start);
    await _persistInt(_prefSkipEnd, end);
  }

  void setStopAfterCurrent(bool v) {
    _stopAfterCurrent = v;
  }

  // ==================== 地址解析 ====================

  /// 音频书章节正文可能直接就是媒体地址；也可能是需要书源规则解析的页面。
  /// 与 legado-E 一致：解析结果是 "http..." 单地址，或 JSON 数组（多个片段顺序播放）。
  static List<String> parseUrls(String? raw) {
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

  /// 解析指定章节的真实音频地址列表。
  Future<List<String>> resolveSegments(int idx) async {
    if (idx < 0 || idx >= _chapters.length) return const [];
    final ch = _chapters[idx];
    final fromContent = parseUrls(ch.content);
    if (fromContent.isNotEmpty) return fromContent;
    if (ch.url.startsWith('http') && _audioExt.hasMatch(ch.url)) return [ch.url];
    // 音频书源：走书源规则解析（等价 legado-E WebBook.getContent）
    final book = _book;
    try {
      _source ??= await _db.getSource(book?.origin ?? '');
      final source = _source;
      if (source != null) {
        final raw = await _engine.getAudioContent(source, ch.url,
            bookInfo: {'name': book?.name, 'author': book?.author},
            chapter: {'index': idx, 'title': ch.title, 'url': ch.url});
        final parsed = parseUrls(raw);
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}
    return const [];
  }

  // ==================== 断点续听 ====================

  Future<void> _savePosition({bool force = false}) async {
    if (_chapters.isEmpty || _book == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastSaveMs < 3000) return;
    _lastSaveMs = now;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          positionKey(_index), '$_segIndex|${_position.inMilliseconds}');
    } catch (_) {}
  }

  Future<AudioResumePoint?> loadPosition(int idx) async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(positionKey(idx));
      if (v == null) return null;
      final parts = v.split('|');
      if (parts.length != 2) return null;
      final seg = int.tryParse(parts[0]) ?? 0;
      final ms = int.tryParse(parts[1]) ?? 0;
      if (seg <= 0 && ms <= 0) return null;
      return AudioResumePoint(seg, Duration(milliseconds: ms));
    } catch (_) {
      return null;
    }
  }

  // ==================== 偏好 ====================

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = p.getInt(_prefMode) ?? 0;
      _mode = m >= 0 && m < AudioPlayMode.values.length
          ? AudioPlayMode.values[m]
          : AudioPlayMode.sequence;
      _rate = p.getDouble(_prefRate) ?? 1.0;
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
}

import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/readaloud/cloud_tts_providers.dart';
import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'reading_record.dart';

/// TTS朗读服务
/// 支持系统TTS和云端HTTP TTS（含免费谷歌朗读）
class TtsService {
  /// 当前活动的朗读实例（由 init 注册、dispose 注销）。
  /// 媒体按键 / 系统快捷入口通过它控制正在朗读的会话，而非新建空实例。
  static TtsService? active;

  /// 忽略音频焦点（legado-E ignoreAudioFocus）：开启后朗读不因来电/切后台
  /// 等音频焦点变化而暂停。由设置页与启动期同步，是真实消费点。
  static bool ignoreAudioFocus = false;

  /// 退出应用时停止朗读（legado-E mediaButtonOnExit，默认 true）。
  static bool stopReadAloudOnExit = true;

  final FlutterTts _flutterTts = FlutterTts();
  final DatabaseService _db = DatabaseService();
  CloudTtsProvider? _cloudProvider;
  AudioPlayer? _cloudPlayer;
  bool _cloudMode = false;
  bool _cloudSpeaking = false;
  int _segIndex = 0;
  List<String> _segments = [];
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  double _speechRate = 0.5;
  double _speechPitch = 1.0;
  double _volume = 1.0;
  /// 最近一次实际下发到引擎的语速（null 表示尚未下发）
  double? _appliedRate;
  String? _currentText;
  String? _language;
  String? _engine;
  List<String> _chapters = [];
  List<BookChapter> _rawChapters = [];
  /// 按需加载某章正文（网络书未缓存时使用）
  Future<String?> Function(int index)? contentLoader;
  int _currentIndex = 0;
  // 单段朗读守卫：划词朗读时不自动续播下一章
  bool _onceGuard = false;

  // === 听书进度计入阅读记录（对齐 Sigma 阅读统计闭环） ===
  final ReadingRecordService _readingRecord = ReadingRecordService();
  /// 朗读所属书籍：由阅读页在 setChapters 后通过 [bindBook] 注入；
  /// 未注入（如 RSS 朗读）时回退到「最近阅读」的书。
  Book? _boundBook;
  DateTime? _playingSince;
  int _accumulatedMs = 0;

  Function(String)? onProgress;
  Function()? onComplete;
  Function(String)? onError;
  /// 新段落/章节开始朗读回调（索引, 文本），供界面高亮当前段
  Function(int index, String text)? onSegmentStart;

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  /// 是否正在朗读（系统/云端，不含暂停）
  bool get isSpeaking => _isPlaying && !_isPaused;
  /// 当前朗读文本
  String? get currentText =>
      (_currentIndex >= 0 && _currentIndex < _chapters.length)
          ? _chapters[_currentIndex]
          : _currentText;
  /// 当前朗读到的章节/段落索引
  int get currentIndex => _currentIndex;
  /// 章节/段落总数
  int get totalCount => _chapters.length;
  double get speechRate => _speechRate;
  double get speechPitch => _speechPitch;
  double get volume => _volume;

  /// SharedPreferences 中保存的朗读偏好 key（与设置页一致）
  static const String kPrefRateKey = 'tts_rate';
  static const String kPrefPitchKey = 'tts_pitch';

  /// HTML → 纯文本（RSS 正文可能带标签，朗读前需剥离；保留段落换行）
  static String stripHtml(String html) {
    if (html.isEmpty) return '';
    var text = html;
    text = text.replaceAll(
        RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true),
        '');
    text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    // 块级标签转换行，保留段落结构
    text = text.replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|ul|ol|blockquote|tr|section|article)>',
            caseSensitive: false),
        '\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = _decodeEntities(text);
    text = text.replaceAll(RegExp(r'[ \t\u3000]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&hellip;', '…')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAllMapped(
          RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));

  /// 按段落切分正文（\n 分段，过滤空白段）
  static List<String> splitParagraphs(String text) => text
      .split(RegExp(r'\r?\n+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 读取朗读偏好（语速 tts_rate / 音调 tts_pitch）并应用
  Future<void> loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rate = prefs.getDouble(kPrefRateKey);
      if (rate != null && rate > 0) await setSpeechRate(rate);
      final pitch = prefs.getDouble(kPrefPitchKey);
      if (pitch != null && pitch > 0) await setPitch(pitch);
    } catch (_) {}
  }

  /// 设置语速并持久化（tts_rate，范围 0.3~3.0，与设置页一致）
  Future<void> setRate(double rate) async {
    await setSpeechRate(rate);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kPrefRateKey, rate);
    } catch (_) {}
  }

  /// 确保缓存语速已下发引擎（初始化竞态 / 偏好后到等场景补下发）
  Future<void> _ensureRateApplied() async {
    if (_appliedRate == _speechRate) return;
    try {
      await _flutterTts.setSpeechRate(_speechRate);
      _appliedRate = _speechRate;
    } catch (_) {}
  }

  /// 初始化TTS
  Future<void> init() async {
    if (_isInitialized) return;
    active = this;
    try {
      await loadPrefs(); // 应用设置页保存的语速/音调
      await _flutterTts.setLanguage(_language ?? 'zh-CN');
      if (_engine != null) await _flutterTts.setEngine(_engine!);
      await _flutterTts.setSpeechRate(_speechRate);
      _appliedRate = _speechRate;
      await _flutterTts.setPitch(_speechPitch);
      await _flutterTts.setVolume(_volume);

      _flutterTts.setCompletionHandler(() {
        _isPlaying = false;
        if (_onceGuard) {
          _onceGuard = false; // 单段朗读结束，不自动续播
          _accumulate();
          unawaited(_flushListening());
          return;
        }
        // 自动播放下一章
        if (_currentIndex < _chapters.length - 1) {
          _currentIndex++;
          _speakCurrent();
        } else {
          // complete：整本读完，结算听书时长并同步进度
          _accumulate();
          unawaited(_flushListening());
          onComplete?.call();
        }
      });

      _flutterTts.setErrorHandler((msg) {
        _accumulate();
        unawaited(_flushListening());
        _isPlaying = false;
        onError?.call(msg.toString());
      });

      _flutterTts.setProgressHandler((text, start, end, word) {
        onProgress?.call(word);
      });

      _isInitialized = true;
    } catch (e) {
      onError?.call('TTS初始化失败: $e');
    }
  }

  /// 设置朗读内容
  void setChapters(List<BookChapter> chapters, {int startIndex = 0}) {
    _rawChapters = chapters;
    _chapters = chapters.map((c) => c.content ?? c.title).where((c) => c.isNotEmpty).toList();
    _currentIndex = startIndex.clamp(0, (_chapters.isEmpty ? 0 : _chapters.length - 1));
  }

  /// 设置纯文本段落列表（RSS 朗读用，复用章节索引机制，支持按段高亮/上下段）
  void setTextSegments(List<String> segments, {int startIndex = 0}) {
    _rawChapters = const [];
    _chapters = segments.where((s) => s.trim().isNotEmpty).toList();
    _currentIndex = startIndex.clamp(0, (_chapters.isEmpty ? 0 : _chapters.length - 1));
  }

  /// 开始朗读
  Future<void> play() async {
    if (!_cloudModeResolved) { await resolveCloudEngine(); _cloudModeResolved = true; }
    if (!_isInitialized && !_cloudMode) await init();
    if (_chapters.isEmpty) return;
    _isPaused = false;
    _markPlaying(); // play：开始累计听书时长
    await _speakCurrent();
  }
  bool _cloudModeResolved = false;

  /// 单段朗读（划词朗读）：朗读一段文本，结束后不自动续播下一章
  Future<void> speakOnce(String text) async {
    if (text.trim().isEmpty) return;
    if (!_isInitialized) await init();
    _onceGuard = true;
    _isPlaying = true;
    _isPaused = false;
    _markPlaying();
    _currentText = text;
    try {
      await _ensureRateApplied();
      await _flutterTts.stop(); // 停掉上一段，避免连续 speak 叠音
      await _flutterTts.speak(text);
    } catch (e) {
      _isPlaying = false;
      onError?.call('朗读失败: $e');
    }
  }

  /// 解析启用的云端 / 自定义 HTTP TTS 引擎；无则回退系统 TTS。
  ///
  /// 优先级：内置云厂商引擎（cloud_tts_engines）→ 用户自定义 HTTP TTS
  /// （http_tts 表，经 HttpTtsProvider 适配）→ 系统 TTS。此前 http_tts
  /// 表「能导入、能备份、能编辑，但既不展示也不参与朗读」，这里补上
  /// 最后一环，让 UI 配置的引擎真正进入朗读链路。
  Future<void> resolveCloudEngine() async {
    try {
      final engines = await _db.getCloudTtsEngines();
      for (final e in engines) {
        if (e.enabled == 1) {
          final p = CloudTtsProviderFactory.create(e);
          if (p != null) { _cloudProvider = p; _cloudMode = true; break; }
        }
      }
    } catch (_) {}
    if (!_cloudMode) {
      try {
        final httpEngines = await _db.getHttpTTS();
        for (final h in httpEngines) {
          if (h.enabled == 1 && h.url.trim().isNotEmpty) {
            _cloudProvider = HttpTtsProvider(h);
            _cloudMode = true;
            break;
          }
        }
      } catch (_) {}
    }
    if (_cloudMode) {
      _cloudPlayer ??= AudioPlayer();
      _cloudPlayer?.onPlayerComplete.listen((_) {
        if (_cloudSpeaking) _playNextSegment();
      });
    }
  }

  bool get isCloudMode => _cloudMode;

  Future<void> _speakCurrent() async {
    if (_currentIndex >= _chapters.length) return;
    _isPlaying = true;
    var text = _chapters[_currentIndex];
    // 网络书未缓存正文（当前仅为标题）时按需拉取
    if (contentLoader != null && _currentIndex < _rawChapters.length) {
      final raw = _rawChapters[_currentIndex];
      if ((raw.content == null || raw.content!.isEmpty) && text == raw.title) {
        try {
          final loaded = await contentLoader!(_currentIndex);
          if (loaded != null && loaded.isNotEmpty) { text = loaded; _chapters[_currentIndex] = loaded; }
        } catch (_) {}
      }
    }
    _currentText = text;
    onSegmentStart?.call(_currentIndex, text);
    if (_cloudMode && _cloudProvider != null) {
      await _cloudSpeak(text);
      return;
    }
    try {
      await _ensureRateApplied();
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      onError?.call('朗读失败: $e');
    }
  }

  /// 云端朗读：按句切分（<=180 字），逐段合成并顺序播放
  List<String> _splitSegments(String text) {
    final result = <String>[];
    final sentences = text.split(RegExp(r'(?<=[。！？!?\n；;])'));
    final buf = StringBuffer();
    for (final s in sentences) {
      if (s.isEmpty) continue;
      if (buf.length + s.length > 180) {
        if (buf.isNotEmpty) result.add(buf.toString());
        buf.clear();
        if (s.length > 180) {
          for (var i = 0; i < s.length; i += 180) {
            result.add(s.substring(i, (i + 180).clamp(0, s.length)));
          }
        } else {
          buf.write(s);
        }
      } else {
        buf.write(s);
      }
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result.isEmpty ? [text] : result;
  }

  Future<void> _cloudSpeak(String text) async {
    _segments = _splitSegments(text);
    _segIndex = 0;
    _cloudSpeaking = true;
    await _playNextSegment();
  }

  Future<void> _playNextSegment() async {
    if (!_cloudSpeaking) return;
    if (_segIndex >= _segments.length) {
      // 本章播完，下一章
      _isPlaying = false;
      if (_currentIndex < _chapters.length - 1) {
        _currentIndex++;
        _speakCurrent();
      } else {
        _accumulate();
        unawaited(_flushListening());
        onComplete?.call();
      }
      return;
    }
    final seg = _segments[_segIndex++];
    onProgress?.call(seg);
    try {
      final path = await _cloudProvider!.synthesize(seg);
      if (path == null) {
        // 本段失败，跳过继续
        _playNextSegment();
        return;
      }
      await _cloudPlayer?.stop();
      await _cloudPlayer?.play(DeviceFileSource(path));
    } catch (e) {
      _playNextSegment();
    }
  }

  /// 暂停
  Future<void> pause() async {
    _accumulate(); // pause：结算本段播放时长（暂停期间不计入阅读记录）
    if (_cloudMode) {
      await _cloudPlayer?.pause();
      _isPaused = true; _isPlaying = false;
      return;
    }
    if (!_isInitialized) return;
    try {
      await _flutterTts.pause();
      _isPaused = true;
      _isPlaying = false;
    } catch (_) {}
  }

  /// 恢复
  Future<void> resume() async {
    _markPlaying(); // resume：恢复计时（与 _accumulate 配对，暂停不计时）
    if (_cloudMode) {
      await _cloudPlayer?.resume();
      _isPaused = false; _isPlaying = true;
      return;
    }
    if (!_isInitialized) await init();
    // 系统 TTS：pause() 时插件已在内部按朗读进度截断保存文本，
    // 若先 stop() 会清空该进度导致从头朗读，故直接 speak 原文本从暂停处续读
    if (_isPaused && _chapters.isNotEmpty && _currentIndex < _chapters.length) {
      _isPaused = false;
      _isPlaying = true;
      try {
        await _ensureRateApplied();
        await _flutterTts.speak(_chapters[_currentIndex]);
      } catch (e) {
        _isPlaying = false;
        onError?.call('恢复朗读失败: $e');
      }
      return;
    }
    await play();
  }

  /// 停止
  Future<void> stop() async {
    _accumulate();
    unawaited(_flushListening()); // complete/stop：写 read_records + 同步进度
    _cloudSpeaking = false;
    if (_cloudMode) { await _cloudPlayer?.stop(); _isPlaying = false; _isPaused = false; return; }
    try {
      await _flutterTts.stop();
      _isPlaying = false;
      _isPaused = false;
    } catch (_) {}
  }

  /// 下一章
  Future<void> next() async {
    if (_currentIndex < _chapters.length - 1) {
      _currentIndex++;
      _isPaused = false;
      if (_cloudMode) _cloudSpeaking = false;
      await _speakCurrent();
    }
  }

  /// 上一章
  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      _isPaused = false;
      if (_cloudMode) _cloudSpeaking = false;
      await _speakCurrent();
    }
  }

  /// 设置语速
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    if (_isInitialized) {
      await _flutterTts.setSpeechRate(rate);
      _appliedRate = rate;
    }
  }

  /// 设置音调
  Future<void> setPitch(double pitch) async {
    _speechPitch = pitch;
    if (_isInitialized) await _flutterTts.setPitch(pitch);
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (_isInitialized) await _flutterTts.setVolume(volume);
  }

  /// 设置语言
  Future<void> setLanguage(String lang) async {
    _language = lang;
    if (_isInitialized) await _flutterTts.setLanguage(lang);
  }

  /// 设置系统 TTS 引擎
  Future<void> setEngine(String engine) async {
    _engine = engine;
    if (_isInitialized) await _flutterTts.setEngine(engine);
  }

  /// 当前语言/引擎（供界面回显）
  String? get language => _language;
  String? get engineName => _engine;

  /// 获取可用语言
  Future<List<String>> getLanguages() async {
    if (!_isInitialized) await init();
    try {
      final langs = await _flutterTts.getLanguages;
      if (langs is List) return langs.map((e) => e.toString()).toList();
      return ['zh-CN', 'en-US'];
    } catch (_) {
      return ['zh-CN', 'en-US'];
    }
  }

  /// 获取可用引擎
  Future<List<String>> getEngines() async {
    if (!_isInitialized) await init();
    try {
      final engines = await _flutterTts.getEngines;
      if (engines is List) return engines.map((e) => e.toString()).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  // === 听书进度计入阅读记录（play/pause/complete 挂钩） ===

  /// 绑定当前朗读书籍（供阅读页在 setChapters 后调用，把听书时长归入该书）。
  void bindBook(Book book) => _boundBook = book;

  /// 清除书籍绑定（RSS 朗读等无书籍上下文场景）。
  void clearBook() => _boundBook = null;

  /// 解析朗读归属书籍：优先显式绑定，否则取「最近阅读」的书
  /// （对齐 Sigma MediaButtonReceiver 的 appDb.bookDao.lastReadBook 语义）。
  Future<Book?> _resolveBook() async {
    final bound = _boundBook;
    if (bound != null) return bound;
    try {
      Book? best;
      for (final b in await _db.getAllBooks()) {
        if (best == null || b.durChapterTime > best.durChapterTime) best = b;
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// play / resume：开始（或恢复）累计听书时长。
  void _markPlaying() {
    _playingSince ??= DateTime.now();
  }

  /// pause / complete / stop：把「正在播放」这段时长累加进本次会话，
  /// 暂停期间不计时，避免阅读记录里混入静止时间。
  void _accumulate() {
    final since = _playingSince;
    if (since != null) {
      _accumulatedMs += DateTime.now().difference(since).inMilliseconds;
      _playingSince = null;
    }
  }

  /// 结算一次听书会话：朗读时长写进 `read_records`，并调
  /// [BookProgressSync.record] 记录进度（阅读统计 / 续读闭环）。
  /// 一次会话只落一条进度，避免 saveBookProgress 的 insert 无限膨胀。
  Future<void> _flushListening() async {
    final ms = _accumulatedMs;
    _accumulatedMs = 0;
    if (ms <= 0) return;
    try {
      final book = await _resolveBook();
      if (book == null) return;
      final seconds = ms ~/ 1000;
      if (seconds > 0) {
        await _readingRecord.recordListening(book.name, book.author, seconds);
      }
      await BookProgressSync.instance.record(
        book,
        chapterIndex: _currentIndex,
        durationMs: ms,
      );
    } catch (_) {}
  }

  /// 释放资源
  Future<void> dispose() async {
    await stop();
    _chapters.clear();
    _isInitialized = false;
    await _cloudPlayer?.dispose();
    _cloudPlayer = null;
    if (active == this) active = null;
  }
}

/// HTTP TTS 配置
class HttpTtsConfig {
  final String url;
  final String method;
  final Map<String, String> headers;
  final Map<String, String> params;
  final String textParam;
  final String contentType;

  HttpTtsConfig({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.params = const {},
    this.textParam = 'text',
    this.contentType = 'audio/mpeg',
  });
}

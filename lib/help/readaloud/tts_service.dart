import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:legado_md3/data/entities/cloud_tts_engine.dart';
import 'package:legado_md3/data/entities/http_tts.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/config/prefer_key_map.dart';
import 'package:legado_md3/help/readaloud/cloud_tts_providers.dart';
import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'chinese_converter.dart';
import 'reading_record.dart';
import 'tts_wake_lock.dart';

/// TTS朗读服务
/// 支持系统TTS和云端HTTP TTS（含免费谷歌朗读）
class TtsService {
  /// 当前活动的朗读实例（由 init 注册、dispose 注销）。
  /// 媒体按键 / 系统快捷入口通过它控制正在朗读的会话，而非新建空实例。
  static TtsService? active;

  /// 忽略音频焦点：开启后朗读不因来电/切后台
  /// 等音频焦点变化而暂停。由设置页与启动期同步，是真实消费点。
  static bool ignoreAudioFocus = false;

  /// 退出应用时停止朗读。
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
  /// `readAloudWakeLock` 偏好键的最近一次读取值（false 表示不申请唤醒锁）。
  bool _wakeLockEnabled = false;

 // === 听书进度计入阅读记录 ===
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
  /// 偏好键 `readAloudWakeLock` 是否开启（真实消费结果，供诊断/测试）。
  bool get wakeLockEnabled => _wakeLockEnabled;
  /// 当前是否按偏好键持有 PARTIAL_WAKE_LOCK（原生通道缺失时仅反映预期状态）。
  bool get wakeLockHeld => TtsWakeLock.instance.isHeld;

  /// SharedPreferences 中保存的朗读偏好 key（与设置页一致）
  static const String kPrefRateKey = 'tts_rate';
  static const String kPrefPitchKey = 'tts_pitch';
  static const String kPrefReadConfigKey = 'read_config_json';
  static const String kPrefTimerEndKey = 'tts_timer_end_ms';
  /// 朗读期间申请 PARTIAL_WAKE_LOCK（锁屏后继续朗读），与设置页键一致。
  static const String kPrefWakeLockKey = 'readAloudWakeLock';

  /// 朗读定时结束时刻（null 表示未设定），由服务持有，切 UI 不丢失。
  DateTime? _sleepEnd;
  Timer? _sleepTimer;

  /// 阅读页当前简繁模式（0 不转换 / 1 转简 / 2 转繁），朗读前套用同一设置，
  /// 保证「看到的正文」与「读出来的正文」简繁一致。
  int _converterMode = 0;

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

  /// 整段仅由空白 / 控制符 / 标点 / 分隔符 / 符号组成时不朗读。
  static final RegExp notReadAloudRe =
      RegExp(r'^(\s|\p{C}|\p{P}|\p{Z}|\p{S})+$', unicode: true);

  /// 朗读前清洗正文：去 HTML 标签 → 按段切分 → 丢弃纯标点段 → 简繁转换。
  /// 与阅读页展示使用同一 [ChineseConverter]，避免「看到简体、读出繁体」。
  static String cleanForReadAloud(String raw, {int converterMode = 0}) {
    var text = raw.trim();
    if (text.contains('<')) text = stripHtml(text);
    final paragraphs = splitParagraphs(text)
        .where((p) => !notReadAloudRe.hasMatch(p))
        .join('\n');
    return ChineseConverter.convert(paragraphs, converterMode);
  }

  /// 读取阅读页的简繁模式，朗读文本按同一模式转换。
  Future<void> loadReadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(kPrefReadConfigKey);
      if (json != null && json.isNotEmpty) {
        _converterMode = ReadConfig.fromJsonString(json).chineseConverter;
      }
    } catch (_) {}
  }

  String _prepareText(String raw) =>
      cleanForReadAloud(raw, converterMode: _converterMode);

  /// 读取朗读偏好（语速 tts_rate / 音调 tts_pitch / 唤醒锁 readAloudWakeLock）并应用
  Future<void> loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rate = prefs.getDouble(kPrefRateKey);
      if (rate != null && rate > 0) await setSpeechRate(rate);
      final pitch = prefs.getDouble(kPrefPitchKey);
      if (pitch != null && pitch > 0) await setPitch(pitch);
      _wakeLockEnabled = prefs.getBool(kPrefWakeLockKey) ?? false;
    } catch (_) {}
  }

  /// 按偏好键 `readAloudWakeLock` 与当前朗读状态同步 CPU 唤醒锁。
  ///
  /// 每次状态切换都重新读取偏好键（SharedPreferences 为内存缓存，开销可忽略），
  /// 以便设置页在朗读中途改动也能即时生效，避免留下「只写不读」的死键。
  /// 只在需要时才触碰原生通道；原生未注册时由 [TtsWakeLock] 安全降级。
  Future<void> _syncWakeLock() async {
    // 先同步快照朗读状态，避免 await 期间 _speakCurrent/stop 改变状态造成竞态。
    final active = isSpeaking;
    bool enabled = _wakeLockEnabled;
    try {
      enabled =
          (await SharedPreferences.getInstance()).getBool(kPrefWakeLockKey) ?? false;
    } catch (_) {
      // 读取失败时沿用上次值，不影响朗读。
    }
    _wakeLockEnabled = enabled;
    await TtsWakeLock.instance.setHeld(enabled: enabled, active: active);
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
      await loadReadConfig();
      await _restoreTimer();
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
          unawaited(_syncWakeLock()); // 单段结束：释放唤醒锁
          return;
        }
        // 自动播放下一章
        if (_currentIndex < _chapters.length - 1) {
          _currentIndex++;
          _speakCurrent(); // 续播由 _speakCurrent 重新同步唤醒锁，无需先释放
        } else {
          // complete：整本读完，结算听书时长并同步进度
          _accumulate();
          unawaited(_flushListening());
          unawaited(_syncWakeLock()); // 整本读完：释放唤醒锁
          onComplete?.call();
        }
      });

      _flutterTts.setErrorHandler((msg) {
        _accumulate();
        unawaited(_flushListening());
        _isPlaying = false;
        unawaited(_syncWakeLock()); // 朗读出错停止：释放唤醒锁
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
    await loadReadConfig();
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
    // 与连续朗读一致地解析用户所选引擎：HTTP/云引擎走云端合成，
    // 否则才用系统 TTS。此前划词朗读恒走系统 TTS，忽略引擎选择。
    if (!_cloudModeResolved) {
      await resolveCloudEngine();
      _cloudModeResolved = true;
    }
    if (!_isInitialized && !_cloudMode) await init();
    _onceGuard = true;
    _isPlaying = true;
    _isPaused = false;
    _markPlaying();
    unawaited(_syncWakeLock()); // 划词朗读开始：按偏好键申请唤醒锁
    final prepared = _prepareText(text);
    _currentText = prepared.isNotEmpty ? prepared : text;
    if (_cloudMode && _cloudProvider != null) {
      await _cloudSpeak(_currentText!);
      return;
    }
    try {
      await _ensureRateApplied();
      await _flutterTts.stop(); // 停掉上一段，避免连续 speak 叠音
      await _flutterTts.speak(_currentText!);
    } catch (e) {
      _isPlaying = false;
      onError?.call('朗读失败: $e');
    }
  }

  /// 按用户选中的引擎精确解析，未选时回退首个启用引擎。
  ///
  /// 选中值语义与偏好键 `appTtsEngine` 一致：纯数字按 id 先查 http_tts
  /// 再查 cloud_tts_engines；云厂商 type/name 直匹配；其余字符串视为
  /// 系统 TTS 引擎包名传给 [setEngine]。
  Future<void> resolveCloudEngine() async {
    _cloudProvider = null;
    _cloudMode = false;
    String? selected;
    try {
      selected = (await SharedPreferences.getInstance())
          .getString(UpstreamPrefKey.ttsEngine);
    } catch (_) {}
    if (selected != null && selected.trim().isEmpty) selected = null;

    List<CloudTtsEngine> engines = const [];
    try {
      engines = await _db.getCloudTtsEngines();
    } catch (_) {}
    List<HttpTTS> httpEngines = const [];
    try {
      httpEngines = await _db.getHttpTTS();
    } catch (_) {}

    CloudTtsEngine? cloud;
    HttpTTS? http;
    final numericId = selected == null ? null : int.tryParse(selected);
    if (numericId != null) {
      for (final h in httpEngines) {
        if (h.id == numericId) { http = h; break; }
      }
      if (http == null) {
        for (final e in engines) {
          if (e.id == numericId) { cloud = e; break; }
        }
      }
    } else if (selected != null) {
      for (final e in engines) {
        if (e.type == selected || e.name == selected) { cloud = e; break; }
      }
      if (cloud == null) _engine = selected; // 系统 TTS 引擎包名
    } else {
      for (final e in engines) {
        if (e.enabled == 1) { cloud = e; break; }
      }
      if (cloud == null) {
        for (final h in httpEngines) {
          if (h.enabled == 1 && h.url.trim().isNotEmpty) { http = h; break; }
        }
      }
    }

    if (cloud != null) {
      final p = CloudTtsProviderFactory.create(cloud);
      if (p != null) { _cloudProvider = p; _cloudMode = true; }
    } else if (http != null) {
      _cloudProvider = HttpTtsProvider(http);
      _cloudMode = true;
    }
    if (_cloudMode) {
      _cloudPlayer ??= AudioPlayer();
      _cloudPlayer?.onPlayerComplete.listen((_) {
        if (_cloudSpeaking) _playNextSegment();
      });
    }
  }

  /// 切换朗读引擎并持久化。下次 [play] 会按新选择重新解析。
  Future<void> selectEngine(String engineId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(UpstreamPrefKey.ttsEngine, engineId);
    } catch (_) {}
    _cloudModeResolved = false;
    _cloudMode = false;
    _cloudProvider = null;
  }

  /// 当前选中的引擎 id（未选择返回 null）。
  Future<String?> get selectedEngine async {
    try {
      return (await SharedPreferences.getInstance())
          .getString(UpstreamPrefKey.ttsEngine);
    } catch (_) {
      return null;
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
    final prepared = _prepareText(text);
    text = prepared.isNotEmpty ? prepared : text.trim();
    _currentText = text;
    onSegmentStart?.call(_currentIndex, text);
    unawaited(_syncWakeLock()); // 开读（含系统/云端、续播、切章）：按偏好键申请唤醒锁
    if (_cloudMode && _cloudProvider != null) {
      await _cloudSpeak(text);
      return;
    }
    if (notReadAloudRe.hasMatch(text)) return;
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
      // 本次云端合成的全部段落播完
      _isPlaying = false;
      if (_onceGuard) {
        // 划词朗读（单段）：结算后停止，不进入章节续播。
        _onceGuard = false;
        _cloudSpeaking = false;
        _accumulate();
        unawaited(_flushListening());
        unawaited(_syncWakeLock());
        return;
      }
      if (_currentIndex < _chapters.length - 1) {
        _currentIndex++;
        _speakCurrent();
      } else {
        _accumulate();
        unawaited(_flushListening());
        unawaited(_syncWakeLock()); // 云端全部播完：释放唤醒锁
        onComplete?.call();
      }
      return;
    }
    final seg = _segments[_segIndex++];
    onProgress?.call(seg);
    try {
      // 语速透传给云厂商（HTTP TTS 的 {{speakSpeed}} 占位符据此替换）
      final path = await _cloudProvider!.synthesize(
        seg,
        rate: _speechRate,
        pitch: _speechPitch,
      );
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
      unawaited(_syncWakeLock()); // 暂停：释放唤醒锁
      return;
    }
    if (!_isInitialized) return;
    try {
      await _flutterTts.pause();
      _isPaused = true;
      _isPlaying = false;
      unawaited(_syncWakeLock()); // 暂停：释放唤醒锁
    } catch (_) {}
  }

  /// 恢复
  Future<void> resume() async {
    _markPlaying(); // resume：恢复计时（与 _accumulate 配对，暂停不计时）
    if (_cloudMode) {
      await _cloudPlayer?.resume();
      _isPaused = false; _isPlaying = true;
      unawaited(_syncWakeLock()); // 云端恢复：按偏好键重新申请唤醒锁
      return;
    }
    if (!_isInitialized) await init();
    // 系统 TTS：pause() 时插件已在内部按朗读进度截断保存文本，
    // 若先 stop() 会清空该进度导致从头朗读，故直接 speak 原文本从暂停处续读
    if (_isPaused && _chapters.isNotEmpty && _currentIndex < _chapters.length) {
      _isPaused = false;
      _isPlaying = true;
      unawaited(_syncWakeLock()); // 系统 TTS 恢复：按偏好键重新申请唤醒锁
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
    if (_cloudMode) {
      await _cloudPlayer?.stop();
      _isPlaying = false; _isPaused = false;
      unawaited(_syncWakeLock()); // 停止：释放唤醒锁
      return;
    }
    try {
      await _flutterTts.stop();
      _isPlaying = false;
      _isPaused = false;
      unawaited(_syncWakeLock()); // 停止：释放唤醒锁
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

  /// 朗读剩余定时（null 表示未设定）
  Duration? get sleepRemaining {
    final end = _sleepEnd;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// 从偏好恢复定时：结束时刻落库，朗读服务重建 / 切页后仍按原时刻到点停止。
  Future<void> _restoreTimer() async {
    try {
      final endMs = (await SharedPreferences.getInstance()).getInt(kPrefTimerEndKey);
      if (endMs != null && endMs > DateTime.now().millisecondsSinceEpoch) {
        _armTimerUntil(DateTime.fromMillisecondsSinceEpoch(endMs));
      } else if (endMs != null) {
        await _clearTimerPref();
      }
    } catch (_) {}
  }

  void _armTimerUntil(DateTime end) {
    _sleepTimer?.cancel();
    _sleepEnd = end;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (DateTime.now().isBefore(end)) return;
      t.cancel();
      _sleepTimer = null;
      _sleepEnd = null;
      _clearTimerPref();
      unawaited(stop());
    });
  }

  Future<void> _clearTimerPref() async {
    try {
      await (await SharedPreferences.getInstance()).remove(kPrefTimerEndKey);
    } catch (_) {}
  }

  /// 设定 N 分钟后停止朗读（<=0 取消），结束时刻持久化供后台/重建续用。
  Future<void> setTimer(int minutes) async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEnd = null;
    if (minutes <= 0) {
      await _clearTimerPref();
      return;
    }
    final end = DateTime.now().add(Duration(minutes: minutes));
    _armTimerUntil(end);
    try {
      await (await SharedPreferences.getInstance())
          .setInt(kPrefTimerEndKey, end.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// 在现有定时上追加分钟（无定时则从当前时刻起算）。
  Future<void> addTimer([int minutes = 1]) {
    final remain = sleepRemaining;
    return setTimer(remain == null ? minutes : remain.inMinutes + minutes);
  }

  Future<void> cancelTimer() => setTimer(0);

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
 /// （appDb.bookDao.lastReadBook 语义）。
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
    _sleepTimer?.cancel();
    _sleepTimer = null;
    await stop();
    unawaited(_syncWakeLock()); // 兜底：释放唤醒锁
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

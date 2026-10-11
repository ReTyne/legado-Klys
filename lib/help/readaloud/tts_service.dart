import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/readaloud/cloud_tts_providers.dart';

/// TTS朗读服务
/// 支持系统TTS和云端HTTP TTS（含免费谷歌朗读）
class TtsService {
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
  String? _language;
  String? _engine;
  List<String> _chapters = [];
  List<BookChapter> _rawChapters = [];
  /// 按需加载某章正文（网络书未缓存时使用）
  Future<String?> Function(int index)? contentLoader;
  int _currentIndex = 0;
  Function(String)? onProgress;
  Function()? onComplete;
  Function(String)? onError;

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  double get speechRate => _speechRate;
  double get speechPitch => _speechPitch;
  double get volume => _volume;

  /// 初始化TTS
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage(_language ?? 'zh-CN');
      if (_engine != null) await _flutterTts.setEngine(_engine!);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_speechPitch);
      await _flutterTts.setVolume(_volume);

      _flutterTts.setCompletionHandler(() {
        _isPlaying = false;
        // 自动播放下一章
        if (_currentIndex < _chapters.length - 1) {
          _currentIndex++;
          _speakCurrent();
        } else {
          onComplete?.call();
        }
      });

      _flutterTts.setErrorHandler((msg) {
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

  /// 开始朗读
  Future<void> play() async {
    if (!_cloudModeResolved) { await resolveCloudEngine(); _cloudModeResolved = true; }
    if (!_isInitialized && !_cloudMode) await init();
    if (_chapters.isEmpty) return;
    _isPaused = false;
    await _speakCurrent();
  }
  bool _cloudModeResolved = false;

  /// 解析启用的云端 TTS 引擎；无则回退系统 TTS
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
    if (_cloudMode && _cloudProvider != null) {
      await _cloudSpeak(text);
      return;
    }
    try {
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
    if (_cloudMode) {
      await _cloudPlayer?.resume();
      _isPaused = false; _isPlaying = true;
      return;
    }
    play();
  }

  /// 停止
  Future<void> stop() async {
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
      if (_cloudMode) _cloudSpeaking = false;
      await _speakCurrent();
    }
  }

  /// 上一章
  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      if (_cloudMode) _cloudSpeaking = false;
      await _speakCurrent();
    }
  }

  /// 设置语速
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    if (_isInitialized) await _flutterTts.setSpeechRate(rate);
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

  /// 释放资源
  Future<void> dispose() async {
    await stop();
    _chapters.clear();
    _isInitialized = false;
    await _cloudPlayer?.dispose();
    _cloudPlayer = null;
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

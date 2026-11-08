import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/v14_models.dart';

/// BGM 在线背景音乐服务（对齐 fork 的 BGM 音乐库 / 朗读场景混音）。
///
/// * 歌单持久化：`DatabaseService().getBgmTracks()/insertBgmTrack()/deleteBgmTrack()`；
/// * 播放：`audioplayers`，本地文件走 [DeviceFileSource]，在线 URL 走 [UrlSource]；
/// * 与朗读混音：朗读开始时自动把 BGM 有效音量降到 [duckFactor] 倍（duck），
///   朗读结束自动还原。朗读状态既可由 UI 主动 [setReadAloudActive]，也可通过
///   [bindReadAloudProbe] 注入探测函数由本服务轮询，保证阅读页无需改动即可接线。
class BgmService extends ChangeNotifier {
  BgmService._();
  static final BgmService instance = BgmService._();

  final DatabaseService _db = DatabaseService();

  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  Timer? _duckTimer;

  List<BgmTrack> _tracks = const [];
  int _index = -1;
  bool _playing = false;
  bool _loaded = false;
  double _volume = 0.6;
  double _duckFactor = 0.3;
  bool _duckEnabled = true;
  bool _readAloudActive = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  /// 朗读状态探测（由阅读页 / 音频页注入，如 `() => tts.isSpeaking`）。
  bool Function()? readAloudProbe;

  List<BgmTrack> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  BgmTrack? get current =>
      _index >= 0 && _index < _tracks.length ? _tracks[_index] : null;
  bool get playing => _playing;
  double get volume => _volume;
  double get duckFactor => _duckFactor;
  bool get duckEnabled => _duckEnabled;
  bool get readAloudActive => _readAloudActive;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get error => _error;

  /// 实际下发给播放器的音量：朗读中且开启 duck 时按比例压低。
  double get effectiveVolume => (_duckEnabled && _readAloudActive)
      ? (_volume * _duckFactor).clamp(0.0, 1.0)
      : _volume.clamp(0.0, 1.0);

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _player = p;
    _completeSub = p.onPlayerComplete.listen((_) => unawaited(next()));
    _stateSub = p.onPlayerStateChanged.listen((s) {
      _playing = s == PlayerState.playing;
      notifyListeners();
    });
    _posSub = p.onPositionChanged.listen((d) {
      _position = d;
      notifyListeners();
    });
    _durSub = p.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    return p;
  }

  /// 从歌单表加载（幂等）。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await reload();
  }

  Future<void> reload() async {
    _tracks = await _db.getBgmTracks();
    if (_index >= _tracks.length) _index = _tracks.isEmpty ? -1 : 0;
    notifyListeners();
  }

  Source _sourceFor(BgmTrack t) {
    if (t.source == 'online' || t.url.startsWith('http')) {
      return UrlSource(t.url);
    }
    var path = t.url;
    if (path.startsWith('file://')) path = path.substring(7);
    return DeviceFileSource(path);
  }

  Future<void> playTrack(int i) async {
    if (_tracks.isEmpty) return;
    final idx = i % _tracks.length;
    _index = idx;
    _error = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    try {
      final p = _ensurePlayer();
      await p.stop();
      await p.setVolume(effectiveVolume);
      await p.play(_sourceFor(_tracks[idx]));
    } catch (e) {
      _error = '播放失败：$e';
      _playing = false;
      notifyListeners();
    }
  }

  Future<void> next() => playTrack(_index + 1);

  Future<void> prev() => playTrack(_index - 1);

  Future<void> toggle() async {
    if (_playing) {
      await pause();
    } else if (_index >= 0) {
      await resume();
    } else if (_tracks.isNotEmpty) {
      await playTrack(0);
    }
  }

  Future<void> pause() async {
    await _player?.pause();
    _playing = false;
    notifyListeners();
  }

  Future<void> resume() async {
    final p = _player;
    if (p == null || _index < 0) {
      if (_tracks.isNotEmpty) await playTrack(_index < 0 ? 0 : _index);
      return;
    }
    await p.setVolume(effectiveVolume);
    await p.resume();
    _playing = true;
    notifyListeners();
  }

  Future<void> stop() async {
    await _player?.stop();
    _playing = false;
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _player?.setVolume(effectiveVolume);
    notifyListeners();
  }

  Future<void> setDuckEnabled(bool v) async {
    _duckEnabled = v;
    await _player?.setVolume(effectiveVolume);
    notifyListeners();
  }

  Future<void> setDuckFactor(double v) async {
    _duckFactor = v.clamp(0.05, 1.0);
    await _player?.setVolume(effectiveVolume);
    notifyListeners();
  }

  /// 朗读状态变化入口：真实改变播放器音量（duck / 还原）。
  Future<void> setReadAloudActive(bool active) async {
    if (_readAloudActive == active) return;
    _readAloudActive = active;
    await _player?.setVolume(effectiveVolume);
    notifyListeners();
  }

  /// 注入朗读状态探测；本服务按 400ms 周期同步 duck，断开传 null。
  void bindReadAloudProbe(bool Function()? probe) {
    readAloudProbe = probe;
    _duckTimer?.cancel();
    _duckTimer = null;
    if (probe == null) return;
    _duckTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final v = probe();
      if (v != _readAloudActive) unawaited(setReadAloudActive(v));
    });
  }

  /// 添加在线 URL 曲目（[source] = 'online'）。
  Future<void> addOnlineTrack({
    required String title,
    required String url,
    String artist = '',
    String? coverUrl,
  }) async {
    await _db.insertBgmTrack(BgmTrack(
      title: title,
      artist: artist,
      url: url,
      coverUrl: coverUrl,
      source: 'online',
      customOrder: _tracks.length,
    ));
    await reload();
  }

  /// 添加本地文件曲目（[path] 为本地绝对路径或 file:// URI）。
  Future<void> addLocalTrack({
    required String title,
    required String path,
    String artist = '',
    String? coverUrl,
  }) async {
    await _db.insertBgmTrack(BgmTrack(
      title: title,
      artist: artist,
      url: path,
      coverUrl: coverUrl,
      source: 'local',
      customOrder: _tracks.length,
    ));
    await reload();
  }

  Future<void> removeTrack(BgmTrack track) async {
    final id = track.id;
    if (id == null) return;
    final wasCurrent = _tracks.indexOf(track) == _index;
    await _db.deleteBgmTrack(id);
    await reload();
    if (wasCurrent) await stop();
  }

  void disposeService() {
    _duckTimer?.cancel();
    _completeSub?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player?.dispose();
    _player = null;
  }
}

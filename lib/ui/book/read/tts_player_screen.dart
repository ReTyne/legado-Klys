import 'dart:async';
import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/help/readaloud/tts_service.dart';

class TtsPlayerScreen extends StatefulWidget {
  final TtsService ttsService;
  final List<BookChapter> chapters;
  final int currentIndex;
  final String bookName;

  const TtsPlayerScreen({
    super.key,
    required this.ttsService,
    required this.chapters,
    required this.currentIndex,
    required this.bookName,
  });

  @override
  State<TtsPlayerScreen> createState() => _TtsPlayerScreenState();
}

class _TtsPlayerScreenState extends State<TtsPlayerScreen> {
  late int _currentIndex;
  bool _isPlaying = false;
  double _speechRate = 0.5;
  double _pitch = 1.0;
  double _volume = 1.0;
  List<String> _languages = [];
  String? _selectedLanguage;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEnd;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _speechRate = widget.ttsService.speechRate;
    _pitch = widget.ttsService.speechPitch;
    _volume = widget.ttsService.volume;
    _loadLanguages();
    widget.ttsService.onComplete = () {
      if (mounted) setState(() => _isPlaying = false);
    };
  }

  Future<void> _loadLanguages() async {
    final langs = await widget.ttsService.getLanguages();
    if (mounted) {
      setState(() {
        _languages = langs;
        _selectedLanguage = langs.contains('zh-CN') ? 'zh-CN' : langs.isNotEmpty ? langs.first : null;
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await widget.ttsService.pause();
      setState(() => _isPlaying = false);
    } else {
      if (widget.ttsService.isCloudMode && widget.ttsService.isPaused) {
        await widget.ttsService.resume();
      } else {
        widget.ttsService.setChapters(widget.chapters, startIndex: _currentIndex);
        await widget.ttsService.play();
      }
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _nextChapter() async {
    if (_currentIndex < widget.chapters.length - 1) {
      setState(() => _currentIndex++);
      if (_isPlaying) {
        widget.ttsService.setChapters(widget.chapters, startIndex: _currentIndex);
        await widget.ttsService.play();
      }
    }
  }

  Future<void> _prevChapter() async {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      if (_isPlaying) {
        widget.ttsService.setChapters(widget.chapters, startIndex: _currentIndex);
        await widget.ttsService.play();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentChapter = _currentIndex < widget.chapters.length
        ? widget.chapters[_currentIndex]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 章节信息
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.headphones, size: 80, color: theme.colorScheme.primary),
                    const SizedBox(height: 24),
                    Text(
                      currentChapter?.title ?? '无章节',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '第 ${_currentIndex + 1} / ${widget.chapters.length} 章',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),

            // 播放控制
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 36,
                  onPressed: _prevChapter,
                ),
                const SizedBox(width: 24),
                FloatingActionButton.large(
                  onPressed: _togglePlay,
                  child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 40),
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  iconSize: 36,
                  onPressed: _nextChapter,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 定时停止
            TextButton.icon(
              onPressed: _showTimerDialog,
              icon: Icon(_sleepTimer != null ? Icons.timer_off : Icons.timer, size: 20),
              label: Text(_sleepTimerEnd != null
                  ? '定时中: ' + _formatRemaining()
                  : '定时停止'),
            ),

            const SizedBox(height: 32),

            // 语速调节
            _buildSlider(
              label: '语速',
              value: _speechRate,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: (v) {
                setState(() => _speechRate = v);
                widget.ttsService.setSpeechRate(v);
              },
            ),

            // 音调调节
            _buildSlider(
              label: '音调',
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              onChanged: (v) {
                setState(() => _pitch = v);
                widget.ttsService.setPitch(v);
              },
            ),

            // 音量调节
            _buildSlider(
              label: '音量',
              value: _volume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              onChanged: (v) {
                setState(() => _volume = v);
                widget.ttsService.setVolume(v);
              },
            ),

            // 语言选择
            if (_languages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Text('语言:', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedLanguage,
                        items: _languages.map((lang) => DropdownMenuItem(value: lang, child: Text(lang))).toList(),
                        onChanged: (v) {
                          setState(() => _selectedLanguage = v);
                          if (v != null) widget.ttsService.setLanguage(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(1),
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 50, child: Text(value.toStringAsFixed(1), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
  void _showTimerDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('定时停止', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: const Text('关闭定时'),
              onTap: () {
                _cancelTimer();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('15分钟后'),
              onTap: () {
                _setTimer(15);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('30分钟后'),
              onTap: () {
                _setTimer(30);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('60分钟后'),
              onTap: () {
                _setTimer(60);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('90分钟后'),
              onTap: () {
                _setTimer(90);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _setTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimerEnd = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (DateTime.now().isAfter(_sleepTimerEnd!)) {
        _cancelTimer();
        widget.ttsService.stop();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        if (mounted) setState(() {});
      }
    });
    setState(() {});
  }

  void _cancelTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEnd = null;
    if (mounted) setState(() {});
  }

  String _formatRemaining() {
    if (_sleepTimerEnd == null) return '';
    final remaining = _sleepTimerEnd!.difference(DateTime.now());
    final mins = remaining.inMinutes;
    final secs = remaining.inSeconds % 60;
    return mins.toString().padLeft(2, '0') + ':' + secs.toString().padLeft(2, '0');
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

}

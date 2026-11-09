import 'package:flutter/material.dart';

import 'package:legado_md3/help/config/video_play_config.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 视频播放器设置（对齐 legado-E `pref_config_other.xml` 的 videoSetting 独立入口）。
///
/// 四项均落到 [VideoPlayConfig] 的持久化键（autoPlay / startFull /
/// longPressSpeed / fullBottomProgressBar），由 `video_player_screen.dart`
/// 启动时 `VideoPlayConfig.load()` 真实读取，构成完整消费链。
class VideoSettingScreen extends StatefulWidget {
  const VideoSettingScreen({super.key});

  @override
  State<VideoSettingScreen> createState() => _VideoSettingScreenState();
}

class _VideoSettingScreenState extends State<VideoSettingScreen> {
  bool _autoPlay = VideoPlayConfig.autoPlay;
  bool _startFull = VideoPlayConfig.startFull;
  bool _fullBottomProgressBar = VideoPlayConfig.fullBottomProgressBar;
  int _longPressSpeedTenths = VideoPlayConfig.longPressSpeedTenths;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await VideoPlayConfig.load();
    if (!mounted) return;
    setState(() {
      _autoPlay = VideoPlayConfig.autoPlay;
      _startFull = VideoPlayConfig.startFull;
      _fullBottomProgressBar = VideoPlayConfig.fullBottomProgressBar;
      _longPressSpeedTenths = VideoPlayConfig.longPressSpeedTenths;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('视频播放器设置')),
      body: _loading
          ? const AppLoadingIndicator()
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                AppSettingsGroup(
                  title: '播放行为',
                  children: [
                    AppSwitchTile(
                      title: '自动播放',
                      subtitle: '打开视频后自动开始播放（autoPlay）',
                      value: _autoPlay,
                      onChanged: (v) async {
                        setState(() {
                          _autoPlay = v;
                          if (!v) _startFull = false;
                        });
                        await VideoPlayConfig.setAutoPlay(v);
                        if (!v) await VideoPlayConfig.setStartFull(false);
                      },
                    ),
                    AppSwitchTile(
                      title: '直接全屏播放',
                      subtitle: _autoPlay
                          ? '需先开启自动播放（startFull）'
                          : '需先开启「自动播放」才能启用',
                      value: _startFull && _autoPlay,
                      onChanged: (v) async {
                        if (!_autoPlay) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请先开启「自动播放」')));
                          return;
                        }
                        setState(() => _startFull = v);
                        await VideoPlayConfig.setStartFull(v);
                      },
                    ),
                    AppSwitchTile(
                      title: '全屏底部进度条',
                      subtitle: '全屏且隐藏控件时显示底部细进度条（fullBottomProgressBar）',
                      value: _fullBottomProgressBar,
                      onChanged: (v) async {
                        setState(() => _fullBottomProgressBar = v);
                        await VideoPlayConfig.setFullBottomProgressBar(v);
                      },
                    ),
                  ],
                ),
                const Divider(),
                const AppSectionHeader('长按倍速'),
                ListTile(
                  dense: true,
                  title: Text('长按倍速：${(_longPressSpeedTenths / 10).toStringAsFixed(1)}x'),
                  subtitle: Slider(
                    value: _longPressSpeedTenths
                        .clamp(VideoPlayConfig.minSpeedTenths,
                            VideoPlayConfig.maxSpeedTenths)
                        .toDouble(),
                    min: VideoPlayConfig.minSpeedTenths.toDouble(),
                    max: VideoPlayConfig.maxSpeedTenths.toDouble(),
                    divisions: VideoPlayConfig.maxSpeedTenths -
                        VideoPlayConfig.minSpeedTenths,
                    label: '${(_longPressSpeedTenths / 10).toStringAsFixed(1)}x',
                    onChanged: (v) =>
                        setState(() => _longPressSpeedTenths = v.round()),
                    onChangeEnd: (v) async {
                      await VideoPlayConfig.setLongPressSpeed(v.round());
                    },
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('恢复默认倍速（3.0x）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await VideoPlayConfig.setLongPressSpeed(
                        VideoPlayConfig.defaultSpeedTenths);
                    if (!mounted) return;
                    setState(() => _longPressSpeedTenths =
                        VideoPlayConfig.defaultSpeedTenths);
                  },
                ),
              ],
            ),
    );
  }
}

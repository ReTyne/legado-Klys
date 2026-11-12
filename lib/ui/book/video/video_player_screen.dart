import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/config/video_play_config.dart';
import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/danmaku_store.dart';

import 'package:legado_md3/ui/theme/app_design.dart';
part 'parts/video_player_screen_state.dart';
part 'parts/video_resume.dart';
part 'parts/danmaku_item.dart';
part 'parts/danmaku_text.dart';
part 'parts/danmaku_text_state.dart';
part 'parts/long_press_speed_picker_dialog.dart';
part 'parts/long_press_speed_picker_dialog_state.dart';
part 'parts/fullscreen_bottom_progress.dart';
part 'parts/fullscreen_bottom_progress_state.dart';


/// 视频播放器。
///
/// 画中画有两条真实通路：`NativeBridge.enterPip` 系统画中画，以及应用内
/// 可拖拽悬浮小窗（设备不支持系统 PiP 或进入失败时自动回退，二者并存）。
/// 弹幕支持文件缓存 / B 站 XML / JSON 三路加载，可调开关 / 透明度 / 字号。
/// 手势调亮度用叠加黑色遮罩模拟并持久化；手势调音量走现有占位提示。
class VideoPlayerScreen extends StatefulWidget {
  final Book book;
  final int initialChapter;
  const VideoPlayerScreen({super.key, required this.book, this.initialChapter = 0});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

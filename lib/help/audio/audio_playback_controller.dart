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

part 'parts/audio_play_mode_ext.dart';
part 'parts/audio_resume_point.dart';
part 'parts/audio_playback_controller.dart';


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

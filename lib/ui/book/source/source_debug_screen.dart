import 'package:flutter/material.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';

part 'parts/source_debug_screen_state.dart';
part 'parts/log_level.dart';
part 'parts/log_line.dart';
part 'parts/step_status.dart';
part 'parts/debug_step.dart';


/// 书源调试页（对齐 legado）：
/// * 「一键调试」：输入搜索内容后一键跑完整链路
///   搜索 → 书籍详情 → 目录 → 第一章正文，统一输出日志。
/// * 「分步调试」：搜索/发现/详情/目录/正文各自可单独执行，
///   每步用 Stopwatch 统计耗时，并展示该步请求 URL、返回摘要与引擎日志。
class SourceDebugScreen extends StatefulWidget {
  final BookSource source;

  const SourceDebugScreen({super.key, required this.source});

  @override
  State<SourceDebugScreen> createState() => _SourceDebugScreenState();
}

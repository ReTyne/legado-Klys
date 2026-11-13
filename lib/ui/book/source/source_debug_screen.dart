import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/source_network_log.dart';

part 'parts/source_debug_screen_state.dart';
part 'parts/log_level.dart';
part 'parts/log_line.dart';
part 'parts/step_status.dart';
part 'parts/debug_step.dart';


/// 书源调试页。
/// * 「一键调试」：输入调试目标后跑完整链路
///   搜索/发现 → 书籍详情 → 目录 → 第一章正文，统一输出日志。
/// * 「分步调试」：搜索/发现/详情/目录/正文各自可单独执行，
///   统计耗时并展示请求地址、返回摘要与引擎日志。
/// * 「发现分类」：列出书源发现分类，可单独调试某个分类，也可串起完整链路。
/// * 「请求响应」：展示状态码、耗时、请求地址、响应大小、来源通道、
///   请求头、响应头、最终地址与重定向链，另列书源配置请求头与最近请求地址。
/// * 「变量」：查看并临时编辑源变量与书籍变量，供后续调试步骤使用。
/// * 「原始源码」：查看各阶段抓取的原始 HTML/JSON。
/// * 支持把全部调试日志导出为纯文本（复制 / 分享 / 导出 txt 文件）。
class SourceDebugScreen extends StatefulWidget {
  final BookSource source;

  const SourceDebugScreen({super.key, required this.source});

  @override
  State<SourceDebugScreen> createState() => _SourceDebugScreenState();
}

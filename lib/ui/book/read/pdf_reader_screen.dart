import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/v14_models.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'parts/pdf_reader_screen_state.dart';
part 'parts/outline_sheet.dart';
part 'parts/raw_outline.dart';
part 'parts/pdf_outline_parser.dart';


/// PDF 本地书阅读页（基于 pdfx 位图分页渲染）。
///
/// 交互复刻 [ReadingScreen]：
/// * 点击页面中央唤出/隐藏菜单；
/// * 顶部菜单（返回、书名、更多：跳页/护眼/亮度）；
/// * 底部菜单（上一页/下一页、翻页滑杆、页码与总页数、跳页对话框、亮度滑杆、护眼遮罩）；
/// * 左右滑动翻页与双指缩放由 pdfx 的 [PdfView] 内置手势完成。
///
/// 阅读进度保存方式与 [ReadingScreen] 对齐：退出/翻页时调用
/// `BookProvider.saveReadingProgress`（durChapterIndex=0 对应 PDF 单章「正文」，
/// durChapterPos=当前页码），并同步 SharedPreferences 键
/// `pdf_progress_<书名>_<作者>` 便于单独恢复。
class PdfReaderScreen extends StatefulWidget {
  final Book book;

  const PdfReaderScreen({super.key, required this.book});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

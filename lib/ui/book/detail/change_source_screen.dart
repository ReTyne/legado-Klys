import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/book_highlight.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/source_result.dart';
part 'parts/change_source_screen_state.dart';
part 'parts/migration_options.dart';
part 'parts/migration_sheet.dart';
part 'parts/migration_sheet_state.dart';


/// 换源：并发在所有启用书源检索同一本书，切换为目标源的目录地址。
///
/// 换源后不再强制把进度清零，
/// 而是按「旧章节标题归一化」在新书源目录里匹配最接近的章节，保留阅读位置；
/// 无法匹配时回退到第 0 章（feature_gap §4-6）。
class ChangeSourceScreen extends StatefulWidget {
  final Book book;
  const ChangeSourceScreen({super.key, required this.book});

  @override
  State<ChangeSourceScreen> createState() => _ChangeSourceScreenState();
}

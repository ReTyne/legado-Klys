import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/book/reader_router.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';

/// 阅读记录 / 阅读统计域的共享配置与「开书」助手。
///
/// `enableReadRecord` 对齐 legado-E `AppConfig.enableReadRecord`：由
/// [ReadRecordScreen] 的开关写入，[ReadingStatsScreen] 读取决定是否计入统计，
/// 记录写入路径（`ReadingRecordService` / `tts_service`）在落库前读取该键。
/// `enableReadingStats` 控制统计页是否汇总展示。
/// 键均为 SharedPreferences 明文，便于其它组直接读取。
class ReadRecordConfig {
  ReadRecordConfig._();

  static const String keyEnableReadRecord = 'enableReadRecord';
  static const String keyEnableReadingStats = 'enableReadingStats';

  static Future<bool> isRecordEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keyEnableReadRecord) ?? true;
  }

  static Future<void> setRecordEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyEnableReadRecord, v);
  }

  static Future<bool> isStatsEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keyEnableReadingStats) ?? true;
  }

  static Future<void> setStatsEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyEnableReadingStats, v);
  }

  /// 点击阅读记录 / 统计明细：书架里有书直接打开对应阅读器，否则跳搜索页按书名搜索。
  /// 走 [readerForBook] 统一分流（文本/音频/漫画/视频/PDF），与书架点击行为一致。
  static Future<void> openBookOrSearch(
      BuildContext context, String bookName, String author) async {
    final book = await DatabaseService().getBook(bookName, author);
    if (!context.mounted) return;
    if (book != null) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => readerForBook(book)));
    } else {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SearchScreen(initialKeyword: bookName)));
    }
  }
}

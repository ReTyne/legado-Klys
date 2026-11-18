/// 模拟追读：按开始日期计算「已解锁章节数」的纯 Dart 逻辑。
///
/// 与自动翻页无关，仅用于限制阅读页可访问的章节上限。
/// 无 Flutter 依赖，便于直接单测。
library;

import 'dart:math';

/// 计算模拟追读当前可访问的章节数（1-based 章数）。
///
/// 规则：`min(totalChapters, max(0, startChapter + daysPassed * dailyChapters))`，
/// 其中 `daysPassed = now 与 startDate 相差的日历天数 + 1`。
/// [startDate] 非法（非 yyyy-MM-dd 或不是合法日期）或 [dailyChapters] <= 0 时
/// 不限制章节，直接返回 [totalChapters]。
int simulatedTotalChapterNum(
  int totalChapters, {
  required int startChapter,
  required String startDate,
  required int dailyChapters,
  DateTime? now,
}) {
  if (dailyChapters <= 0) return totalChapters;

  final start = _parseDate(startDate);
  if (start == null) return totalChapters;

  final today = now ?? DateTime.now();
  final current = DateTime(today.year, today.month, today.day);
  final daysPassed = current.difference(start).inDays + 1;
  final unlocked = startChapter + daysPassed * dailyChapters;

  return min(totalChapters, max(0, unlocked));
}

/// 严格按 yyyy-MM-dd 解析日期；格式不符或非法日期返回 null。
DateTime? _parseDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  // 排除 2026-02-30 之类被规范化的日期。
  if (parsed.year.toString().padLeft(4, '0') != value.substring(0, 4) ||
      parsed.month.toString().padLeft(2, '0') != value.substring(5, 7) ||
      parsed.day.toString().padLeft(2, '0') != value.substring(8, 10)) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

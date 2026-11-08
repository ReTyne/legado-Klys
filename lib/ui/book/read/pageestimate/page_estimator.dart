import 'package:flutter/material.dart';

import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/ui/book/read/text_paginator.dart';

/// 章节页数估算（对齐 fork `ChapterPageEstimator` / `HeuristicPageEstimator`）。
///
/// 精确模式直接复用 [TextPaginator.paginate] 的真实分页结果（与阅读页同一套
/// 测量逻辑，保证估算页数与实际翻页数一致）；未缓存正文或视口尺寸未知时
/// 退化为按字数/每页容量的启发式估算。
class ChapterPageEstimator {
  ChapterPageEstimator._();

  /// 与阅读页 `_textStyle` 一致的正文样式，保证测量口径一致。
  static TextStyle textStyle(ReadConfig config) => TextStyle(
        fontSize: config.textSize.toDouble(),
        height: config.lineSpacing * 0.5 + 1.0,
        letterSpacing: config.letterSpacing,
        wordSpacing: config.wordSpacing,
        fontWeight: config.boldText
            ? FontWeight.bold
            : FontWeight.values[((config.fontWeight ~/ 100) - 1)
                .clamp(0, FontWeight.values.length - 1)],
        fontFamily: config.fontFamily,
      );

  /// 每页可容纳字符数（启发式用）：随字号、可用宽高缩放。
  static int _charsPerPage(ReadConfig config, double width, double height) {
    final fontSize = config.textSize.toDouble();
    final lineHeight = fontSize * (config.lineSpacing * 0.5 + 1.0);
    final lines = (height / lineHeight).floor().clamp(1, 200);
    final perLine = (width / (fontSize * 1.05)).floor().clamp(8, 400);
    final gap = 1 + config.paragraphSpacing.clamp(0, 6);
    return (lines * perLine / (1 + gap * 0.15)).floor().clamp(120, 20000);
  }

  /// 精确估算：用真实分页器切页，返回页数。
  static int exact({
    required String content,
    required ReadConfig config,
    required double width,
    required double height,
  }) {
    if (content.trim().isEmpty || width <= 0 || height <= 0) {
      return heuristic(content: content, config: config, width: width, height: height);
    }
    final paragraphs = content
        .split(RegExp(r'\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return 1;
    final pages = TextPaginator.paginate(
      paragraphs: paragraphs,
      indent: TextPaginator.indentFor(config.textIndent),
      paraGapLines: config.paragraphSpacing.clamp(0, 10),
      maxWidth: width,
      maxHeight: height,
      style: textStyle(config),
      gapLinesConsumeHeight: config.readBodyToLh,
    );
    return pages.isEmpty ? 1 : pages.length;
  }

  /// 启发式估算：按章节字数 / 每页容量估算（正文尚未缓存时使用）。
  static int heuristic({
    required String content,
    required ReadConfig config,
    required double width,
    required double height,
    int? wordCount,
  }) {
    final chars = (wordCount != null && wordCount > 0)
        ? wordCount
        : content.replaceAll(RegExp(r'\s+'), '').length;
    if (chars <= 0) return 1;
    final w = width > 0 ? width : 360.0;
    final h = height > 0 ? height : 640.0;
    final perPage = _charsPerPage(config, w, h);
    return (chars / perPage).ceil().clamp(1, 100000);
  }

  /// 统一入口：有完整正文且视口可用 → 精确；否则启发式。
  /// 返回 `(页数, 模式)`，模式 1=精确 0=启发式。
  static ({int pages, int mode}) estimate({
    required String? content,
    required ReadConfig config,
    required double width,
    required double height,
    int? wordCount,
    bool exactMode = true,
  }) {
    final text = content ?? '';
    if (exactMode && text.trim().isNotEmpty && width > 0 && height > 0) {
      return (
        pages: exact(
            content: text, config: config, width: width, height: height),
        mode: 1,
      );
    }
    return (
      pages: heuristic(
          content: text,
          config: config,
          width: width,
          height: height,
          wordCount: wordCount),
      mode: 0,
    );
  }
}

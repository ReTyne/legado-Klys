import 'package:flutter/material.dart';

/// 真实文本分页器
///
/// 用 [TextPainter] 逐段测量真实行高与换行位置，按可用宽高切页，
/// 替代"按字数估算"的粗糙分页。每页由若干实际渲染行用 '\n' 连接，
/// 便于直接交给 [Text] 渲染且行高一致。
class TextPaginator {
  /// 将段落列表真实分页。
  ///
  /// - [paragraphs] 原始段落（不含缩进，不含段间空行）
  /// - [indent] 每段首行前缀（如全角缩进）
  /// - [paraGapLines] 段间距（插入的空行数）
  /// - [maxWidth] 可用文本宽度
  /// - [maxHeight] 每页可用高度
  /// - [style] 正文样式
  static List<String> paginate({
    required List<String> paragraphs,
    required String indent,
    required int paraGapLines,
    required double maxWidth,
    required double maxHeight,
    required TextStyle style,
  }) {
    if (paragraphs.isEmpty) return const [''];
    if (maxWidth <= 0 || maxHeight <= 0) return [paragraphs.join('\n\n')];

    final lineHeight = _measureLineHeight(style, maxWidth);
    final pages = <String>[];
    final current = <String>[];
    var used = 0.0;

    void flush() {
      if (current.isNotEmpty) {
        pages.add(current.join('\n'));
        current.clear();
        used = 0;
      }
    }

    void addLine(String line) {
      if (used + lineHeight > maxHeight && current.isNotEmpty) {
        flush();
      }
      current.add(line);
      used += lineHeight;
    }

    for (var i = 0; i < paragraphs.length; i++) {
      final para = (indent + paragraphs[i]);
      final lines = _measureLines(para, style, maxWidth);
      if (i > 0) {
        for (var g = 0; g < paraGapLines; g++) {
          addLine('');
        }
      }
      for (final line in lines) {
        addLine(line);
      }
    }
    flush();
    return pages.isEmpty ? [paragraphs.join('\n\n')] : pages;
  }

  /// 测量单行高度（含行距倍数）
  static double _measureLineHeight(TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: '测量行高', style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth);
    final metrics = tp.computeLineMetrics();
    final h = metrics.isNotEmpty ? metrics.first.height : (style.fontSize ?? 16) * 1.5;
    tp.dispose();
    return h;
  }

  /// 测量一段文本在给定宽度下的实际换行行
  static List<String> _measureLines(String text, TextStyle style, double maxWidth) {
    if (text.trim().isEmpty) return [text];
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth);
    final metrics = tp.computeLineMetrics();
    final result = <String>[];
    if (metrics.isEmpty) {
      tp.dispose();
      return [text];
    }
    var offset = 0;
    for (var i = 0; i < metrics.length && offset < text.length; i++) {
      final boundary = tp.getLineBoundary(TextPosition(offset: offset));
      var start = boundary.start;
      var end = boundary.end;
      if (start < 0) start = 0;
      if (end > text.length) end = text.length;
      if (end < start) end = start;
      result.add(text.substring(start, end));
      offset = end;
    }
    tp.dispose();
    return result.isEmpty ? [text] : result;
  }

  /// 首行缩进：用全角空格，保证中文缩进宽度等价
  static String indentFor(int chars) {
    if (chars <= 0) return '';
    return '　' * chars;
  }
}

import 'dart:convert';

import 'package:enough_convert/enough_convert.dart';

///  `help/JsExtensions.kt` + `utils/StringUtils.kt` +
/// `utils/HtmlFormatter.kt` 的 JS 扩展函数语义。
///
/// JS 桥（`legado_bridge_js_08.dart`）里这几个函数过去是简化实现：
/// - `htmlFormat` 直接去所有标签 → 会丢掉正文图片；
/// - `toNumChapter` 只 `parseInt` 去前导零 → 不认「第一章」；
/// - `strToBytes/bytesToStr` 忽略 charset 参数。
///
/// 本类把上游真实语义抽成纯 Dart 函数，既供 Dart 侧正文处理复用，也作为
/// JS 桥实现的对照契约（可用单元测试锁定行为）。
class JsTextUtils {
  JsTextUtils._();

  /// 上游 `chnMap`：零~十、大写数字、两、百/佰、千/仟、万、亿。
  static const Map<String, int> _chnMap = {
    '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    '〇': 0, '壹': 1, '贰': 2, '叁': 3, '肆': 4,
    '伍': 5, '陆': 6, '柒': 7, '捌': 8, '玖': 9, '拾': 10,
    '两': 2, '百': 100, '佰': 100, '千': 1000, '仟': 1000,
    '万': 10000, '亿': 100000000,
  };

  /// 上游 `StringUtils.fullToHalf`：全角空格→半角，全角 ASCII→半角。
  static String fullToHalf(String input) {
    final buf = StringBuffer();
    for (final r in input.runes) {
      if (r == 12288) {
        buf.writeCharCode(32);
      } else if (r >= 65281 && r <= 65374) {
        buf.writeCharCode(r - 65248);
      } else {
        buf.writeCharCode(r);
      }
    }
    return buf.toString();
  }

  /// 上游 `StringUtils.stringToInt`：全角转半角、去空白，先按十进制整数
  /// 解析，失败再走 [chineseNumToInt]；都不行返回 -1。
  static int stringToInt(String? s) {
    if (s == null) return -1;
    final half = fullToHalf(s).replaceAll(RegExp(r'\s+'), '');
    // 上游 `Integer.parseInt("")` 抛异常后回落 chineseNumToInt("")，空循环
    // 不抛异常，结果为 0；这里不做提前返回，保持该可观察行为。
    final arabic = int.tryParse(half);
    if (arabic != null) return arabic;
    return chineseNumToInt(half);
  }

  /// 上游 `StringUtils.chineseNumToInt`。
  ///
  /// 支持「一零二五」逐字拼接形式，以及「一千零二十五」/「一千二」等
  /// 带单位形式；解析失败返回 -1（与上游 `getOrDefault(-1)` 一致）。
  static int chineseNumToInt(String chNum) {
    // 上游对空串：cn.size==0，`for` 不执行，最终 `result += tmp + billion`
    // 得到 0（不抛异常），故不是 -1。
    if (chNum.isEmpty) return 0;
    final cn = chNum.split('');

    // 「一零二五」形式：全是单数字字符且长度 > 1 时按位拼接
    final digitChars = RegExp(r'^[〇零一二三四五六七八九壹贰叁肆伍陆柒捌玖]+$');
    if (cn.length > 1 && digitChars.hasMatch(chNum)) {
      final sb = StringBuffer();
      for (final c in cn) {
        final v = _chnMap[c];
        if (v == null) return -1;
        sb.write(v);
      }
      return int.tryParse(sb.toString()) ?? -1;
    }

    var result = 0;
    var tmp = 0;
    var billion = 0;
    for (var i = 0; i < cn.length; i++) {
      final tmpNum = _chnMap[cn[i]];
      if (tmpNum == null) return -1; // 未映射字符 → 上游抛异常回退 -1
      if (tmpNum == 100000000) {
        result += tmp;
        result *= tmpNum;
        billion = billion * 100000000 + result;
        result = 0;
        tmp = 0;
      } else if (tmpNum == 10000) {
        result += tmp;
        result *= tmpNum;
        tmp = 0;
      } else if (tmpNum >= 10) {
        if (tmp == 0) tmp = 1;
        result += tmpNum * tmp;
        tmp = 0;
      } else {
        // 上游：`一千二` 末尾补零（12 → 1200）
        final prev = i >= 2 ? (_chnMap[cn[i - 1]] ?? 0) : 0;
        tmp = (i >= 2 && i == cn.length - 1 && prev > 10)
            ? tmpNum * prev ~/ 10
            : tmp * 10 + tmpNum;
      }
    }
    return result + tmp + billion;
  }

  /// 上游 `JsExtensions.toNumChapter`：`(第)(.+?)(章)` → 中间数字用
  /// [stringToInt] 转成阿拉伯数字，其余原样；不匹配返回原串。
  static String? toNumChapter(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(第)(.+?)(章)').firstMatch(s);
    if (m == null) return s;
    final n = stringToInt(m.group(2));
    return '${m.group(1)}$n${m.group(3)}';
  }

  /// 上游 `HtmlFormatter.formatKeepImg`：
  /// 1. 去 `&nbsp;` 等空格实体、注释、除 `<img>` 外的所有标签；
  /// 2. `div/p/br/hr/hN/article/dd/dl` 等块级标签转换为换行；
  /// 3. 规范化 `<img>`，只保留 `src`（含 `data-src` 等懒加载）；
  /// 4. 段落首行缩进两个全角空格、去首尾空白。
  static String htmlFormat(String? html) {
    if (html == null) return '';
    var s = html;
    s = s.replaceAll(RegExp(r'(&nbsp;)+'), ' ');
    s = s.replaceAll(RegExp(r'(&ensp;|&emsp;)'), ' ');
    s = s.replaceAll(
        RegExp(r'(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)'), '');
    // 块级标签 → 换行
    s = s.replaceAll(
        RegExp(r'</?(?:div|p|br|hr|h\d|article|dd|dl)[^>]*>',
            caseSensitive: false),
        '\n');
    // 注释
    s = s.replaceAll(RegExp(r'<!--[^>]*-->'), '');
    // 先把 img 占位保护起来，再去掉其它标签
    final images = <String>[];
    s = s.replaceAllMapped(RegExp(r'<img[^>]*>', caseSensitive: false), (m) {
      images.add(_normalizeImg(m.group(0)!));
      return '\u0000IMG${images.length - 1}\u0000';
    });
    // 去掉剩余所有非 img 标签（img 已被占位）
    s = s.replaceAll(RegExp(r'</?[a-zA-Z]+(?=[ >])[^<>]*>'), '');
    // 恢复 img
    s = s.replaceAllMapped(RegExp('\u0000IMG(\\d+)\u0000'), (m) {
      final i = int.tryParse(m.group(1) ?? '') ?? -1;
      return (i >= 0 && i < images.length) ? images[i] : '';
    });
    // 缩进与去首尾空白
    s = s.replaceAll(RegExp(r'\s*\n+\s*'), '\n　　');
    s = s.replaceAll(RegExp(r'^[\n\s]+'), '　　');
    s = s.replaceAll(RegExp(r'[\n\s]+$'), '');
    return s;
  }

  /// 从 `<img ...>` 中提取 src（支持 `src` / `data-src` / `data-original` /
  /// `data-srcset`），输出规范化的 `<img src="...">`。
  static String _normalizeImg(String tag) {
    // 1) 带 {..} 书源规则参数的 src；2) data-(src|original|srcset) 懒加载；
    // 3) 普通 src（要求属性名前是空白，避免把 data-src 误当 src）；
    // 4) 任意 data-* 属性兜底。上游把懒加载属性排在普通 src 之前，
    // 这样 `<img src="占位.gif" data-src="真图.jpg">` 取到的是真图。
    final patterns = [
      RegExp(r'''\ssrc\s*=\s*["']([^"'>]*\{[^{}]+\}[^"'>]*)["']''',
          caseSensitive: false),
      RegExp(r'''\sdata-(?:src|original|srcset)\s*=\s*["']([^"'>]+)["']''',
          caseSensitive: false),
      RegExp(r'''\ssrc\s*=\s*["']([^"'>]*)["']''', caseSensitive: false),
      RegExp(r'''\sdata-[^=\s]+\s*=\s*["']([^"'>]*)["']''',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(tag);
      if (m != null) return '<img src="${m.group(1)}">';
    }
    return tag;
  }

  /// Java `charset(name)` 的别名归一化：去掉大小写、连字符、下划线差异。
  /// `GB_2312` / `GB2312` / `gb-2312` / `GBK` 都归到 GBK 家族。
  static String _normCharset(String? charset) =>
      (charset ?? 'utf-8').toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');

  static bool _isGbk(String cs) =>
      cs == 'gbk' ||
      cs == 'gb2312' ||
      cs == 'gb18030' ||
      cs == 'cp936' ||
      cs == 'gb';

  static bool _isLatin1(String cs) =>
      cs == 'latin1' || cs == 'iso88591' || cs == 'iso8859' || cs == 'l1';

  /// 上游 `strToBytes(str, charset)` 的 charset 语义：
  /// utf-8 用 UTF-8；GBK 家族用 GBK；Latin-1 家族用 Latin-1；其余回退 UTF-8。
  /// 未覆盖的字符集在 JS 桥里由 `TextDecoder/TextEncoder` 标签兜底，此处为
  /// Dart 侧纯函数对照契约（Flutter 无 Java `Charset.forName` 全字符集能力）。
  static List<int> strToBytes(String? str, {String? charset}) {
    final s = str ?? '';
    final cs = _normCharset(charset);
    if (_isGbk(cs)) return const GbkCodec().encode(s);
    if (_isLatin1(cs)) return latin1.encode(s);
    return utf8.encode(s);
  }

  /// 上游 `bytesToStr(bytes, charset)`：按 charset 解码字节数组。
  static String bytesToStr(List<int> bytes, {String? charset}) {
    final cs = _normCharset(charset);
    if (_isGbk(cs)) return const GbkCodec().decode(bytes);
    if (_isLatin1(cs)) return latin1.decode(bytes, allowInvalid: true);
    return utf8.decode(bytes, allowMalformed: true);
  }
}

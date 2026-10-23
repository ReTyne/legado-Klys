import 'package:legado_md3/utils/chinese_utils.dart';

/// 简繁转换工具（对齐 legado-E 的 ChineseConverter）。
///
/// 实际转换委托给 [ChineseUtils]：词组优先 + 单字兜底的最长匹配，
/// 比单纯逐字替换更准确（如「计算机」「头发」等词组不会被误拆）。
class ChineseConverter {
  /// 转换正文。mode: 0=不转换 1=转简体 2=转繁体
  static String convert(String text, int mode) {
    if (mode == 1) return ChineseUtils.t2s(text);
    if (mode == 2) return ChineseUtils.s2t(text);
    return text;
  }

  /// 是否包含繁体字
  static bool containsTraditional(String text) => ChineseUtils.containsT(text);

  /// 是否包含简体字
  static bool containsSimplified(String text) => ChineseUtils.containsS(text);
}

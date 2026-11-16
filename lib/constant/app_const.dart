import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 应用级常量与通用工具。
///
/// 集中收敛请求头键名、并发上限、字符集、设备标识生成，以及分组拆分 /
/// 中文排序 / 发现分类缓存键等被多处复用的纯函数。
class AppConst {
  AppConst._();

  /// HTTP 请求头中 User-Agent 的键名。
  // ignore: constant_identifier_names
  static const String UA_NAME = 'User-Agent';

  /// 默认最大并发线程数。
  // ignore: constant_identifier_names
  static const int MAX_THREAD = 16;

  /// 常用字符集列表（网页解码 / 书源 charset 下拉候选）。
  static const List<String> charsets = <String>[
    'UTF-8',
    'GBK',
    'GB2312',
    'GB18030',
    'BIG5',
    'ISO-8859-1',
    'UTF-16',
    'UTF-16LE',
    'UTF-16BE',
    'windows-1252',
    'Shift_JIS',
    'EUC-KR',
    'KOI8-R',
  ];

  /// 生成一个 16 位十六进制设备标识。
  static String androidId() {
    final rnd = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(rnd.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// 分组串的统一分隔符：逗号、分号（中英文）、顿号、任意空白。
  static final RegExp groupSplitRegex = RegExp(r'[,;，；、\s]+');

  /// 按统一分隔符拆分分组串：去首尾空白、过滤空项、保持原顺序。
  static List<String> splitGroups(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    return raw
        .split(groupSplitRegex)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 分组中文排序比较器。
  ///
  /// 规则（确定性）：拉丁字母大小写不敏感按字典序；汉字等非 ASCII 字符按
  /// Unicode 码点升序，自然排在 ASCII 之后；前缀相同则短串在前。
  static int compareGroups(String a, String b) {
    final ar = a.runes.toList();
    final br = b.runes.toList();
    final n = ar.length < br.length ? ar.length : br.length;
    for (var i = 0; i < n; i++) {
      final va = _foldRune(ar[i]);
      final vb = _foldRune(br[i]);
      if (va != vb) return va.compareTo(vb);
    }
    return ar.length.compareTo(br.length);
  }

  static int _foldRune(int c) => (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c;

  /// 发现分类缓存键：包含 exploreUrl 的内容哈希，分类配置变化后自动失效。
  static String exploreKindsCacheKey(String sourceUrl, String exploreUrl) {
    final hash =
        md5.convert(utf8.encode(exploreUrl)).toString().substring(0, 8);
    return 'exploreKinds_${sourceUrl}_$hash';
  }
}

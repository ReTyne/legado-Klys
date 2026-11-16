import 'package:legado_md3/data/model/book_source.dart';
import 'parts/engine_primitives.dart';

/// 书源实体能力的 extension 兜底。
///
/// 数据层后续会在 [BookSource] 上补同名实例方法（getBookType /
/// getExploreKindsKey / getSourceType / getCheckKeyword / hasGroup /
/// getDisplayNameGroup）。为避免重复定义冲突，这里统一使用 `ext` 前缀命名；
/// 实体方法就位后可由 team-lead 决定改为直接转发。
extension BookSourceEngineExt on BookSource {
  /// 书源类型位标志：文本 0 / 音频 1 / 图片 2 / 文件 4 / 视频 8。
  int extGetBookType() {
    switch (bookSourceType) {
      case 1:
        return kBookTypeAudio;
      case 2:
        return kBookTypeImage;
      case 3:
        return kBookTypeFile;
      case 4:
        return kBookTypeVideo;
      default:
        return kBookTypeText;
    }
  }

  /// 发现分类缓存键：含 exploreUrl 内容哈希，配置变更自动失效。
  String extGetExploreKindsKey() =>
      exploreKindsCacheKey(bookSourceUrl, exploreUrl ?? '');

  /// 书源类型值（与实体字段一致）。
  int extGetSourceType() => bookSourceType;

  /// 调试页推荐关键词：兼容 ruleSearch.checkKeyWord 与顶层字段回退。
  String extGetCheckKeyword() => effectiveCheckKeyWord ?? '';

  /// 是否属于指定分组（分组串按逗号/空格切分比较）。
  bool extHasGroup(String group) {
    final g = group.trim();
    if (g.isEmpty) return false;
    final raw = bookSourceGroup ?? '';
    return raw
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .contains(g);
  }

  /// 展示用分组名：取首个分组并去掉纯数字排序前缀（如 `01_玄幻`）。
  String extGetDisplayNameGroup() {
    final raw = (bookSourceGroup ?? '').trim();
    if (raw.isEmpty) return '';
    final first = raw.split(RegExp(r'[,，\s]+')).first.trim();
    return first.replaceFirst(RegExp(r'^\d+[._\-、]\s*'), '');
  }
}

/// 书源类型位标志常量。
const int kBookTypeText = 0;
const int kBookTypeAudio = 1 << 0;
const int kBookTypeImage = 1 << 1;
const int kBookTypeFile = 1 << 2;
const int kBookTypeVideo = 1 << 3;

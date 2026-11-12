import 'package:legado_md3/utils/alphanum_comparator.dart';

/// 批次 6 · Web 端点参数边界（ `service/WebService.kt` 与
/// `api/controller/BookController.kt`），集中为纯函数以便单元回归。

// ---- 端口（WebService.kt:185-191）----
const int webPortMin = 1024;
const int webPortMax = 65530;
const int webPortDefault = 1122;

/// `1024..65530` 之外（上界为 WS 的 port+1 留余量）统一回退 1122。
int validateWebPort(int port) =>
    (port < webPortMin || port > webPortMax) ? webPortDefault : port;

// ---- 正文图片宽度（BookController.kt:105）----
const int imageWidthDefault = 640;

/// `width` 缺省/非法（含 <=0）时回退 640。
int parseImageWidth(String? raw) {
  final v = int.tryParse(raw?.trim() ?? '');
  return (v == null || v <= 0) ? imageWidthDefault : v;
}

// ---- 封面（BookController.kt:69-94）----
/// 封面加载 3 秒超时（上游 `ftBitmap.get(3, TimeUnit.SECONDS)`）。
const Duration coverLoadTimeout = Duration(seconds: 3);

/// 上游封面固定 84×112（`.override(84, 112)`）。
const int coverWidth = 84;
const int coverHeight = 112;

// ---- 章节等待（BookController.kt:186-195）----
const int chapterWaitMaxAttempts = 30;
const Duration chapterWaitInterval = Duration(seconds: 1);

/// 轮询等待 [probe] 返回非空值：最多 [maxAttempts] 次，每次间隔 [interval]。
/// 始终为 null 时返回 null。「30 次 × 1s 等待章节入库」。
Future<T?> pollForValue<T>(
  Future<T?> Function() probe, {
  int maxAttempts = chapterWaitMaxAttempts,
  Duration interval = chapterWaitInterval,
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    final value = await probe();
    if (value != null) return value;
    if (i < maxAttempts - 1) await Future.delayed(interval);
  }
  return null;
}

// ---- 书架排序四分支（BookController.kt:53-61）----
/// [sortType]：1=最新章节时间降序，2=书名中文序，3=手动顺序升序，
/// 其它=阅读时间降序（默认，对齐 `sortedByDescending { durChapterTime }`）。
///
/// 上游分支 2 用 `cnCompare`（依赖中文拼音/笔画 Collator）；纯 Dart 无等价
/// 排序器，降级为 [AlphanumComparator] 自然序（数字块按数值比较，中文按码点），
/// 至少避免「书名含数字」时的字典序错乱。
///
/// 以泛型 + 字段提取器实现，避免本文件依赖 `data/model/book.dart`
/// （并行批次中该文件会经由 `constant/book_type.dart` 传递依赖，隔离冲突）。
List<T> sortBookshelf<T>(
  List<T> books,
  int sortType, {
  required int Function(T) latestChapterTime,
  required String Function(T) name,
  required int? Function(T) order,
  required int Function(T) durChapterTime,
}) {
  final list = List<T>.from(books);
  switch (sortType) {
    case 1:
      list.sort((a, b) =>
          latestChapterTime(b).compareTo(latestChapterTime(a)));
      break;
    case 2:
      list.sort((a, b) => AlphanumComparator.compare(name(a), name(b)));
      break;
    case 3:
      list.sort((a, b) => (order(a) ?? 0).compareTo(order(b) ?? 0));
      break;
    default:
      list.sort(
          (a, b) => durChapterTime(b).compareTo(durChapterTime(a)));
  }
  return list;
}

/// Flutter 本地偏好 `bs_sortType`（0最近阅读/1书名/2作者/3添加时间/4手动）
/// 映射到上游 `bookshelfSort` 四分支取值，保证 Web 与 App 书架顺序一致。
int mapLocalBookshelfSort(int local) {
  switch (local) {
    case 1:
      return 2; // 书名 → cnCompare 分支
    case 4:
      return 3; // 手动 → order 升序
    default:
      return 0; // 其余 → 默认（阅读时间降序，等价「最近阅读」）
  }
}

// ---- 多 IP 严格 IPv4 校验（NetworkUtils.kt:278-283）----
bool isStrictIPv4Address(String? input) {
  if (input == null || input.isEmpty) return false;
  if (input.codeUnitAt(0) < 0x31 || input.codeUnitAt(0) > 0x39) return false;
  final parts = input.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}

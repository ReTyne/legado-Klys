/// 逐字对齐 legado-E `constant/BookType.kt` / `constant/BookSourceType.kt`
/// 与 `data/DatabaseMigrations.kt` 的 `Migration_54_55`。
///
/// 上游用「2 的幂位」表示书籍类型，一本可叠加多位，DAO 全部依赖
/// `type & mask > 0` 判定分组。本项目 `Book.type` 历史上用顺序枚举
/// (0 文本 / 1 本地 / 2 音频 / 3 图片 / 4 视频，见 data/model/book.dart)，
/// 且被 reader_router.dart / book_provider.dart 的 switch 直接消费。
///
/// 因此这里**不改变 `Book.type` 的落库语义**：本文件只提供位标志权威定义、
/// 与 Flutter 枚举的双向转换，供「备份导入/导出边界」与「DAO 位运算过滤」使用。
/// 与 Android 备份互通时，位标志值与上游完全一致。
/// 旧版书源类型（legado-E `constant/BookSourceType.kt:6-12`）。
/// v54→55 之前 books.type 存这些值，迁移时重映射为 [BookType] 位标志。
class BookSourceType {
  BookSourceType._();

  static const int defaultType = 0; // 文本（上游常量名为 default，Dart 关键字）
  static const int audio = 1;
  static const int image = 2;
  static const int file = 3;
  static const int video = 4;
}

/// 书籍类型位标志（legado-E `constant/BookType.kt:14-66`）。
/// 每一位代表一个类型，数值为 2 的 n 次方，可叠加；>=8 与老版本类型区分。
class BookType {
  BookType._();

  /// 4 视频 (0b100)
  static const int video = 4;

  /// 8 文本 (0b1000)
  static const int text = 8;

  /// 16 更新失败 (0b10000)
  static const int updateError = 16;

  /// 32 音频 (0b100000)
  static const int audio = 32;

  /// 64 图片 (0b1000000)
  static const int image = 64;

  /// 128 只提供下载服务的网站 (0b10000000)
  static const int webFile = 128;

  /// 256 本地 (0b100000000)
  static const int local = 256;

  /// 512 压缩包（从压缩包内解压来的书籍文件） (0b1000000000)
  static const int archive = 512;

  /// 1024 未正式加入到书架的临时阅读书籍 (0b10000000000)
  static const int notShelf = 1024;

  /// 所有可以从书源转换的书籍类型（BookType.kt:64）
  static const int allBookType = video | text | image | audio | webFile;

  /// 含本地位的所有书籍类型（BookType.kt:66）
  static const int allBookTypeLocal = allBookType | local;

  /// 本地书籍书源标志（BookType.kt:71）
  static const String localTag = 'loc_book';

  /// webDav:: 开头的书籍（BookType.kt:76）
  static const String webDavTag = 'webDav::';

  /// Flutter 端顺序枚举值（data/model/book.dart 的 Book.typeXxx）。
  static const int flutterText = 0;
  static const int flutterLocal = 1;
  static const int flutterAudio = 2;
  static const int flutterImage = 3;
  static const int flutterVideo = 4;

  /// 上游 `type & mask > 0` 的判定。
  static bool hasFlag(int type, int flag) => (type & flag) > 0;

  /// 上游 `type & mask = 0` 的判定。
  static bool notFlag(int type, int flag) => (type & flag) == 0;

  /// 是否为「位标志格式」而非 Flutter 顺序枚举。
  /// Flutter 枚举最大为 4，任何 >= text(8) 的值必然是位标志；
  /// video(4) 与 Flutter typeVideo(4) 数值相同、语义一致，无需区分。
  static bool isBitmapType(int type) => type >= text;

  /// `update books set type = type | local where origin like 'loc_book%'/'webDav::%'`
  /// （DatabaseMigrations.kt:356-361）。按 origin 前缀补本地位，幂等。
  static int applyLocalBit(int type, String? origin) {
    if (origin == null) return type;
    if (origin.startsWith(localTag) || origin.startsWith(webDavTag)) {
      return type | local;
    }
    return type;
  }

  /// Migration_54_55：旧 BookSourceType 值 → 位标志（DatabaseMigrations.kt:331-361
  /// 的四条 `update books set type = ... where type = ...`），再按 origin 前缀补 local 位。
  ///
  /// 幂等：仅 0..3 命中映射；4(video) 旧值与位标志数值相同保持；
  /// >=8 已是位标志组合保持。故重复执行不会二次改写。
  static int remapLegacyType(int oldType, {String? origin}) {
    final int result;
    switch (oldType) {
      case BookSourceType.defaultType: // 0 -> text
        result = text;
        break;
      case BookSourceType.audio: // 1 -> audio
        result = audio;
        break;
      case BookSourceType.image: // 2 -> image
        result = image;
        break;
      case BookSourceType.file: // 3 -> webFile
        result = webFile;
        break;
      default:
        result = oldType;
    }
    return applyLocalBit(result, origin);
  }

  /// 位标志 → Flutter 顺序枚举（备份导入落库用）。
  ///
  /// 有信息损失（本就无法与上游完全等价，显式标注）：
  /// - local 是可叠加位，Flutter 由独立 `Book.local` 布尔兜底（配合 fromMap 置位）；
  /// - updateError/archive/notShelf/webFile 在 Flutter 无独立枚举，归入文本。
  static int toFlutterEnum(int flags) {
    if (hasFlag(flags, audio)) return flutterAudio;
    if (hasFlag(flags, video)) return flutterVideo;
    if (hasFlag(flags, image)) return flutterImage;
    if (hasFlag(flags, local)) return flutterLocal;
    return flutterText;
  }

  /// Flutter 顺序枚举 → 位标志（跨端导出用）。
  static int fromFlutterEnum(int enumType, {String? origin, bool isLocal = false}) {
    int flags;
    switch (enumType) {
      case flutterLocal:
        flags = text | local;
        break;
      case flutterAudio:
        flags = audio;
        break;
      case flutterImage:
        flags = image;
        break;
      case flutterVideo:
        flags = video;
        break;
      default:
        flags = text;
    }
    if (isLocal) flags |= local;
    return applyLocalBit(flags, origin);
  }
}

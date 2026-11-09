import 'book_type.dart';

/// 逐字对齐 legado-E：
/// - `data/entities/BookGroup.kt:32-40` 的 7 个内置虚拟分组常量；
/// - `data/AppDatabase.kt:177-242` `onOpen` 的幂等插入 / 开库脏数据修复 SQL；
/// - `data/dao/BookDao.kt:21-82` `flowByGroup` 的位运算分组过滤。
///
/// 本项目 `book_groups` 表主键是自增 `id`、列为 `groupId/name/"order"/show/cover`
/// (+ v14 补的 `enableRefresh`)，与上游 `groupId` 主键 / `groupName` 列不同；
/// 因此 SQL 的**列名按本项目适配**，但 groupId/order/show/enableRefresh 的
/// **取值逐字对齐上游**。上游用 `where not exists` 保证每次开库幂等。

/// 一个内置虚拟分组行（对齐 AppDatabase.kt onOpen 的 insert 值）。
class VirtualGroupRow {
  final int groupId;
  final String name;
  final int order;
  final int show;
  final int enableRefresh;

  const VirtualGroupRow(
    this.groupId,
    this.name,
    this.order,
    this.show,
    this.enableRefresh,
  );
}

/// 7 个内置虚拟分组 + onOpen SQL 生成。
class VirtualBookGroup {
  VirtualBookGroup._();

  /// BookGroup.kt companion（IdRoot 是 flowByGroup 的分支锚点，但 onOpen 不插入行）
  static const int idRoot = -100;
  static const int idAll = -1;
  static const int idLocal = -2;
  static const int idAudio = -3;
  static const int idNetNone = -4;
  static const int idLocalNone = -5;
  static const int idVideo = -6;
  static const int idError = -11;

  /// AppDatabase.kt:180-226 的 7 行（顺序与 order 值一致）：
  ///  - IdLocal 带 enableRefresh=0；IdLocalNone 带 show=0；
  ///  - 其余 show=1、enableRefresh 走表默认 1；
  ///  - order：全部 -10 / 本地 -9 / 音频 -8 / 网络未分组 -7 /
  ///    本地未分组 -6 / 视频 -5 / 更新失败 -1。
  static const List<VirtualGroupRow> builtIns = <VirtualGroupRow>[
    VirtualGroupRow(idAll, '全部', -10, 1, 1),
    VirtualGroupRow(idLocal, '本地', -9, 1, 0),
    VirtualGroupRow(idAudio, '音频', -8, 1, 1),
    VirtualGroupRow(idNetNone, '网络未分组', -7, 1, 1),
    VirtualGroupRow(idLocalNone, '本地未分组', -6, 0, 1),
    VirtualGroupRow(idVideo, '视频', -5, 1, 1),
    VirtualGroupRow(idError, '更新失败', -1, 1, 1),
  ];

  /// 生成 7 条 `insert ... select ... where not exists` 幂等插入 SQL
  /// （对齐 AppDatabase.kt:179-226）。列名按 book_groups 表适配为
  /// `groupId/name/"order"/show/enableRefresh`；上游列名为 groupName。
  static List<String> buildInsertSqls({String table = 'book_groups'}) =>
      builtIns.map((VirtualGroupRow g) {
        return 'insert into $table(groupId, name, "order", show, enableRefresh) '
            "select ${g.groupId}, '${g.name}', ${g.order}, ${g.show}, ${g.enableRefresh} "
            'where not exists '
            '(select * from $table where groupId = ${g.groupId})';
      }).toList();

  /// 上游 onOpen 的 4 条脏数据修复 SQL 原文（AppDatabase.kt:228-242），
  /// 仅作契约留存：Flutter 表名/列不同，实际执行见 [buildRepairSqls]。
  static const List<String> upstreamRepairSqls = <String>[
    "update book_sources set loginUi = null where loginUi = 'null'",
    "update rssSources set loginUi = null where loginUi = 'null'",
    "update httpTTS set loginUi = null where loginUi = 'null'",
    "update httpTTS set concurrentRate = '0' where concurrentRate is null",
  ];

  /// 本项目可执行的开库修复 SQL（幂等）。与上游对照：
  /// - `book_sources` / `rss_sources` 的 loginUi：表名/列一一对应，照搬；
  /// - `httpTTS.loginUi`：本项目 `http_tts` 表**无 loginUi 列**，无法等价实现 →
  ///   跳过（不伪造列）；
  /// - `httpTTS.concurrentRate`：本项目 `http_tts.concurrentRate` 为 INTEGER，
  ///   上游写字符串 '0'；这里补数值 0，NULL→0 语义等价；
  /// - `keyboardAssists` 空表灌默认数据：本项目 `keyboard_assists` 表结构
  ///   (name/rule/...) 与上游 (type/key/value/serialNo) 不同，且无
  ///   `defaultData/keyboardAssists.json` 资源，无法等价灌入 → 跳过。
  static List<String> buildRepairSqls() => const <String>[
        "update book_sources set loginUi = null where loginUi = 'null'",
        "update rss_sources set loginUi = null where loginUi = 'null'",
        "update http_tts set concurrentRate = 0 where concurrentRate is null",
      ];
}

/// `BookDao.flowByGroup` 的位运算分组过滤（BookDao.kt:21-82）。
///
/// 上游在 books.type（位标志列）上直接用 `type & X > 0` 与
/// `(SELECT sum(groupId) FROM book_groups where groupId > 0) & group` 子查询判定。
/// 本项目 books.type 存 Flutter 顺序枚举，无法直接对该列套用上游位规则，
/// 故同时提供：
///  - [buildFlowByGroupWhere] / [buildFlowByGroupSql]：逐字复刻上游 SQL（契约 / 未来切换用）；
///  - [matchesGroup]：Dart 层把书投影成位标志后应用**同一套**位规则（报告 #17 允许的等价实现）。
class BookGroupQuery {
  BookGroupQuery._();

  /// 生成上游 flowByGroup 各分支的 WHERE 子句（逐字复刻 BookDao.kt）。
  /// [groupColumn] / [groupTable] 可切到本项目列名（group_name / book_groups）。
  static String buildFlowByGroupWhere(
    int groupId, {
    String groupColumn = '`group`',
    String groupTable = 'book_groups',
  }) {
    final String sumExpr =
        '(SELECT sum(groupId) FROM $groupTable where groupId > 0) & $groupColumn';
    switch (groupId) {
      case VirtualBookGroup.idRoot:
        // BookDao.kt:37-44 flowRoot
        return 'type & ${BookType.text} > 0 '
            'and type & ${BookType.local} = 0 '
            'and ($sumExpr) = 0 '
            'and (select show from $groupTable where groupId = ${VirtualBookGroup.idNetNone}) != 1';
      case VirtualBookGroup.idAll:
        // BookDao.kt:47 flowAll（无 where，占位恒真）
        return '1 = 1';
      case VirtualBookGroup.idLocal:
        return 'type & ${BookType.local} > 0';
      case VirtualBookGroup.idAudio:
        return 'type & ${BookType.audio} > 0';
      case VirtualBookGroup.idNetNone:
        // BookDao.kt:59-65
        return 'type & ${BookType.audio} = 0 '
            'and type & ${BookType.local} = 0 '
            'and type & ${BookType.video} = 0 '
            'and ($sumExpr) = 0';
      case VirtualBookGroup.idLocalNone:
        return 'type & ${BookType.local} > 0 and ($sumExpr) = 0';
      case VirtualBookGroup.idVideo:
        return 'type & ${BookType.video} > 0';
      case VirtualBookGroup.idError:
        return 'type & ${BookType.updateError} > 0';
      default:
        // BookDao.kt:75 flowByUserGroup
        return '($groupColumn & $groupId) > 0';
    }
  }

  /// 生成完整查询语句；flowAll / flowUpdateError 带 `order by durChapterTime desc`。
  static String buildFlowByGroupSql(
    int groupId, {
    String groupColumn = '`group`',
    String groupTable = 'book_groups',
  }) {
    final String where = buildFlowByGroupWhere(
      groupId,
      groupColumn: groupColumn,
      groupTable: groupTable,
    );
    final String orderBy =
        (groupId == VirtualBookGroup.idAll ||
                groupId == VirtualBookGroup.idError)
            ? ' order by durChapterTime desc'
            : '';
    return 'select * from books where $where$orderBy';
  }

  /// 与 [buildFlowByGroupWhere] 完全等价的 Dart 层判定。
  /// [typeFlags]：位标志类型；[groupBits]：书籍 group 位掩码；
  /// [userGroupsSum]：`sum(groupId) where groupId > 0`；
  /// [netNoneShow]：IdNetNone 分组的 show 值。
  ///
  /// 注：flowRoot 的 `netNoneShow != 1` 是上游原文（看似反直觉，逐字照抄）。
  static bool matchesGroup({
    required int typeFlags,
    required int groupBits,
    required int groupId,
    required int userGroupsSum,
    required int netNoneShow,
  }) {
    switch (groupId) {
      case VirtualBookGroup.idRoot:
        return BookType.hasFlag(typeFlags, BookType.text) &&
            BookType.notFlag(typeFlags, BookType.local) &&
            (userGroupsSum & groupBits) == 0 &&
            netNoneShow != 1;
      case VirtualBookGroup.idAll:
        return true;
      case VirtualBookGroup.idLocal:
        return BookType.hasFlag(typeFlags, BookType.local);
      case VirtualBookGroup.idAudio:
        return BookType.hasFlag(typeFlags, BookType.audio);
      case VirtualBookGroup.idNetNone:
        return BookType.notFlag(typeFlags, BookType.audio) &&
            BookType.notFlag(typeFlags, BookType.local) &&
            BookType.notFlag(typeFlags, BookType.video) &&
            (userGroupsSum & groupBits) == 0;
      case VirtualBookGroup.idLocalNone:
        return BookType.hasFlag(typeFlags, BookType.local) &&
            (userGroupsSum & groupBits) == 0;
      case VirtualBookGroup.idVideo:
        return BookType.hasFlag(typeFlags, BookType.video);
      case VirtualBookGroup.idError:
        return BookType.hasFlag(typeFlags, BookType.updateError);
      default:
        return (groupBits & groupId) > 0;
    }
  }

  /// 把本项目 `Book.type`（顺序枚举）投影成位标志，供 [matchesGroup] 使用。
  static int projectFlutterType(int enumType, {String? origin, bool local = false}) =>
      BookType.fromFlutterEnum(enumType, origin: origin, isLocal: local);
}

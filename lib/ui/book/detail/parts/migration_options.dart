/// 由 change_source_screen.dart 按「一类一文件」拆出的 _MigrationOptions。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../change_source_screen.dart';



/// 换源迁移选项（fork F21）：进度 / 章内位置 / 书签 / 高亮分别可选。
class _MigrationOptions {
  _MigrationOptions({required this.keepProgress});

  bool keepProgress;
  bool keepPagePos = true;
  bool migrateBookmarks = true;
  bool migrateHighlights = true;
}

Future<_MigrationOptions?> _showSourceMigrationSheet(
  BuildContext context, {
  required String bookName,
  required String sourceName,
  required String? matchedTitle,
  required bool hasMatch,
  required int bookmarkCount,
  required int highlightCount,
}) {
  return showModalBottomSheet<_MigrationOptions>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MigrationSheet(
      bookName: bookName,
      sourceName: sourceName,
      matchedTitle: matchedTitle,
      hasMatch: hasMatch,
      bookmarkCount: bookmarkCount,
      highlightCount: highlightCount,
    ),
  );
}

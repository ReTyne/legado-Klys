/// 由 change_source_screen.dart 按「一类一文件」拆出的 _MigrationSheet。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../change_source_screen.dart';


class _MigrationSheet extends StatefulWidget {
  const _MigrationSheet({
    required this.bookName,
    required this.sourceName,
    required this.matchedTitle,
    required this.hasMatch,
    required this.bookmarkCount,
    required this.highlightCount,
  });

  final String bookName;
  final String sourceName;
  final String? matchedTitle;
  final bool hasMatch;
  final int bookmarkCount;
  final int highlightCount;

  @override
  State<_MigrationSheet> createState() => _MigrationSheetState();
}

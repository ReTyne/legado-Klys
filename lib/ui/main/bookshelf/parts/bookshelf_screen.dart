/// 由 bookshelf_screen.dart 按「一类一文件」拆出的 BookshelfScreen。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../bookshelf_screen.dart';


class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

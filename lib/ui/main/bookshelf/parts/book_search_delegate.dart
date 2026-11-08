/// 由 bookshelf_manage_screen.dart 按「一类一文件」拆出的 _BookSearchDelegate。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../bookshelf_manage_screen.dart';


/// 书架管理内搜索（对齐 E BookshelfManageActivity 的 SearchView）
class _BookSearchDelegate extends SearchDelegate<String> {
  final List<Book> books;
  _BookSearchDelegate(this.books);

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
            icon: const Icon(Icons.clear_outlined),
            tooltip: '清空',
            onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final q = query.toLowerCase();
    final result = q.isEmpty
        ? books
        : books
            .where((b) =>
                b.name.toLowerCase().contains(q) ||
                b.author.toLowerCase().contains(q))
            .toList();
    return ListView.builder(
      itemCount: result.length,
      itemBuilder: (context, i) {
        final b = result[i];
        return ListTile(
          title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(b.author, maxLines: 1),
          onTap: () => close(context, b.name),
        );
      },
    );
  }
}

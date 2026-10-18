import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/rss_star.dart';
import 'package:legado_md3/data/local/app_database.dart';

class RssStarScreen extends StatefulWidget {
  const RssStarScreen({super.key});

  @override
  State<RssStarScreen> createState() => _RssStarScreenState();
}

class _RssStarScreenState extends State<RssStarScreen> {
  final DatabaseService _db = DatabaseService();
  List<RssStar> _stars = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStars();
  }

  Future<void> _loadStars() async {
    final stars = await _db.getRssStars();
    setState(() {
      _stars = stars;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RSS收藏')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stars.isEmpty
              ? const Center(child: Text('暂无收藏'))
              : ListView.builder(
                  itemCount: _stars.length,
                  itemBuilder: (context, index) {
                    final star = _stars[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(star.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: star.desc != null ? Text(star.desc!, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async {
                          if (star.id != null) {
                            await _db.deleteRssStar(star.id!);
                            _loadStars();
                          }
                        }),
                        onTap: () => _showDetail(star),
                      ),
                    );
                  },
                ),
    );
  }

  void _showDetail(RssStar star) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text(star.title),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (star.desc != null) Text(star.desc!),
        if (star.content != null) ...[const SizedBox(height: 8), Text(star.content!)],
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }
}

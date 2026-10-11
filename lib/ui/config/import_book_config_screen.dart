import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 导入书籍配置，对齐原版 importBookConfig/ImportBookConfig
class ImportBookConfigScreen extends StatefulWidget {
  const ImportBookConfigScreen({super.key});

  @override
  State<ImportBookConfigScreen> createState() => _ImportBookConfigScreenState();
}

class _ImportBookConfigScreenState extends State<ImportBookConfigScreen> {
  String _path = '';
  String _fileNameTpl = '';
  int _sort = 0;
  static const _sorts = ['默认', '按文件名', '按修改时间', '按大小'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _path = p.getString('import_path') ?? 'Legado/books';
      _fileNameTpl = p.getString('import_nameTpl') ?? '{name} - {author}';
      _sort = p.getInt('import_sort') ?? 0;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('import_path', _path);
    await p.setString('import_nameTpl', _fileNameTpl);
    await p.setInt('import_sort', _sort);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入书籍配置'), actions: [
        TextButton(onPressed: () { _save(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存'))); }, child: const Text('保存')),
      ]),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('默认导入路径'),
          subtitle: Text(_path, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.edit, size: 18),
          onTap: () async {
            final ctl = TextEditingController(text: _path);
            final v = await showDialog<String>(context: context, builder: (c) => AlertDialog(
              title: const Text('导入路径'),
              content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '相对路径')),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('确定'))],
            ));
            if (v != null) setState(() => _path = v);
          },
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_rename_outline),
          title: const Text('导入文件名规则'),
          subtitle: const Text('可用变量：{name} 书名、{author} 作者、{index} 序号', style: TextStyle(fontSize: 11)),
          trailing: Text(_fileNameTpl, style: const TextStyle(fontSize: 12)),
          onTap: () async {
            final ctl = TextEditingController(text: _fileNameTpl);
            final v = await showDialog<String>(context: context, builder: (c) => AlertDialog(
              title: const Text('文件名规则'),
              content: TextField(controller: ctl),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('确定'))],
            ));
            if (v != null && v.isNotEmpty) setState(() => _fileNameTpl = v);
          },
        ),
        ListTile(
          leading: const Icon(Icons.sort),
          title: const Text('本地导入排序'),
          trailing: DropdownButton<int>(
            value: _sort, underline: const SizedBox(),
            items: List.generate(_sorts.length, (i) => DropdownMenuItem(value: i, child: Text(_sorts[i]))),
            onChanged: (v) => setState(() => _sort = v ?? 0),
          ),
        ),
        const Padding(padding: EdgeInsets.all(16), child: Text(
          '说明：远程书籍服务器在「本地导入 → 远程书籍」中配置 WebDAV；导入的 TXT/EPUB 会按文件名规则保存到默认导入路径。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        )),
      ]),
    );
  }
}

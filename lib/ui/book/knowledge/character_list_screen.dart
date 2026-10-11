import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_knowledge.dart';
import 'package:legado_md3/ui/book/knowledge/character_detail_screen.dart';

class BookCharacter {
  final String name;
  final String? avatar;
  final String? description;
  final String? gender;
  final List<String>? relations;
  final List<String>? quotes;
  final int? color;

  BookCharacter({required this.name, this.avatar, this.description, this.gender, this.relations, this.quotes, this.color});

  factory BookCharacter.fromJson(Map<String, dynamic> json) => BookCharacter(
    name: json['name'] ?? '',
    avatar: json['avatar'],
    description: json['description'],
    gender: json['gender'],
    relations: json['relations'] != null ? List<String>.from(json['relations']) : null,
    quotes: json['quotes'] != null ? List<String>.from(json['quotes']) : null,
    color: json['color'],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'avatar': avatar,
    'description': description,
    'gender': gender,
    'relations': relations,
    'quotes': quotes,
    'color': color,
  };
}

class CharacterListScreen extends StatefulWidget {
  final Book book;
  const CharacterListScreen({super.key, required this.book});

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<BookCharacter> _characters = [];
  final Map<String, int> _idMap = {};
  final DatabaseService _db = DatabaseService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCharacters();
  }

  Future<void> _loadCharacters() async {
    final list = await _db.getBookKnowledge(widget.book.name, widget.book.author, type: 'character');
    setState(() {
      _characters.clear();
      _idMap.clear();
      for (final k in list) {
        try {
          final ch = BookCharacter.fromJson(jsonDecode(k.content ?? '{}'));
          _characters.add(ch);
          _idMap[ch.name] = k.id ?? 0;
        } catch (_) {
          _characters.add(BookCharacter(name: k.name, description: k.content));
          _idMap[k.name] = k.id ?? 0;
        }
      }
      _loading = false;
    });
  }

  Future<void> _addCharacter() async {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    String gender = '男';
    final colors = [0xFF6750A4, 0xFFE91E63, 0xFF0F9D58, 0xFFF44336, 0xFF03A9F4, 0xFFFF9800];
    int color = colors[0];
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (d, setD) => AlertDialog(
      title: const Text('添加角色'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '角色名')),
        const SizedBox(height: 8),
        Row(children: [
          const Text('性别: '),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('男'), selected: gender == '男', onSelected: (_) => setD(() => gender = '男')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('女'), selected: gender == '女', onSelected: (_) => setD(() => gender = '女')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: descCtl, maxLines: 3, decoration: const InputDecoration(labelText: '角色描述')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: colors.map((cl) => GestureDetector(
          onTap: () => setD(() => color = cl),
          child: CircleAvatar(radius: 14, backgroundColor: Color(cl), child: color == cl ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
        )).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('保存')),
      ],
    )));
    if (ok == true && nameCtl.text.trim().isNotEmpty) {
      final ch = BookCharacter(name: nameCtl.text.trim(), gender: gender, description: descCtl.text.trim(), color: color);
      final k = BookKnowledge(bookName: widget.book.name, author: widget.book.author, type: 'character', name: ch.name, content: jsonEncode(ch.toJson()), order: _characters.length);
      await _db.insertBookKnowledge(k);
      _loadCharacters();
    }
  }

  Future<void> _deleteCharacter(BookCharacter ch) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text('删除角色「${ch.name}」'), content: const Text('确定删除该角色吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除'))],
    ));
    if (ok == true) {
      final id = _idMap[ch.name];
      if (id != null) await _db.deleteBookKnowledge(id);
      _loadCharacters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.book.name} - 角色'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '角色列表'), Tab(text: '关系网')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCharacterList(), _buildCharacterNetwork()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCharacter,
        child: const Icon(Icons.person_add_alt),
      ),
    );
  }

  Widget _buildCharacterList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_characters.isEmpty) return const Center(child: Text('暂无角色信息'));
    return ListView.builder(
      itemCount: _characters.length,
      itemBuilder: (context, index) {
        final char = _characters[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(char.color ?? 0xFF6750A4),
            child: Text(char.name.isNotEmpty ? char.name[0] : '?', style: const TextStyle(color: Colors.white)),
          ),
          title: Text(char.name),
          subtitle: Text('${char.gender ?? ''} ${char.description ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterDetailScreen(character: char, bookName: widget.book.name))),
          onLongPress: () => _deleteCharacter(char),
        );
      },
    );
  }

  Widget _buildCharacterNetwork() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_characters.isEmpty) return const Center(child: Text('暂无角色关系'));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _characters.map((char) => Card(
          child: ExpansionTile(
            leading: CircleAvatar(backgroundColor: Color(char.color ?? 0xFF6750A4), child: Text(char.name[0], style: const TextStyle(color: Colors.white))),
            title: Text(char.name),
            subtitle: Text(char.description ?? ''),
            children: [
              if (char.relations != null) Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('关系:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: char.relations!.map((r) => Chip(label: Text(r))).toList()),
                ]),
              ),
              if (char.quotes != null) Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('名言:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...char.quotes!.map((q) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('"$q"', style: const TextStyle(fontStyle: FontStyle.italic)))),
                ]),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

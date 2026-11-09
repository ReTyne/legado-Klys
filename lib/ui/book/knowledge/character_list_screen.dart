import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/ui/book/knowledge/relation_graph_painter.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
part 'character_detail_screen.dart';


/// 一个角色（缺字段统一用 JSON 存在 `book_knowledge.content`）。
class BookCharacter {
  final String name;
  final String? avatar;
  final String? description;
  final String? gender;
  final List<String>? relations;
  final List<String>? quotes;
  final int? color;

  /// 关系网节点坐标（归一化 0~1），随 content JSON 持久化。
  double? posX;
  double? posY;

  BookCharacter({
    required this.name,
    this.avatar,
    this.description,
    this.gender,
    this.relations,
    this.quotes,
    this.color,
    this.posX,
    this.posY,
  });

  factory BookCharacter.fromJson(Map<String, dynamic> json) => BookCharacter(
        name: json['name'] ?? '',
        avatar: json['avatar'],
        description: json['description'],
        gender: json['gender'],
        relations: json['relations'] != null
            ? List<String>.from(json['relations'] as List)
            : null,
        quotes: json['quotes'] != null
            ? List<String>.from(json['quotes'] as List)
            : null,
        color: json['color'],
        posX: (json['posX'] as num?)?.toDouble(),
        posY: (json['posY'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatar': avatar,
        'description': description,
        'gender': gender,
        'relations': relations,
        'quotes': quotes,
        'color': color,
        if (posX != null) 'posX': posX,
        if (posY != null) 'posY': posY,
      };
}

/// 事件时间线条目（同样以 JSON 存在 `book_knowledge.content`，type='event'）。
class BookEvent {
  final String title;
  final String time;
  final String description;
  final String? related;

  BookEvent({
    required this.title,
    this.time = '',
    this.description = '',
    this.related,
  });

  factory BookEvent.fromJson(Map<String, dynamic> j) => BookEvent(
        title: j['title'] ?? '',
        time: j['time'] ?? '',
        description: j['description'] ?? '',
        related: j['related'],
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'time': time,
        'description': description,
        'related': related,
      };
}

class _StoredEvent {
  final int? id;
  final BookEvent event;
  const _StoredEvent(this.id, this.event);
}

/// 书籍知识图谱：角色列表 / 真关系网（CustomPainter + 拖拽 + 点击详情） / 事件时间线。
class CharacterListScreen extends StatefulWidget {
  final Book book;
  const CharacterListScreen({super.key, required this.book});

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<BookCharacter> _characters = [];
  final List<_StoredEvent> _events = [];
  final Map<String, int> _idMap = {};
  final DatabaseService _db = DatabaseService();
  List<GraphNode> _graphNodes = const [];
  bool _loading = true;
  String? _selectedNode;
  int _graphVersion = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadCharacters();
    _loadEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCharacters() async {
    final list = await _db.getBookKnowledge(
        widget.book.name, widget.book.author,
        type: 'character');
    final characters = <BookCharacter>[];
    _idMap.clear();
    for (final k in list) {
      try {
        final ch = BookCharacter.fromJson(
            Map<String, dynamic>.from(jsonDecode(k.content ?? '{}') as Map));
        characters.add(ch);
        _idMap[ch.name] = k.id ?? 0;
      } catch (_) {
        characters.add(BookCharacter(name: k.name, description: k.content));
        _idMap[k.name] = k.id ?? 0;
      }
    }
    _graphNodes = _buildGraphNodes(characters);
    if (!mounted) return;
    setState(() {
      _characters
        ..clear()
        ..addAll(characters);
      _loading = false;
    });
  }

  Future<void> _loadEvents() async {
    final list = await _db.getBookKnowledge(
        widget.book.name, widget.book.author,
        type: 'event');
    final out = <_StoredEvent>[];
    for (final k in list) {
      try {
        out.add(_StoredEvent(
            k.id,
            BookEvent.fromJson(
                Map<String, dynamic>.from(jsonDecode(k.content ?? '{}') as Map))));
      } catch (_) {
        out.add(_StoredEvent(k.id,
            BookEvent(title: k.name, description: k.content ?? '')));
      }
    }
    if (!mounted) return;
    setState(() {
      _events
        ..clear()
        ..addAll(out);
    });
  }

  List<GraphNode> _buildGraphNodes(List<BookCharacter> characters) {
    final nodes = <GraphNode>[];
    for (var i = 0; i < characters.length; i++) {
      final c = characters[i];
      final fallback = _circlePos(i, characters.length);
      nodes.add(GraphNode(
        id: c.name,
        label: c.name,
        avatar: c.avatar,
        color: c.color,
        position: (c.posX != null && c.posY != null)
            ? Offset(c.posX!, c.posY!)
            : fallback,
      ));
    }
    return nodes;
  }

  Offset _circlePos(int i, int n) {
    if (n <= 1) return const Offset(0.5, 0.5);
    final angle = 2 * math.pi * i / n - math.pi / 2;
    return Offset(0.5 + 0.32 * math.cos(angle), 0.5 + 0.32 * math.sin(angle));
  }

  /// 把 `relations`（"角色名|关系" 或 "关系:角色名"）解析成关系网边。
  List<GraphEdge> _buildEdges() {
    final names = _characters.map((c) => c.name).toSet();
    final edges = <GraphEdge>[];
    for (final c in _characters) {
      for (final raw in c.relations ?? const <String>[]) {
        String target = raw.trim();
        String label = '关联';
        if (raw.contains('|')) {
          final parts = raw.split('|');
          target = parts[0].trim();
          label = parts.length > 1 ? parts[1].trim() : label;
        } else if (raw.contains(':')) {
          final parts = raw.split(':');
          final a = parts[0].trim();
          final b = parts.length > 1 ? parts[1].trim() : '';
          if (names.contains(b) && !names.contains(a)) {
            target = b;
            label = a;
          } else {
            target = a;
            label = b.isEmpty ? label : b;
          }
        }
        if (target.isEmpty || target == c.name || !names.contains(target)) {
          continue;
        }
        // 无向关系去重
        final exists = edges.any((e) =>
            (e.from == c.name && e.to == target) ||
            (e.from == target && e.to == c.name));
        if (!exists) edges.add(GraphEdge(from: c.name, to: target, label: label));
      }
    }
    return edges;
  }

  Future<void> _saveNodePosition(String name, Offset pos) async {
    final id = _idMap[name];
    if (id == null) return;
    BookCharacter? ch;
    for (final c in _characters) {
      if (c.name == name) {
        ch = c;
        break;
      }
    }
    if (ch == null) return;
    ch.posX = pos.dx;
    ch.posY = pos.dy;
    try {
      final db = await _db.database;
      await db.update('book_knowledge', {'content': jsonEncode(ch.toJson())},
          where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> _addCharacter() async {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final avatarCtl = TextEditingController();
    final relCtl = TextEditingController();
    String gender = '男';
    const colors = [
      0xFF6750A4,
      0xFFE91E63,
      0xFF0F9D58,
      0xFFF44336,
      0xFF03A9F4,
      0xFFFF9800
    ];
    int color = colors[0];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setD) => AlertDialog(
        title: const Text('添加角色'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: '角色名')),
            const SizedBox(height: AppSpacing.s),
            Row(children: [
              const Text('性别: '),
              const SizedBox(width: AppSpacing.s),
              ChoiceChip(
                  label: const Text('男'),
                  selected: gender == '男',
                  onSelected: (_) => setD(() => gender = '男')),
              const SizedBox(width: AppSpacing.s),
              ChoiceChip(
                  label: const Text('女'),
                  selected: gender == '女',
                  onSelected: (_) => setD(() => gender = '女')),
            ]),
            TextField(
                controller: descCtl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '角色描述')),
            TextField(
                controller: avatarCtl,
                decoration: const InputDecoration(
                    labelText: '头像 URL（可选）', hintText: 'https://…')),
            TextField(
                controller: relCtl,
                decoration: const InputDecoration(
                    labelText: '关系（逗号分隔，如 李四|盟友）')),
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: 8,
              children: colors
                  .map((cl) => GestureDetector(
                        onTap: () => setD(() => color = cl),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(cl),
                          child: color == cl
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      ))
                  .toList(),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('保存')),
        ],
      )),
    );
    if (ok != true || nameCtl.text.trim().isEmpty) {
      return;
    }
    final relations = relCtl.text
        .split(RegExp('[,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final ch = BookCharacter(
      name: nameCtl.text.trim(),
      gender: gender,
      description: descCtl.text.trim(),
      avatar: avatarCtl.text.trim().isEmpty ? null : avatarCtl.text.trim(),
      relations: relations.isEmpty ? null : relations,
      color: color,
    );
    await _db.insertBookKnowledge(BookKnowledge(
      bookName: widget.book.name,
      author: widget.book.author,
      type: 'character',
      name: ch.name,
      content: jsonEncode(ch.toJson()),
      order: _characters.length,
    ));
    await _loadCharacters();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加角色「${ch.name}」')),
      );
    }
  }

  Future<void> _addEvent() async {
    final titleCtl = TextEditingController();
    final timeCtl = TextEditingController();
    final descCtl = TextEditingController();
    final relCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('添加事件'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: titleCtl,
                decoration: const InputDecoration(labelText: '事件标题')),
            TextField(
                controller: timeCtl,
                decoration: const InputDecoration(
                    labelText: '时间 / 章节', hintText: '第 3 章 / 2024 年')),
            TextField(
                controller: descCtl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '事件描述')),
            TextField(
                controller: relCtl,
                decoration: const InputDecoration(
                    labelText: '关联角色（可选）')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || titleCtl.text.trim().isEmpty) return;
    final ev = BookEvent(
      title: titleCtl.text.trim(),
      time: timeCtl.text.trim(),
      description: descCtl.text.trim(),
      related: relCtl.text.trim().isEmpty ? null : relCtl.text.trim(),
    );
    await _db.insertBookKnowledge(BookKnowledge(
      bookName: widget.book.name,
      author: widget.book.author,
      type: 'event',
      name: ev.title,
      content: jsonEncode(ev.toJson()),
      order: _events.length,
    ));
    await _loadEvents();
  }

  Future<void> _deleteCharacter(BookCharacter ch) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除角色「${ch.name}」',
      content: '确定删除该角色吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    final id = _idMap[ch.name];
    if (id != null) await _db.deleteBookKnowledge(id);
    await _loadCharacters();
  }

  Future<void> _deleteEvent(_StoredEvent e) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除事件「${e.event.title}」',
      content: '确定删除该事件吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    if (e.id != null) await _db.deleteBookKnowledge(e.id!);
    await _loadEvents();
  }

  void _showNodeDetail(String name) {
    BookCharacter? ch;
    for (final c in _characters) {
      if (c.name == name) {
        ch = c;
        break;
      }
    }
    if (ch == null) return;
    final BookCharacter selected = ch;
    setState(() => _selectedNode = name);
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              _avatar(selected, radius: 28),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                  child: Text(selected.name,
                      style: Theme.of(context).textTheme.titleLarge)),
            ]),
            const SizedBox(height: AppSpacing.m),
            if (selected.description != null &&
                selected.description!.isNotEmpty)
              Text(selected.description!),
            if (selected.relations != null &&
                selected.relations!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.m),
              Wrap(
                spacing: 8,
                children: selected.relations!
                    .map((r) => Chip(label: Text(r)))
                    .toList(),
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CharacterDetailScreen(
                      character: selected,
                      bookName: widget.book.name,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.person_outline),
              label: const Text('查看详情'),
            ),
          ]),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selectedNode = null);
    });
  }

  Widget _avatar(BookCharacter ch, {double radius = 20}) {
    final cs = Theme.of(context).colorScheme;
    final bg = Color(ch.color ?? cs.primary.value);
    final url = ch.avatar;
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage:
          (url != null && url.startsWith('http')) ? NetworkImage(url) : null,
      child: (url == null || !url.startsWith('http'))
          ? Text(ch.name.isNotEmpty ? ch.name[0] : '?',
              style: const TextStyle(color: Colors.white))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.book.name} - 知识图谱'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '角色列表'),
            Tab(text: '关系网'),
            Tab(text: '事件时间线'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCharacterList(), _buildNetwork(), _buildTimeline()],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: _tabController.index == 2 ? '添加事件' : '添加角色',
        onPressed:
            _tabController.index == 2 ? _addEvent : _addCharacter,
        child: Icon(_tabController.index == 2
            ? Icons.event_outlined
            : Icons.person_add_alt_outlined),
      ),
    );
  }

  Widget _buildCharacterList() {
    if (_loading) return const AppLoadingIndicator();
    if (_characters.isEmpty) {
      return const AppEmptyState(
          icon: Icons.people_outline, title: '暂无角色信息');
    }
    return ListView.builder(
      itemCount: _characters.length,
      itemBuilder: (context, index) {
        final char = _characters[index];
        return ListTile(
          leading: _avatar(char),
          title: Text(char.name),
          subtitle: Text('${char.gender ?? ''} ${char.description ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showNodeDetail(char.name),
          onLongPress: () => _deleteCharacter(char),
        );
      },
    );
  }

  Widget _buildNetwork() {
    if (_loading) return const AppLoadingIndicator();
    if (_characters.isEmpty) {
      return const AppEmptyState(
          icon: Icons.account_tree_outlined,
          title: '暂无角色关系',
          message: '添加角色并填写「关系」后即可看到关系网');
    }
    final cs = Theme.of(context).colorScheme;
    final edges = _buildEdges();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
          child: Text('拖拽节点调整布局（自动保存）· 点击节点查看详情 · 共 ${edges.length} 条关系',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, cons) {
            final w = cons.maxWidth;
            final h = cons.maxHeight;
            const r = RelationGraphPainter.nodeRadius;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: RelationGraphPainter(
                      nodes: _graphNodes,
                      edges: edges,
                      colorScheme: cs,
                      selectedId: _selectedNode,
                      version: _graphVersion,
                    ),
                  ),
                ),
                for (var i = 0; i < _graphNodes.length; i++)
                  _buildDraggableNode(_graphNodes[i], i, w, h, r),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDraggableNode(
      GraphNode node, int index, double w, double h, double r) {
    final ch = index < _characters.length ? _characters[index] : null;
    return Positioned(
      left: (node.position.dx * w - r - 3).clamp(0.0, (w - 2 * r - 6).clamp(0.0, w)),
      top: (node.position.dy * h - r - 3).clamp(0.0, (h - 2 * r - 6).clamp(0.0, h)),
      width: 2 * r + 6,
      height: 2 * r + 6,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            node.position = Offset(
              (node.position.dx + d.delta.dx / w).clamp(0.05, 0.95),
              (node.position.dy + d.delta.dy / h).clamp(0.05, 0.95),
            );
            _graphVersion++;
          });
        },
        onPanEnd: (_) =>
            unawaited(_saveNodePosition(node.id, node.position)),
        onTap: () => _showNodeDetail(node.id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ch != null
                ? _avatar(ch, radius: r)
                : CircleAvatar(
                    radius: r,
                    child: Text(node.label.isNotEmpty ? node.label[0] : '?')),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    if (_events.isEmpty) {
      return const AppEmptyState(
          icon: Icons.timeline_outlined,
          title: '暂无事件',
          message: '点右下角添加事件，构成故事时间线');
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.l),
      itemCount: _events.length,
      itemBuilder: (context, i) {
        final e = _events[i].event;
        return InkWell(
          onLongPress: () => _deleteEvent(_events[i]),
          borderRadius: AppRadius.mAll,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (i < _events.length - 1)
                    Container(width: 2, height: 56, color: cs.outlineVariant),
                ],
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.m),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (e.time.isNotEmpty)
                            Text(e.time,
                                style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(
                              child: Text(e.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                        ]),
                        if (e.description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(e.description,
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13)),
                        ],
                        if (e.related != null && e.related!.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Chip(
                              label: Text(e.related!),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


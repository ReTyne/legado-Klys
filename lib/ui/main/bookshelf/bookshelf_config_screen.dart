import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../di/book_provider.dart';

/// 书架配置页面 - 对齐原版BookshelfConfigSheet
class BookshelfConfigScreen extends StatefulWidget {
  const BookshelfConfigScreen({super.key});

  @override
  State<BookshelfConfigScreen> createState() => _BookshelfConfigScreenState();
}

class _BookshelfConfigScreenState extends State<BookshelfConfigScreen> {
  // 分组
  int _groupStyle = 0; // 0: 折叠 1: 平铺
  bool _hideEmptyGroups = false;
  // 排序
  int _sortType = 0; // 0: 最近阅读 1: 书名 2: 作者 3: 添加时间 4: 手动
  bool _sortAscending = false;
  // 布局: 0详细列表 1紧凑列表 2三列网格 3四列紧凑网格 4大封面
  int _layout = 0;
  int _columnCount = 3;
  double _coverWidth = 100;
  bool _compactTitle = false;
  bool _centerTitle = false;
  bool _showDivider = false;
  // 详情
  bool _compactDetails = false;
  bool _showLatestChapter = true;
  bool _showSynopsis = false;
  int _synopsisLines = 2;
  bool _showTags = false;
  int _maxTitleLines = 2;
  bool _coverShadow = true;
  // 角标
  bool _showUnread = false;
  bool _showUnreadNew = true;
  bool _showWaitUpdateCount = false;
  bool _showBookCount = true;
  bool _showLastUpdateTime = false;
  // 其他
  bool _searchFilterFirst = false;
  bool _showFastScroller = true;
  bool _showTabMenu = true;
  int _updateLimit = 0;

  static const _sortNames = ['最近阅读', '书名', '作者', '添加时间', '手动排序'];
  static const _groupStyleNames = ['折叠分组(顶部标签)', '平铺分组(分区展示)'];
  static const _layoutNames = ['详细列表', '紧凑列表', '三列网格', '紧凑网格', '大封面'];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _groupStyle = prefs.getInt('bs_groupStyle') ?? 0;
      _hideEmptyGroups = prefs.getBool('bs_hideEmptyGroups') ?? false;
      _sortType = prefs.getInt('bs_sortType') ?? 0;
      _sortAscending = prefs.getBool('bs_sortAscending') ?? false;
      // 新布局字段优先；兼容旧的 layoutMode/gridStyle
      final savedLayout = prefs.getInt('bs_layout');
      if (savedLayout != null) {
        _layout = savedLayout;
      } else {
        final mode = prefs.getInt('bs_layoutMode') ?? 0;
        _layout = mode == 1 ? ((prefs.getInt('bs_gridStyle') ?? 0) == 1 ? 3 : 2) : 0;
      }
      _columnCount = prefs.getInt('bs_columnCount') ?? 3;
      _coverWidth = prefs.getDouble('bs_coverWidth') ?? 100;
      _compactTitle = prefs.getBool('bs_compactTitle') ?? false;
      _centerTitle = prefs.getBool('bs_centerTitle') ?? false;
      _showDivider = prefs.getBool('bs_showDivider') ?? false;
      _compactDetails = prefs.getBool('bs_compactDetails') ?? false;
      _showLatestChapter = prefs.getBool('bs_showLatestChapter') ?? true;
      _showSynopsis = prefs.getBool('bs_showSynopsis') ?? false;
      _synopsisLines = prefs.getInt('bs_synopsisLines') ?? 2;
      _showTags = prefs.getBool('bs_showTags') ?? false;
      _maxTitleLines = prefs.getInt('bs_maxTitleLines') ?? 2;
      _coverShadow = prefs.getBool('bs_coverShadow') ?? true;
      _showUnread = prefs.getBool('bs_showUnread') ?? false;
      _showUnreadNew = prefs.getBool('bs_showUnreadNew') ?? true;
      _showWaitUpdateCount = prefs.getBool('bs_showWaitUpdateCount') ?? false;
      _showBookCount = prefs.getBool('bs_showBookCount') ?? true;
      _showLastUpdateTime = prefs.getBool('bs_showLastUpdateTime') ?? false;
      _searchFilterFirst = prefs.getBool('bs_searchFilterFirst') ?? false;
      _showFastScroller = prefs.getBool('bs_showFastScroller') ?? true;
      _showTabMenu = prefs.getBool('bs_showTabMenu') ?? true;
      _updateLimit = prefs.getInt('bs_updateLimit') ?? 0;
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
  );

  Widget _switchTile(String title, bool value, ValueChanged<bool> onChanged, {String? desc}) {
    return SwitchListTile(
      dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: desc != null ? Text(desc, style: const TextStyle(fontSize: 11)) : null,
      value: value, onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('书架配置')),
      body: ListView(children: [
        // 布局模式
        _sectionTitle('书架布局'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _layoutNames.length; i++)
              ChoiceChip(
                label: Text(_layoutNames[i]),
                selected: _layout == i,
                onSelected: (_) {
                  setState(() => _layout = i);
                  _save('bs_layout', i);
                  Provider.of<BookProvider>(context, listen: false)
                      .setBookshelfLayout(i);
                },
              ),
          ]),
        ),
        const SizedBox(height: 8),
        if (_layout >= 2) ...[
          ListTile(
            dense: true, title: Text('网格列数: $_columnCount'),
            subtitle: Slider(value: _columnCount.toDouble(), min: 2, max: 8, divisions: 6,
              label: '$_columnCount',
              onChanged: (v) => setState(() => _columnCount = v.toInt()),
              onChangeEnd: (v) => _save('bs_columnCount', v.toInt())),
          ),
          _switchTile('紧凑标题字体', _compactTitle, (v) { setState(() => _compactTitle = v); _save('bs_compactTitle', v); }),
          _switchTile('居中标题', _centerTitle, (v) { setState(() => _centerTitle = v); _save('bs_centerTitle', v); }),
        ] else ...[
          ListTile(
            dense: true, title: Text('列表封面宽度: ${_coverWidth.toInt()}'),
            subtitle: Slider(value: _coverWidth, min: 60, max: 200, divisions: 28,
              label: '${_coverWidth.toInt()}',
              onChanged: (v) => setState(() => _coverWidth = v),
              onChangeEnd: (v) => _save('bs_coverWidth', v)),
          ),
          _switchTile('紧凑详情', _compactDetails, (v) { setState(() => _compactDetails = v); _save('bs_compactDetails', v); }),
        ],
        _switchTile('显示分割线', _showDivider, (v) { setState(() => _showDivider = v); _save('bs_showDivider', v); }),

        // 分组
        _sectionTitle('分组'),
        ListTile(
          dense: true, title: const Text('分组样式'),
          trailing: DropdownButton<int>(
            value: _groupStyle, underline: const SizedBox(),
            items: List.generate(_groupStyleNames.length, (i) => DropdownMenuItem(value: i, child: Text(_groupStyleNames[i]))),
            onChanged: (v) { setState(() => _groupStyle = v ?? 0); _save('bs_groupStyle', v ?? 0); },
          ),
        ),
        _switchTile('隐藏空分组', _hideEmptyGroups, (v) { setState(() => _hideEmptyGroups = v); _save('bs_hideEmptyGroups', v); }),

        // 排序
        _sectionTitle('排序'),
        ListTile(
          dense: true, title: const Text('排序方式'),
          trailing: DropdownButton<int>(
            value: _sortType, underline: const SizedBox(),
            items: List.generate(_sortNames.length, (i) => DropdownMenuItem(value: i, child: Text(_sortNames[i]))),
            onChanged: (v) { setState(() => _sortType = v ?? 0); _save('bs_sortType', v ?? 0); },
          ),
        ),
        _switchTile('升序排列', _sortAscending, (v) { setState(() => _sortAscending = v); _save('bs_sortAscending', v); }, desc: '关闭则为降序'),

        // 显示信息
        _sectionTitle('显示信息'),
        ListTile(
          dense: true, title: Text('最大标题行数: $_maxTitleLines'),
          subtitle: Slider(value: _maxTitleLines.toDouble(), min: 1, max: 5, divisions: 4,
            label: '$_maxTitleLines',
            onChanged: (v) => setState(() => _maxTitleLines = v.toInt()),
            onChangeEnd: (v) => _save('bs_maxTitleLines', v.toInt())),
        ),
        _switchTile('封面阴影', _coverShadow, (v) { setState(() => _coverShadow = v); _save('bs_coverShadow', v); }),
        _switchTile('显示最新章节', _showLatestChapter, (v) { setState(() => _showLatestChapter = v); _save('bs_showLatestChapter', v); }),
        _switchTile('显示简介', _showSynopsis, (v) { setState(() => _showSynopsis = v); _save('bs_showSynopsis', v); }),
        if (_showSynopsis) ListTile(
          dense: true, title: Text('简介行数: $_synopsisLines'),
          subtitle: Slider(value: _synopsisLines.toDouble(), min: 1, max: 10, divisions: 9,
            label: '$_synopsisLines',
            onChanged: (v) => setState(() => _synopsisLines = v.toInt()),
            onChangeEnd: (v) => _save('bs_synopsisLines', v.toInt())),
        ),
        _switchTile('显示标签', _showTags, (v) { setState(() => _showTags = v); _save('bs_showTags', v); }),

        // 角标
        _sectionTitle('角标'),
        _switchTile('显示未读', _showUnread, (v) { setState(() => _showUnread = v); _save('bs_showUnread', v); }),
        _switchTile('显示未读(新)', _showUnreadNew, (v) { setState(() => _showUnreadNew = v); _save('bs_showUnreadNew', v); }),
        _switchTile('显示待更新数量', _showWaitUpdateCount, (v) { setState(() => _showWaitUpdateCount = v); _save('bs_showWaitUpdateCount', v); }),
        _switchTile('显示书籍数量', _showBookCount, (v) { setState(() => _showBookCount = v); _save('bs_showBookCount', v); }),
        _switchTile('显示最后更新时间', _showLastUpdateTime, (v) { setState(() => _showLastUpdateTime = v); _save('bs_showLastUpdateTime', v); }),

        // 其他
        _sectionTitle('其他'),
        _switchTile('搜索优先过滤', _searchFilterFirst, (v) { setState(() => _searchFilterFirst = v); _save('bs_searchFilterFirst', v); }),
        _switchTile('显示快速滚动条', _showFastScroller, (v) { setState(() => _showFastScroller = v); _save('bs_showFastScroller', v); }),
        _switchTile('显示Tab菜单', _showTabMenu, (v) { setState(() => _showTabMenu = v); _save('bs_showTabMenu', v); }),
        ListTile(
          dense: true, title: Text('更新限制: ${_updateLimit == 0 ? '无限制' : '$_updateLimit 本'}'),
          subtitle: Slider(value: _updateLimit.toDouble(), min: 0, max: 20, divisions: 20,
            label: _updateLimit == 0 ? '无限制' : '$_updateLimit',
            onChanged: (v) => setState(() => _updateLimit = v.toInt()),
            onChangeEnd: (v) => _save('bs_updateLimit', v.toInt())),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}


import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/common/deep_link_service.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/source/check_source_service.dart';
import 'package:legado_md3/ui/book/import/online_import_screen.dart';
import 'package:legado_md3/ui/book/source/source_debug_screen.dart';
import 'package:legado_md3/ui/book/source/source_edit_screen.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';
import 'package:legado_md3/ui/book/source/qr_share_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
part 'qr_scanner_screen.dart';


/// 书源导入高级选项（对齐 legado-E `res/menu/import_source.xml` 的 7 项菜单：
/// menu_new_group / menu_select_new_source / menu_select_update_source /
/// menu_keep_original_name / menu_keep_group / menu_keep_enable / menu_show_comment）。
/// 另保留 1 项扩展「导入时自动替换同名」（官方原版能力）。
/// 早期注释所称「12 项菜单」是官方原版口径，不适用于 Sigma 基准。
///
/// 每一项都真实参与 [_SourceManageScreenState._importSourcesFromData] 的落库或渲染：
/// - [keepOriginalName] / [keepGroup] / [keepEnabled]：更新同名 URL 书源时保留本地字段；
/// - [selectNewSource] / [selectUpdateSource]：控制新增 / 已存在书源是否落库；
/// - [newGroup] / [addGroup]：menu_new_group，导入时统一分组（整体替换或追加）；
/// - [showComment]：menu_show_comment，书源列表显示备注；
/// - [autoReplaceSameName]：存在同名但不同 URL 的旧源时先删除再导入。
/// 全部持久化到 SharedPreferences，默认值保持「全量导入」的原有行为。
class SourceImportOptions {
  const SourceImportOptions({
    this.keepOriginalName = false,
    this.keepGroup = false,
    this.keepEnabled = false,
    this.selectNewSource = true,
    this.selectUpdateSource = true,
    this.autoReplaceSameName = false,
    this.showComment = false,
    this.newGroup = '',
    this.addGroup = false,
  });

  final bool keepOriginalName;
  final bool keepGroup;
  final bool keepEnabled;
  final bool selectNewSource;
  final bool selectUpdateSource;
  final bool autoReplaceSameName;
  final bool showComment;
  final String newGroup;
  final bool addGroup;

  static const String _keyPrefix = 'source_import_opt_';

  static Future<SourceImportOptions> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SourceImportOptions(
      keepOriginalName: prefs.getBool('${_keyPrefix}keep_original_name') ?? false,
      keepGroup: prefs.getBool('${_keyPrefix}keep_group') ?? false,
      keepEnabled: prefs.getBool('${_keyPrefix}keep_enabled') ?? false,
      selectNewSource: prefs.getBool('${_keyPrefix}select_new_source') ?? true,
      selectUpdateSource: prefs.getBool('${_keyPrefix}select_update_source') ?? true,
      autoReplaceSameName: prefs.getBool('${_keyPrefix}auto_replace_same_name') ?? false,
      showComment: prefs.getBool('${_keyPrefix}show_comment') ?? false,
      newGroup: prefs.getString('${_keyPrefix}new_group') ?? '',
      addGroup: prefs.getBool('${_keyPrefix}add_group') ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_keyPrefix}keep_original_name', keepOriginalName);
    await prefs.setBool('${_keyPrefix}keep_group', keepGroup);
    await prefs.setBool('${_keyPrefix}keep_enabled', keepEnabled);
    await prefs.setBool('${_keyPrefix}select_new_source', selectNewSource);
    await prefs.setBool('${_keyPrefix}select_update_source', selectUpdateSource);
    await prefs.setBool('${_keyPrefix}auto_replace_same_name', autoReplaceSameName);
    await prefs.setBool('${_keyPrefix}show_comment', showComment);
    await prefs.setString('${_keyPrefix}new_group', newGroup);
    await prefs.setBool('${_keyPrefix}add_group', addGroup);
  }
}

class SourceManageScreen extends StatefulWidget {
  const SourceManageScreen({super.key});

  @override
  State<SourceManageScreen> createState() => _SourceManageScreenState();
}

class _SourceManageScreenState extends State<SourceManageScreen> {
  final DatabaseService _db = DatabaseService();
  final CheckSourceService _checkService = CheckSourceService();
  List<BookSource> _sources = [];
  bool _isLoading = true;
  final String _searchQuery = '';
  String? _selectedGroup;
  // 对齐 E BookSourceActivity.upBookSource 的特殊分组过滤
  // （need_login / 未分组 / 已启用 / 未启用 / 已启用发现）
  String? _specialFilter;
  int _sortBy = 0; // 0=手动 1=权重 2=名称 3=URL 4=更新时间 5=响应时间 6=启用
  bool _sortAsc = true;
  bool _selectMode = false;
  bool _groupByDomain = false;
  /// menu_show_comment：书源列表是否显示备注（由导入选项持久化）。
  bool _showComment = false;
  final Set<String> _selectedIds = {};
  List<String> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadSources();
    _loadShowComment();
  }

  Future<void> _loadShowComment() async {
    final options = await SourceImportOptions.load();
    if (mounted) setState(() => _showComment = options.showComment);
  }

  @override
  void dispose() {
    _checkService.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    setState(() => _isLoading = true);
    _sources = await _db.getAllSources();
    _groups = _sources
        .map((s) => s.bookSourceGroup)
        .whereType<String>().where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (mounted) setState(() => _isLoading = false);
  }

  List<BookSource> get _filteredSources {
    var result = _sources;
    // 对齐 E upBookSource(searchKey)：need_login 等特殊过滤
    switch (_specialFilter) {
      case 'need_login':
        result = result
            .where((s) => (s.loginUrl ?? '').trim().isNotEmpty)
            .toList();
        break;
      case 'no_group':
        result = result
            .where((s) => (s.bookSourceGroup ?? '').trim().isEmpty)
            .toList();
        break;
      case 'enabled':
        result = result.where((s) => s.enabled).toList();
        break;
      case 'disabled':
        result = result.where((s) => !s.enabled).toList();
        break;
      case 'enabled_explore':
        result = result.where((s) => s.enabledExplore).toList();
        break;
    }
    if (_selectedGroup != null) {
      result = result.where((s) => s.bookSourceGroup == _selectedGroup).toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result
          .where((s) =>
              s.bookSourceName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              s.bookSourceUrl.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    // 排序
    result = List.from(result);
    switch (_sortBy) {
      case 1: result.sort((a, b) => _sortAsc ? a.weight.compareTo(b.weight) : b.weight.compareTo(a.weight)); break;
      case 2: result.sort((a, b) => _sortAsc ? a.bookSourceName.compareTo(b.bookSourceName) : b.bookSourceName.compareTo(a.bookSourceName)); break;
      case 3: result.sort((a, b) => _sortAsc ? a.bookSourceUrl.compareTo(b.bookSourceUrl) : b.bookSourceUrl.compareTo(a.bookSourceUrl)); break;
      case 4: result.sort((a, b) => _sortAsc ? (a.lastUpdateTime ?? 0).compareTo(b.lastUpdateTime ?? 0) : (b.lastUpdateTime ?? 0).compareTo(a.lastUpdateTime ?? 0)); break;
      case 5: result.sort((a, b) => _sortAsc ? (a.respondTime ?? 0).compareTo(b.respondTime ?? 0) : (b.respondTime ?? 0).compareTo(a.respondTime ?? 0)); break;
      case 6: result.sort((a, b) => _sortAsc ? (a.enabled ? 0 : 1).compareTo(b.enabled ? 0 : 1) : (b.enabled ? 0 : 1).compareTo(a.enabled ? 0 : 1)); break;
    }
    return result;
  }

  String _specialFilterLabel(String key) {
    switch (key) {
      case 'need_login':
        return '需要登录';
      case 'no_group':
        return '未分组';
      case 'enabled':
        return '已启用';
      case 'disabled':
        return '未启用';
      case 'enabled_explore':
        return '已启用发现';
      default:
        return key;
    }
  }

  Future<void> _toggleSource(BookSource source, bool enabled) async {
    source.enabled = enabled;
    await _db.updateSource(source);
    setState(() {});
  }

  void _showSourceLogin(BookSource source) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SourceLoginScreen(source: source),
    ));
  }

  Future<void> _deleteSource(BookSource source) async {
    await _db.deleteSource(source.bookSourceUrl);
    _loadSources();
  }

  void _showAddMenu() {
    showAppMenuSheet(
      context,
      title: '书源',
      items: [
        AppMenuSheetItem(
          title: '网络导入',
          icon: Icons.add_link_outlined,
          subtitle: '从URL导入书源JSON',
          onTap: _showImportDialog,
        ),
        AppMenuSheetItem(
          title: '新建书源',
          icon: Icons.add_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SourceEditScreen()),
          ).then((_) => _loadSources()),
        ),
        AppMenuSheetItem(
          title: '剪贴板导入',
          icon: Icons.content_paste_outlined,
          subtitle: '从剪贴板粘贴书源JSON',
          onTap: _importFromClipboard,
        ),
        AppMenuSheetItem(
          title: '本地导入',
          icon: Icons.folder_open_outlined,
          subtitle: '从JSON文件导入',
          onTap: _importFromFile,
        ),
        AppMenuSheetItem(
          title: '导出书源',
          icon: Icons.ios_share_outlined,
          subtitle: '导出所有书源为JSON',
          onTap: _exportSources,
        ),
        AppMenuSheetItem(
          title: '二维码导入',
          icon: Icons.qr_code_scanner_outlined,
          subtitle: '扫描二维码导入书源',
          onTap: () async {
            final code = await Navigator.push<String>(context,
                MaterialPageRoute(builder: (_) => const QrScannerScreen(title: '扫描书源二维码')));
            if (code == null || code.isEmpty) return;
            final text = code.trim();
            if (text.startsWith('http')) {
              _importFromUrl(text);
            } else {
              if (!mounted || !context.mounted) return;
              final n = await runWithBusyDialog<int>(
                context,
                message: '正在导入书源…',
                task: _importSourcesFromString(text),
              );
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('导入 $n 个书源')));
              }
            }
          },
        ),
        AppMenuSheetItem(
          title: '导入选项',
          icon: Icons.rule_outlined,
          subtitle: '保留字段、导入范围、自定义分组、显示备注、同名替换',
          onTap: _showImportOptionsDialog,
        ),
        AppMenuSheetItem(
          title: '按域名分组',
          icon: Icons.domain_outlined,
          subtitle: '自动按域名分组显示',
          onTap: () {
            setState(() => _groupByDomain = !_groupByDomain);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_groupByDomain ? '已按域名分组' : '已取消域名分组')));
          },
        ),
        AppMenuSheetItem(
          title: '书源校验',
          icon: Icons.verified_outlined,
          subtitle: CheckSourceConfig.summary,
          onTap: () => _validateSources(),
        ),
        AppMenuSheetItem(
          title: '校验设置',
          icon: Icons.tune_outlined,
          subtitle: '超时时间与校验项',
          onTap: _showCheckSourceConfigDialog,
        ),
        AppMenuSheetItem(
          title: '分组管理',
          icon: Icons.folder_special_outlined,
          onTap: _showGroupManageDialog,
        ),
      ],
    );
  }

  Future<void> _importFromUrl(String url, {String? type}) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.bytes,
      ));
      final response = await dio.get<List<int>>(url);
      final bytes = response.data ?? [];
      // 检测 gzip 压缩（特殊书源常用 gzip 传输但可能无 Content-Encoding 头）
      var body = '';
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        body = utf8.decode(gzip.decode(bytes));
      } else {
        body = utf8.decode(bytes);
      }
      if (type != null) {
        // 指定类型：走统一导入分派
        await DeepLinkService.instance.importRaw(body, type: type);
      } else {
        if (!mounted || !context.mounted) return;
        final count = await runWithBusyDialog<int>(
          context,
          message: '正在导入书源…',
          task: _importSourcesFromString(body),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(count > 0 ? '成功导入 $count 个书源' : '未识别到有效书源')),
          );
        }
      }
      _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  /// 从字符串解析并导入书源，兼容 JSON 数组/单对象/包装对象/JSONL
  Future<int> _importSourcesFromString(String raw) async {
    var text = raw.trim();
    if (text.isEmpty) return 0;
    // 去除 BOM 与常见包裹
    if (text.startsWith('﻿')) text = text.substring(1);
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // 可能是 JSONL：逐行一个对象
      final lines = text.split(RegExp(r'[\r\n]+')).where((l) => l.trim().startsWith('{')).toList();
      if (lines.isEmpty) rethrow;
      final arr = [];
      for (final l in lines) {
        try { arr.add(jsonDecode(l)); } catch (_) {}
      }
      decoded = arr;
    }
    // 导入选项每次从 SharedPreferences 读取，保证「导入选项」对话框保存后立即生效
    final options = await SourceImportOptions.load();
    return _importSourcesFromData(decoded, options);
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final file = File(result.files.first.path!);
      final bytes = await file.readAsBytes();
      // 检测 gzip 压缩
      var content = '';
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        content = utf8.decode(gzip.decode(bytes));
      } else {
        content = utf8.decode(bytes);
      }
      if (!mounted || !context.mounted) return;
      final count = await runWithBusyDialog<int>(
        context,
        message: '正在导入书源…',
        task: _importSourcesFromString(content),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $count 个书源')),
        );
      }
      _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData == null || clipboardData.text == null || clipboardData.text!.isEmpty) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空')),
        );
        }
        return;
      }
      if (!mounted || !context.mounted) return;
      final count = await runWithBusyDialog<int>(
        context,
        message: '正在导入书源…',
        task: _importSourcesFromString(clipboardData.text!),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $count 个书源')),
        );
      }
      _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _exportSources() async {
    try {
      final sources = await _db.getAllSources();
      if (sources.isEmpty) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可导出的书源')),
        );
        }
        return;
      }
      final jsonStr = const JsonEncoder.withIndent('  ').convert(
        sources.map((s) => s.toJson()).toList(),
      );
      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: jsonStr));
      // 同时分享
      final tempFile = File('${Directory.systemTemp.path}/book_sources.json');
      await tempFile.writeAsString(jsonStr);
      await Share.shareXFiles([XFile(tempFile.path)], text: 'Legado书源导出 (${sources.length}个)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 ${sources.length} 个书源（已复制到剪贴板）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 按 [SourceImportOptions] 真实落库：新增/更新分流、保留本地字段、同名自动替换。
  /// insertSource 使用 ConflictAlgorithm.replace，故同名 URL 天然为覆盖更新。
  Future<int> _importSourcesFromData(
      dynamic data, SourceImportOptions options) async {
    // 解包常见订阅格式：{data:[...]} / {bookSources:[...]} / {result:[...]}
    dynamic unwrapped = data;
    if (unwrapped is Map && !unwrapped.containsKey('bookSourceUrl')) {
      for (final key in ['data', 'bookSources', 'sources', 'result', 'list', 'records']) {
        if (unwrapped[key] is List) { unwrapped = unwrapped[key]; break; }
      }
    }
    // 现有书源快照：按 URL 精确匹配（更新场景）+ 按名称匹配（同名替换场景）
    final existing = await _db.getAllSources();
    final existingByUrl = <String, BookSource>{
      for (final s in existing) s.bookSourceUrl: s,
    };
    int count = 0;
    final list = unwrapped is List ? unwrapped : [unwrapped];
    for (final item in list) {
      if (item is Map) {
        try {
          final m = Map<String, dynamic>.from(item);
          final url = (m['bookSourceUrl'] ?? '').toString();
          if (url.isEmpty) continue;
          final source = BookSource.fromJson(m);
          final old = existingByUrl[url];
          if (old == null) {
            // 新增源：受「选中新增源」控制
            if (!options.selectNewSource) continue;
          } else {
            // 更新源：受「选中更新源」控制，并按选项保留本地字段
            if (!options.selectUpdateSource) continue;
            if (options.keepOriginalName) source.bookSourceName = old.bookSourceName;
            if (options.keepGroup) source.bookSourceGroup = old.bookSourceGroup;
            if (options.keepEnabled) {
              source.enabled = old.enabled;
              source.enabledExplore = old.enabledExplore;
            }
          }
          // menu_new_group：把导入的书源统一归入指定分组（追加或整体替换）。
          // 对齐 Sigma ImportBookSourceViewModel.importSelect：groupName 在
          // keepGroup 之后应用，isAddGroup 时保留原分组并追加新分组。
          final group = options.newGroup.trim();
          if (group.isNotEmpty) {
            if (options.addGroup) {
              final parts = (source.bookSourceGroup ?? '')
                  .split(RegExp(r'[,，;；\s]+'))
                  .map((g) => g.trim())
                  .where((g) => g.isNotEmpty)
                  .toList();
              if (!parts.contains(group)) parts.add(group);
              source.bookSourceGroup = parts.join(',');
            } else {
              source.bookSourceGroup = group;
            }
          }
          // 导入时自动替换同名：删除同名但不同 URL 的旧书源
          if (options.autoReplaceSameName) {
            for (final s in existing) {
              if (s.bookSourceUrl != source.bookSourceUrl &&
                  s.bookSourceName == source.bookSourceName) {
                await _db.deleteSource(s.bookSourceUrl);
              }
            }
          }
          await _db.insertSource(source);
          existingByUrl[source.bookSourceUrl] = source;
          count++;
        } catch (_) {}
      }
    }
    return count;
  }

  /// 网络/在线导入（对齐 legado-E OnLineImportActivity）：打开独立的一键导入
  /// 界面，支持 URL / JSON / legado:// 链接与 7 类+readConfig 类型选择；
  /// 返回后刷新书源列表（导入可能新增/更新书源）。
  void _showImportDialog() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const OnlineImportScreen()))
        .then((_) => _loadSources());
  }

  /// 导入高级选项：对齐 legado-E `res/menu/import_source.xml` 的 7 项菜单
  /// （new_group / select_new_source / select_update_source / keep_original_name /
  /// keep_group / keep_enable / show_comment），另含 1 项扩展「自动替换同名」。
  /// 早期所写「12 项菜单」是官方原版口径，不适用于 Sigma 基准。
  Future<void> _showImportOptionsDialog() async {
    final current = await SourceImportOptions.load();
    if (!mounted) return;
    var keepOriginalName = current.keepOriginalName;
    var keepGroup = current.keepGroup;
    var keepEnabled = current.keepEnabled;
    var selectNewSource = current.selectNewSource;
    var selectUpdateSource = current.selectUpdateSource;
    var autoReplaceSameName = current.autoReplaceSameName;
    var showComment = current.showComment;
    var addGroup = current.addGroup;
    final groupCtl = TextEditingController(text: current.newGroup);
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: const Text('导入选项'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppSectionHeader('保留本地字段（menu_keep_*，同名 URL 更新时生效）'),
              SwitchListTile(
                title: const Text('保留原名'),
                subtitle: const Text('更新已有书源时不覆盖本地书源名称'),
                value: keepOriginalName,
                onChanged: (v) => setS(() => keepOriginalName = v),
              ),
              SwitchListTile(
                title: const Text('保留分组'),
                subtitle: const Text('更新已有书源时不覆盖本地分组'),
                value: keepGroup,
                onChanged: (v) => setS(() => keepGroup = v),
              ),
              SwitchListTile(
                title: const Text('保留启用状态'),
                subtitle: const Text('更新已有书源时不覆盖启用/发现开关'),
                value: keepEnabled,
                onChanged: (v) => setS(() => keepEnabled = v),
              ),
              const Divider(),
              const AppSectionHeader('导入范围（menu_select_*）'),
              SwitchListTile(
                title: const Text('选中新增源'),
                subtitle: const Text('导入书源库中尚不存在的书源'),
                value: selectNewSource,
                onChanged: (v) => setS(() => selectNewSource = v),
              ),
              SwitchListTile(
                title: const Text('选中更新源'),
                subtitle: const Text('覆盖更新书源库中已存在的书源'),
                value: selectUpdateSource,
                onChanged: (v) => setS(() => selectUpdateSource = v),
              ),
              const Divider(),
              const AppSectionHeader('自定义分组（menu_new_group）'),
              TextField(
                controller: groupCtl,
                decoration: const InputDecoration(
                  labelText: '导入分组名',
                  hintText: '留空则不改分组',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                title: const Text('追加到原分组'),
                subtitle: const Text('关闭则整体替换书源分组'),
                value: addGroup,
                onChanged: (v) => setS(() => addGroup = v),
              ),
              const Divider(),
              const AppSectionHeader('显示与扩展'),
              SwitchListTile(
                title: const Text('显示书源备注（menu_show_comment）'),
                subtitle: const Text('在书源列表中显示书源注释'),
                value: showComment,
                onChanged: (v) => setS(() => showComment = v),
              ),
              SwitchListTile(
                title: const Text('导入时自动替换同名（扩展）'),
                subtitle: const Text('存在同名但不同 URL 的旧源时先删除再导入'),
                value: autoReplaceSameName,
                onChanged: (v) => setS(() => autoReplaceSameName = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                await SourceImportOptions(
                  keepOriginalName: keepOriginalName,
                  keepGroup: keepGroup,
                  keepEnabled: keepEnabled,
                  selectNewSource: selectNewSource,
                  selectUpdateSource: selectUpdateSource,
                  autoReplaceSameName: autoReplaceSameName,
                  showComment: showComment,
                  newGroup: groupCtl.text.trim(),
                  addGroup: addGroup,
                ).save();
                if (d.mounted) Navigator.pop(d);
                await _loadShowComment();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('导入选项已保存')));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    groupCtl.dispose();
  }

  void _showSortDialog() {
    const sortNames = ['手动排序', '按权重', '按名称', '按URL', '按更新时间', '按响应时间', '按启用状态'];
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('排序方式'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ...List.generate(sortNames.length, (index) => RadioListTile<int>(
          title: Text(sortNames[index]),
          value: index,
          groupValue: _sortBy,
          onChanged: (v) => setState(() { _sortBy = v ?? 0; Navigator.pop(context); }),
        )),
        const Divider(),
        SwitchListTile(title: const Text('降序排列'), value: !_sortAsc, onChanged: (v) => setState(() => _sortAsc = !v)),
      ]),
    ));
  }

  void _showGroupManageDialog() {
    showDialog(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('分组管理'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('分组来源于书源；可在此重命名或解散（解散后书源回到未分组）。新建分组请在编辑书源或多选“添加分组”中设置。',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            if (_groups.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('暂无分组'))
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _groups.map((g) => ListTile(
                    dense: true,
                    title: Text(g),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.drive_file_rename_outline, size: 18), tooltip: '重命名', onPressed: () => _renameGroup(g)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18), tooltip: '解散分组', onPressed: () async {
                        for (final s in _sources.where((s) => s.bookSourceGroup == g)) {
                          s.bookSourceGroup = null;
                          await _db.updateSource(s);
                        }
                        await _loadSources();
                        if (mounted) { setDialogState(() {}); }
                      }),
                    ]),
                  )).toList(),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    ));
  }

  Future<void> _renameGroup(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: '新分组名', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;
    for (final s in _sources.where((s) => s.bookSourceGroup == oldName)) {
      s.bookSourceGroup = newName;
      await _db.updateSource(s);
    }
    await _loadSources();
    if (mounted) {
      // 刷新分组管理弹窗内容
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已重命名为「$newName」')));
    }
  }

  Future<void> _batchAction(String action) async {
    final selected = _sources.where((s) => _selectedIds.contains(s.bookSourceUrl)).toList();
    switch (action) {
      case 'enable_explore':
        for (final s in selected) { s.enabledExplore = true; await _db.updateSource(s); }
        if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已启用${selected.length}个书源的发现')));
        break;
      case 'disable_explore':
        for (final s in selected) { s.enabledExplore = false; await _db.updateSource(s); }
        if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已禁用${selected.length}个书源的发现')));
        break;
      case 'to_top':
        for (var i = 0; i < selected.length; i++) { selected[i].customOrder = -(i + 1); await _db.updateSource(selected[i]); }
        if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已置顶')));
        break;
      case 'to_bottom':
        for (var i = 0; i < selected.length; i++) { selected[i].customOrder = i + 1; await _db.updateSource(selected[i]); }
        if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已置底')));
        break;
      case 'add_group':
        _showBatchGroupDialog(selected, true);
        return;
      case 'remove_group':
        for (final s in selected) { s.bookSourceGroup = null; await _db.updateSource(s); }
        if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移除分组')));
        break;
      case 'check':
        Navigator.pop(context);
        final sel = _sources.where((s) => _selectedIds.contains(s.bookSourceUrl)).toList();
        _validateSources(sel.isNotEmpty ? sel : null);
        return;
      case 'invert':
        final all = _filteredSources.map((s) => s.bookSourceUrl).toSet();
        setState(() { final inverted = all.difference(_selectedIds); _selectedIds.clear(); _selectedIds.addAll(inverted); });
        return;
    }
    await _loadSources();
    setState(() { _selectMode = false; _selectedIds.clear(); });
  }

  void _showBatchGroupDialog(List selected, bool add) {
    final controller = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text(add ? '添加到分组' : '移除分组'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: '分组名称')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          for (final s in selected) { s.bookSourceGroup = controller.text; await _db.updateSource(s); }
          if (mounted && context.mounted) { Navigator.pop(context); await _loadSources(); setState(() { _selectMode = false; _selectedIds.clear(); }); }
        }, child: const Text('确定')),
      ],
    ));
  }

  Future<void> _batchEnable(bool enabled) async {
    for (final id in _selectedIds) {
      final source = _sources.where((s) => s.bookSourceUrl == id).firstOrNull;
      if (source != null) { source.enabled = enabled; await _db.updateSource(source); }
    }
    await _loadSources();
    setState(() { _selectMode = false; _selectedIds.clear(); });
  }

  Future<void> _batchDelete() async {
    for (final id in _selectedIds) { await _db.deleteSource(id); }
    await _loadSources();
    setState(() { _selectMode = false; _selectedIds.clear(); });
  }

  Future<void> _batchExport() async {
    final selected = _sources.where((s) => _selectedIds.contains(s.bookSourceUrl)).toList();
    if (selected.isEmpty) return;
    final jsonStr = const JsonEncoder.withIndent('  ').convert(selected.map((s) => s.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出${selected.length}个书源到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectMode ? Text('已选 ${_selectedIds.length} 个') : Text('书源管理 (${_sources.length})'),
        leading: _selectMode ? IconButton(icon: const Icon(Icons.close), tooltip: '取消多选', onPressed: () => setState(() { _selectMode = false; _selectedIds.clear(); })) : null,
        actions: _selectMode ? [
          IconButton(icon: const Icon(Icons.select_all_outlined), tooltip: '全选', onPressed: () => setState(() => _selectedIds.addAll(_filteredSources.map((s) => s.bookSourceUrl)))),
          IconButton(icon: const Icon(Icons.check_circle_outline), tooltip: '启用', onPressed: () => _batchEnable(true)),
          IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: '禁用', onPressed: () => _batchEnable(false)),
          IconButton(icon: const Icon(Icons.ios_share_outlined), tooltip: '导出', onPressed: _batchExport),
          PopupMenuButton<String>(
            onSelected: (v) => _batchAction(v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'enable_explore', child: Text('启用发现')),
              PopupMenuItem(value: 'disable_explore', child: Text('禁用发现')),
              PopupMenuItem(value: 'to_top', child: Text('选中置顶')),
              PopupMenuItem(value: 'to_bottom', child: Text('选中置底')),
              PopupMenuItem(value: 'add_group', child: Text('添加分组')),
              PopupMenuItem(value: 'remove_group', child: Text('移除分组')),
              PopupMenuItem(value: 'check', child: Text('校验选中')),
              PopupMenuItem(value: 'invert', child: Text('反选')),
            ],
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            tooltip: '删除',
            onPressed: () async {
              final ok = await showAppConfirmDialog(
                context,
                title: '删除选中',
                content: '确定删除${_selectedIds.length}个书源吗？',
                confirmText: '删除',
                danger: true,
              );
              if (ok) _batchDelete();
            },
          ),
        ] : [
          IconButton(
            icon: const Icon(Icons.search_outlined),
            tooltip: '搜索',
            onPressed: () {
              showSearch(
                context: context,
                delegate: SourceSearchDelegate(_sources, (source) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SourceEditScreen(source: source))).then((_) => _loadSources());
                }),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'enable_all':
                  for (final s in _sources) { s.enabled = true; _db.updateSource(s); }
                  setState(() {});
                  break;
                case 'disable_all':
                  for (final s in _sources) { s.enabled = false; _db.updateSource(s); }
                  setState(() {});
                  break;
                case 'select_mode':
                  setState(() { _selectMode = true; _selectedIds.clear(); });
                  break;
                case 'sort':
                  _showSortDialog();
                  break;
                case 'group_manage':
                  _showGroupManageDialog();
                  break;
                // 对齐 E BookSourceActivity 的 menu_group_* 特殊分组过滤
                case 'filter_need_login':
                case 'filter_no_group':
                case 'filter_enabled':
                case 'filter_disabled':
                case 'filter_enabled_explore':
                  setState(() => _specialFilter = value.substring(7));
                  break;
                case 'filter_clear':
                  setState(() => _specialFilter = null);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'select_mode', child: Text('多选模式')),
              PopupMenuItem(value: 'sort', child: Text('排序')),
              PopupMenuItem(value: 'group_manage', child: Text('分组管理')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'filter_need_login', child: Text('需要登录')),
              PopupMenuItem(value: 'filter_no_group', child: Text('未分组')),
              PopupMenuItem(value: 'filter_enabled', child: Text('已启用')),
              PopupMenuItem(value: 'filter_disabled', child: Text('未启用')),
              PopupMenuItem(value: 'filter_enabled_explore', child: Text('已启用发现')),
              PopupMenuItem(value: 'filter_clear', child: Text('清除过滤')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'enable_all', child: Text('全部启用')),
              PopupMenuItem(value: 'disable_all', child: Text('全部禁用')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 对齐 E BookSourceActivity：特殊分组过滤状态条，点了可一键清除
          if (_specialFilter != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, size: 16),
                  const SizedBox(width: 6),
                  Text('筛选：${_specialFilterLabel(_specialFilter!)}',
                      style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _specialFilter = null),
                    child: const Text('清除'),
                  ),
                ],
              ),
            ),
          if (_groups.isNotEmpty)
            AppChipTabs<String>(
              items: ['全部', ..._groups],
              selected: _selectedGroup ?? '全部',
              labelOf: (g) => g,
              onSelected: (g) =>
                  setState(() => _selectedGroup = g == '全部' ? null : g),
            ),
          Expanded(
            child: _isLoading
                ? const AppLoadingIndicator()
                : _filteredSources.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredSources.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final source = _filteredSources[index];
                          final selected = _selectedIds.contains(source.bookSourceUrl);
                    return Card(
                      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: ListTile(
                        leading: _selectMode
                            ? Checkbox(value: selected, onChanged: (_) => setState(() => selected ? _selectedIds.remove(source.bookSourceUrl) : _selectedIds.add(source.bookSourceUrl)))
                            : CircleAvatar(
                          backgroundColor: source.enabled == true
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Text(
                            source.bookSourceName.isNotEmpty ? source.bookSourceName[0] : '?',
                            style: TextStyle(color: source.enabled == true ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                        title: Text(source.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(source.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            if (source.bookSourceGroup != null && source.bookSourceGroup!.isNotEmpty)
                              Text('分组: ${source.bookSourceGroup}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                            // menu_show_comment：开关开启时在书源列表显示备注
                            if (_showComment && (source.bookSourceComment ?? '').isNotEmpty)
                              Text('备注: ${source.bookSourceComment}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        trailing: _selectMode ? null : Switch(
                          value: source.enabled == true,
                          onChanged: (value) => _toggleSource(source, value),
                        ),
                        onTap: () {
                          if (_selectMode) {
                            setState(() => selected ? _selectedIds.remove(source.bookSourceUrl) : _selectedIds.add(source.bookSourceUrl));
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => SourceEditScreen(source: source))).then((_) => _loadSources());
                          }
                        },
                        onLongPress: () => _selectMode ? setState(() => selected ? _selectedIds.remove(source.bookSourceUrl) : _selectedIds.add(source.bookSourceUrl)) : _showSourceOptions(source),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() => const AppEmptyState(
        icon: Icons.source_outlined,
        title: '暂无书源',
        message: '点击右下角添加或导入书源',
      );

  /// 书源校验（对齐 legado-E CheckSourceService：七项校验 + 失效分组 + 响应时间）
  Future<void> _validateSources([List<BookSource>? targets]) async {
    final sources = targets ?? await _db.getAllSources();
    if (sources.isEmpty) return;
    if (_checkService.isRunning) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有书源在校验，等完成后再试')));
      }
      return;
    }
    int done = 0, valid = 0, invalid = 0;
    String current = '';
    final sub = _checkService.progressStream.listen((p) {
      if (!mounted) return;
      setState(() {
        done = p.done;
        valid = p.validCount;
        invalid = p.invalidCount;
        current = p.currentName;
      });
    });
    if (!mounted) { sub.cancel(); return; }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (c, setS) {
        void upd() { if (c.mounted) setS(() {}); }
        upd();
        return AlertDialog(
          title: const Text('书源校验'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: sources.isEmpty ? 0 : done / sources.length),
            const SizedBox(height: 12),
            Text('进度 $done/${sources.length}  有效 $valid  无效 $invalid'),
            if (current.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('正在校验：$current',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () { _checkService.cancel(); Navigator.pop(c); },
              child: const Text('取消校验'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('后台运行'),
            ),
          ],
        );
      }),
    );
    final summary = await _checkService.start(sources);
    await sub.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭进度对话框
    await _loadSources();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(summary.errorMessage.isNotEmpty
          ? summary.errorMessage
          : summary.canceled
              ? '校验已取消：有效 $valid 个，无效 $invalid 个'
              : '校验完成：有效 ${summary.valid} 个，无效 ${summary.invalid} 个'),
    ));
  }

  /// 校验设置对话框（对齐 legado-E ui/config/CheckSourceConfig.kt）
  void _showCheckSourceConfigDialog() {
    var timeoutCtrl =
        TextEditingController(text: '${AppPrefs.checkSourceTimeout ~/ 1000}');
    var wSourceComment = AppPrefs.wSourceComment;
    var checkDomain = AppPrefs.checkDomain;
    var checkSearch = AppPrefs.checkSearch;
    var checkDiscovery = AppPrefs.checkDiscovery;
    var checkInfo = AppPrefs.checkInfo;
    var checkCategory = AppPrefs.checkCategory;
    var checkContent = AppPrefs.checkContent;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setS) {
        // 选项依赖关系（对齐 E 的 enable/disable 联动）
        void onSearchOrDiscoveryChanged() {
          if (!checkSearch && !checkDiscovery) {
            checkInfo = false;
            checkCategory = false;
            checkContent = false;
          }
        }
        void onInfoChanged() {
          if (!checkInfo) {
            checkCategory = false;
            checkContent = false;
          }
        }
        void onCategoryChanged() {
          if (!checkCategory) checkContent = false;
        }
        final infoEnabled = checkSearch || checkDiscovery;
        final categoryEnabled = infoEnabled && checkInfo;
        final contentEnabled = categoryEnabled && checkCategory;

        return AlertDialog(
          title: const Text('校验设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: timeoutCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '超时（秒）',
                    helperText: '单个书源校验的总超时时间',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('写入错误注释'),
                  subtitle: const Text('校验失败时把错误信息写入书源注释'),
                  value: wSourceComment,
                  onChanged: (v) => setS(() => wSourceComment = v),
                ),
                const Divider(),
                CheckboxListTile(
                  title: const Text('源地址'),
                  subtitle: const Text('Socket 探测源地址可达性'),
                  value: checkDomain,
                  onChanged: (v) => setS(() {
                    checkDomain = v ?? false;
                    if (!checkSearch && !checkDiscovery && !checkDomain) {
                      checkSearch = true;
                    }
                  }),
                ),
                CheckboxListTile(
                  title: const Text('搜索'),
                  value: checkSearch,
                  onChanged: (v) => setS(() {
                    checkSearch = v ?? false;
                    onSearchOrDiscoveryChanged();
                    if (!checkSearch && !checkDiscovery && !checkDomain) {
                      checkDiscovery = true;
                    }
                  }),
                ),
                CheckboxListTile(
                  title: const Text('发现'),
                  value: checkDiscovery,
                  onChanged: (v) => setS(() {
                    checkDiscovery = v ?? false;
                    onSearchOrDiscoveryChanged();
                    if (!checkSearch && !checkDiscovery && !checkDomain) {
                      checkSearch = true;
                    }
                  }),
                ),
                CheckboxListTile(
                  title: const Text('详情'),
                  value: checkInfo,
                  onChanged: infoEnabled
                      ? (v) => setS(() {
                            checkInfo = v ?? false;
                            onInfoChanged();
                          })
                      : null,
                ),
                CheckboxListTile(
                  title: const Text('目录'),
                  value: checkCategory,
                  onChanged: categoryEnabled
                      ? (v) => setS(() {
                            checkCategory = v ?? false;
                            onCategoryChanged();
                          })
                      : null,
                ),
                CheckboxListTile(
                  title: const Text('正文'),
                  value: checkContent,
                  onChanged: contentEnabled
                      ? (v) => setS(() => checkContent = v ?? false)
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final text = timeoutCtrl.text.trim();
                final secs = int.tryParse(text);
                if (secs == null || secs <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('超时时间不能为空且必须大于 0 秒')));
                  return;
                }
                AppPrefs.checkSourceTimeout = secs * 1000;
                AppPrefs.wSourceComment = wSourceComment;
                AppPrefs.checkDomain = checkDomain;
                AppPrefs.checkSearch = checkSearch;
                AppPrefs.checkDiscovery = checkDiscovery;
                AppPrefs.checkInfo = checkInfo;
                AppPrefs.checkCategory = checkCategory;
                AppPrefs.checkContent = checkContent;
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已保存：${CheckSourceConfig.summary}')));
              },
              child: const Text('确定'),
            ),
          ],
        );
      }),
    );
  }

  void _showSourceOptions(BookSource source) {
    showAppMenuSheet(
      context,
      title: source.bookSourceName,
      items: [
        AppMenuSheetItem(
          title: '编辑',
          icon: Icons.edit_outlined,
          onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SourceEditScreen(source: source)))
              .then((_) => _loadSources()),
        ),
        AppMenuSheetItem(
          title: source.enabled == true ? '禁用' : '启用',
          icon: source.enabled == true ? Icons.toggle_off : Icons.toggle_on,
          onTap: () => _toggleSource(source, !(source.enabled == true)),
        ),
        AppMenuSheetItem(
          title: '复制书源JSON',
          icon: Icons.content_copy_outlined,
          onTap: () async {
            final jsonStr = const JsonEncoder.withIndent('  ').convert(source.toJson());
            await Clipboard.setData(ClipboardData(text: jsonStr));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('书源JSON已复制到剪贴板')),
              );
            }
          },
        ),
        AppMenuSheetItem(
          title: '调试书源',
          icon: Icons.bug_report_outlined,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => SourceDebugScreen(source: source))),
        ),
        AppMenuSheetItem(
          title: '分享书源',
          icon: Icons.share_outlined,
          onTap: () async {
            final jsonStr = const JsonEncoder.withIndent('  ').convert(source.toJson());
            await Share.share(jsonStr, subject: source.bookSourceName);
          },
        ),
        AppMenuSheetItem(
          title: '分享二维码',
          icon: Icons.qr_code_2_outlined,
          subtitle: '生成书源二维码，供其它设备扫码导入',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => QrShareScreen(source: source))),
        ),
        AppMenuSheetItem(
          title: source.customOrder > 0 ? '取消置顶' : '置顶',
          icon: Icons.push_pin_outlined,
          onTap: () {
            source.customOrder = source.customOrder > 0 ? 0 : -1;
            _db.updateSource(source);
            _loadSources();
          },
        ),
        AppMenuSheetItem(
          title: '置底',
          icon: Icons.vertical_align_bottom_outlined,
          onTap: () {
            source.customOrder = 1;
            _db.updateSource(source);
            _loadSources();
          },
        ),
        AppMenuSheetItem(
          title: '登录',
          icon: Icons.login_outlined,
          onTap: () => _showSourceLogin(source),
        ),
        AppMenuSheetItem(
          title: source.enabledExplore ? '禁用发现' : '启用发现',
          icon: source.enabledExplore ? Icons.explore_off_outlined : Icons.explore_outlined,
          onTap: () {
            source.enabledExplore = !source.enabledExplore;
            _db.updateSource(source);
            _loadSources();
          },
        ),
        AppMenuSheetItem(
          title: '书源详情',
          icon: Icons.info_outline,
          onTap: () => showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(source.bookSourceName),
              content: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('URL: ${source.bookSourceUrl}'),
                  const SizedBox(height: 8),
                  Text('分组: ${source.bookSourceGroup ?? "默认"}'),
                  const SizedBox(height: 8),
                  Text('类型: ${source.bookSourceType == 0 ? "文本" : source.bookSourceType == 1 ? "音频" : source.bookSourceType == 2 ? "图片" : source.bookSourceType == 3 ? "文件" : "视频"}'),
                  const SizedBox(height: 8),
                  Text('搜索URL: ${source.searchUrl ?? "无"}'),
                  const SizedBox(height: 8),
                  Text('发现URL: ${source.exploreUrl ?? "无"}'),
                  const SizedBox(height: 8),
                  Text('响应时间: ${source.respondTime}ms'),
                  const SizedBox(height: 8),
                  Text('权重: ${source.weight}'),
                  const SizedBox(height: 8),
                  Text('备注: ${source.bookSourceComment ?? "无"}'),
                ],
              )),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
            ),
          ),
        ),
        AppMenuSheetItem(
          title: '删除',
          icon: Icons.delete_outline,
          onTap: () async {
            final ok = await showAppConfirmDialog(
              context,
              title: '删除书源',
              content: '确定要删除「${source.bookSourceName}」吗？',
              confirmText: '删除',
              danger: true,
            );
            if (ok) _deleteSource(source);
          },
        ),
      ],
    );
  }
}

class SourceSearchDelegate extends SearchDelegate<BookSource> {
  final List<BookSource> sources;
  final Function(BookSource) onSelect;

  SourceSearchDelegate(this.sources, this.onSelect);

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear_outlined), tooltip: '清除', onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    tooltip: '返回',
    onPressed: () => Navigator.pop(context),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = query.isEmpty
        ? sources
        : sources.where((s) => s.bookSourceName.contains(query) || s.bookSourceUrl.contains(query)).toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final source = results[index];
        return ListTile(
          title: Text(source.bookSourceName),
          subtitle: Text(source.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onSelect(source),
        );
      },
    );
  }
}


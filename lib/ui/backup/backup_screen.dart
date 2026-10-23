import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/help/storage/webdav_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/storage/backup_service.dart';
import 'package:legado_md3/help/storage/backup_zip.dart';
import 'package:legado_md3/data/local/app_database.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final BackupService _backupService = BackupService();

  /// 备份内容勾选（默认全选）
  final Map<BackupType, bool> _selected = {
    for (final t in BackupType.values) t: true,
  };
  /// 是否对敏感内容加密（zip 备份）
  bool _encryptBackup = false;
  /// 本地备份保留份数（0 表示不限）
  int _keepCount = BackupService.defaultKeepCount;
  /// 恢复前自动备份当前数据
  bool _restoreAutoBackup = true;
  /// 仅恢复最新备份（跳过云端备份选择弹窗）
  bool _onlyLatestBackup = true;
  /// 自动检查新备份（进入页面时静默比对云端备份数量）
  bool _autoCheckNewBackup = true;
  /// 恢复忽略项（恢复时默认取消勾选的数据类型）
  final Set<BackupType> _restoreIgnore = {};

  bool _isWorking = false;
  List<File> _backupFiles = [];
  final _webdavUrl = TextEditingController();
  final _webdavUser = TextEditingController();
  final _webdavPass = TextEditingController();
  final _webdavDir = TextEditingController();
  final _webdavDeviceName = TextEditingController();
  bool _syncProgress = false;

  /// 恢复忽略项可选数据类型（对照原版 restoreIgnore：书架/书源/RSS/替换规则/阅读记录/主题/配置）
  static const Map<BackupType, String> _restoreIgnoreItems = {
    BackupType.books: '书架',
    BackupType.bookSources: '书源',
    BackupType.rssSources: 'RSS',
    BackupType.replaceRules: '替换规则',
    BackupType.readRecords: '阅读记录',
    BackupType.theme: '主题',
    BackupType.settings: '配置',
  };

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
    _loadWebdav();
    _loadBackupPrefs();
  }

  Future<void> _loadBackupFiles() async {
    final files = await _backupService.getBackupFiles();
    if (mounted) setState(() => _backupFiles = files);
  }

  Future<void> _loadBackupPrefs() async {
    final p = await SharedPreferences.getInstance();
    // 全局持久化配置（webDavDeviceName / restoreIgnore / onlyLatestBackup / autoCheckNewBackup）
    AppPrefs.loadFrom(p);
    if (!mounted) return;
    setState(() {
      _encryptBackup = p.getBool('backup_encrypt') ?? false;
      _keepCount = p.getInt('backup_keep_count') ?? BackupService.defaultKeepCount;
      _restoreAutoBackup = p.getBool('backup_restore_auto') ?? true;
      _onlyLatestBackup = AppPrefs.onlyLatestBackup;
      _autoCheckNewBackup = AppPrefs.autoCheckNewBackup;
      _restoreIgnore
        ..clear()
        ..addAll(BackupType.values.where((t) => AppPrefs.restoreIgnore.contains(t.name)));
    });
    // 自动检查新备份：配置了 WebDAV 时静默比对云端备份数量
    if (AppPrefs.autoCheckNewBackup && _webdavUrl.text.trim().isNotEmpty) {
      _checkNewBackupSilently();
    }
  }

  Future<void> _saveBackupPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('backup_encrypt', _encryptBackup);
    await p.setInt('backup_keep_count', _keepCount);
    await p.setBool('backup_restore_auto', _restoreAutoBackup);
    AppPrefs.onlyLatestBackup = _onlyLatestBackup;
    AppPrefs.autoCheckNewBackup = _autoCheckNewBackup;
  }

  /// 静默检查 WebDAV 云端备份数量变化（autoCheckNewBackup）
  Future<void> _checkNewBackupSilently() async {
    try {
      final list = await _webdav().listBackups();
      if (!mounted) return;
      final p = await SharedPreferences.getInstance();
      final last = p.getInt('webdav_last_backup_count');
      if (last != null && list.length != last) {
        _tip('WebDAV 云端备份数量变化：${list.length} 个');
      }
      await p.setInt('webdav_last_backup_count', list.length);
    } catch (_) {}
  }

  /// 恢复忽略项多选对话框
  Future<void> _showRestoreIgnoreDialog() async {
    final temp = Set<BackupType>.of(_restoreIgnore);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('恢复忽略项'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('勾选的数据类型在恢复时默认取消，避免覆盖本地数据', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          ..._restoreIgnoreItems.entries.map((e) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: temp.contains(e.key),
            title: Text(e.value),
            onChanged: (v) => setDialogState(() {
              if (v == true) {
                temp.add(e.key);
              } else {
                temp.remove(e.key);
              }
            }),
          )),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () {
            setState(() {
              _restoreIgnore
                ..clear()
                ..addAll(temp);
            });
            AppPrefs.restoreIgnore = temp.map((t) => t.name).toList();
            Navigator.pop(ctx);
          }, child: const Text('保存')),
        ],
      )),
    );
  }

  Future<void> _loadWebdav() async {
    final p = await SharedPreferences.getInstance();
    _webdavUrl.text = p.getString('webdav_url') ?? '';
    _webdavUser.text = p.getString('webdav_user') ?? '';
    _webdavPass.text = p.getString('webdav_pass') ?? '';
    _webdavDir.text = p.getString('webdav_dir') ?? 'Legado/backup';
    _webdavDeviceName.text = AppPrefs.webDavDeviceName;
    setState(() => _syncProgress = p.getBool('webdav_syncProgress') ?? false);
  }
  Future<void> _saveWebdav() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('webdav_url', _webdavUrl.text);
    await p.setString('webdav_user', _webdavUser.text);
    await p.setString('webdav_pass', _webdavPass.text);
    await p.setString('webdav_dir', _webdavDir.text);
    await p.setBool('webdav_syncProgress', _syncProgress);
    AppPrefs.webDavDeviceName = _webdavDeviceName.text;
  }
  Widget _buildWebdavCard() => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.cloud, size: 20),
        const SizedBox(width: 8),
        Text('WebDAV设置', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _webdavUrl, decoration: const InputDecoration(labelText: 'WebDAV URL', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: _webdavUser, decoration: const InputDecoration(labelText: '账号', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: _webdavPass, obscureText: true, decoration: const InputDecoration(labelText: '密码', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(controller: _webdavDir, decoration: const InputDecoration(labelText: '备份子目录', isDense: true, border: OutlineInputBorder())),
      TextField(controller: _webdavDeviceName, decoration: const InputDecoration(labelText: '设备名', isDense: true, border: OutlineInputBorder(), hintText: '标识备份来源设备，如 我的手机')),
      SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('同步阅读进度'), value: _syncProgress, onChanged: (v) => setState(() => _syncProgress = v)),
      Row(children: [
        OutlinedButton(onPressed: () async { await _saveWebdav(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WebDAV配置已保存'))); }, child: const Text('保存配置')),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _testWebDav, child: const Text('测试')),
        OutlinedButton(onPressed: _restoreFromWebDav, child: const Text('云端恢复')),
        const Spacer(),
        FilledButton(onPressed: _uploadWebDav, child: const Text('上传')),
      ]),
    ])),
  );
  WebDavService _webdav() {
    final s = WebDavService();
    s.configure(baseUrl: _webdavUrl.text.trim(), username: _webdavUser.text.trim(), password: _webdavPass.text);
    return s;
  }

  void _tip(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _testWebDav() async {
    if (_webdavUrl.text.trim().isEmpty) { _tip('请先填写 WebDAV 地址'); return; }
    await _saveWebdav();
    _tip('正在测试连接...');
    final ok = await _webdav().testConnection();
    _tip(ok ? 'WebDAV 连接成功' : '连接失败，请检查地址/账号/密码');
  }

  /// 上传 zip 备份到 WebDAV（含勾选内容，可选加密）
  Future<void> _uploadWebDav() async {
    if (_webdavUrl.text.trim().isEmpty) { _tip('请先填写 WebDAV 地址'); return; }
    final selection = BackupSelection(_selected.entries.where((e) => e.value).map((e) => e.key).toSet());
    if (selection.types.isEmpty) { _tip('请先勾选备份内容'); return; }
    await _saveWebdav();
    // 加密备份需要先输入密码
    String? password;
    if (_encryptBackup) {
      password = await _askPassword(confirm: true);
      if (password == null) return;
    }
    setState(() => _isWorking = true);
    try {
      final bytes = await _backupService.createZipBackup(selection: selection, password: password);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      // 设备名（webDavDeviceName）写入云端备份文件名，标识备份来源设备
      final deviceTag = AppPrefs.webDavDeviceName.isEmpty
          ? ''
          : '_${AppPrefs.webDavDeviceName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
      final ok = await _webdav().uploadBackup('backup_$ts$deviceTag.zip', bytes);
      // 勾选「同步阅读进度」时，额外上传一份阅读进度
      if (ok && _syncProgress) {
        final progress = await DatabaseService().getAllBookProgress();
        await _webdav().uploadReadingProgress(progress.map((e) => e.toMap()).toList());
      }
      _tip(ok ? '已上传到 WebDAV（zip${password != null ? '·加密' : ''}）' : '上传失败');
    } catch (e) {
      _tip('上传失败: $e');
    }
    if (mounted) setState(() => _isWorking = false);
  }

  Future<void> _restoreFromWebDav() async {
    if (_webdavUrl.text.trim().isEmpty) { _tip('请先填写 WebDAV 地址'); return; }
    final list = await _webdav().listBackups();
    if (!mounted) return;
    if (list.isEmpty) { _tip('云端没有备份文件'); return; }
    String chosen;
    if (_onlyLatestBackup) {
      // 仅恢复最新备份：按文件名（时间戳）取最新，跳过选择弹窗
      chosen = list.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    } else {
      final picked = await showDialog<String>(context: context, builder: (d) => SimpleDialog(
        title: const Text('选择云端备份'),
        children: list.reversed.map((name) => SimpleDialogOption(child: Text(name), onPressed: () => Navigator.pop(d, name))).toList(),
      ));
      if (picked == null) return;
      chosen = picked;
    }
    setState(() => _isWorking = true);
    try {
      final bytes = await _webdav().downloadBackup(chosen);
      if (bytes == null) { _tip('下载失败'); return; }
      final dir = await getTemporaryDirectory();
      // 云端可能是 zip 或旧版 json，按文件头自动识别，后缀不影响
      final tmp = File('${dir.path}/webdav_restore_${DateTime.now().millisecondsSinceEpoch}.bak');
      await tmp.writeAsBytes(bytes);
      await _showRestoreDialog(tmp.path);
    } catch (e) {
      _tip('恢复失败: $e');
    }
    if (mounted) setState(() => _isWorking = false);
  }

  /// 弹出密码输入对话框；[confirm] 为 true 时需输入两次
  Future<String?> _askPassword({bool confirm = false}) async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(confirm ? '设置备份密码' : '输入备份密码'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: p1, obscureText: true, autofocus: true,
            decoration: const InputDecoration(labelText: '密码（留空则不加密）')),
          if (confirm) ...[
            const SizedBox(height: 8),
            TextField(controller: p2, obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码')),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
          FilledButton(onPressed: () {
            if (confirm && p1.text != p2.text) return; // 两次不一致不关闭
            Navigator.pop(d, p1.text);
          }, child: const Text('确定')),
        ],
      ),
    );
    if (confirm && result != null && result.isEmpty) return null;
    return result;
  }

  /// 创建 zip 备份（含内容勾选与可选加密）
  Future<void> _createBackup() async {
    final selection = BackupSelection(_selected.entries.where((e) => e.value).map((e) => e.key).toSet());
    if (selection.types.isEmpty) {
      _tip('请先勾选备份内容');
      return;
    }
    await _saveBackupPrefs();
    // 加密备份：弹窗输入密码
    String? password;
    if (_encryptBackup) {
      password = await _askPassword(confirm: true);
      if (password == null) return;
    }
    setState(() => _isWorking = true);
    try {
      final path = await _backupService.exportZipBackupToFile(
        selection: selection,
        password: password,
      );
      await _loadBackupFiles();
      if (mounted) {
        _tip('备份已保存: ${path.split('/').last}（只保留最近 $_keepCount 份）');
      }
    } catch (e) {
      _tip('备份失败: $e');
    }
    if (mounted) setState(() => _isWorking = false);
  }

  /// 弹出「选择性恢复」对话框：勾选恢复内容 + 恢复前自动备份 + 密码
  Future<void> _showRestoreDialog(String filePath) async {
    final info = await _backupService.inspectBackupFile(filePath);
    if (!mounted) return;
    // 恢复勾选（默认勾选备份中包含的类型；解析失败时全列）
    // restoreIgnore：勾选忽略的类型默认取消且禁止勾选
    final restoreTypes = <BackupType>{...info.selection.types}..removeWhere(_restoreIgnore.contains);
    final pwdController = TextEditingController();
    var autoBackup = _restoreAutoBackup;

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (ctx, setDialogState) {
        Future<void> verifyPassword() async {
          final pwd = pwdController.text;
          final re = await _backupService.inspectBackupFile(filePath, password: pwd);
          if (!ctx.mounted) return;
          setDialogState(() {
            restoreTypes
              ..clear()
              ..addAll(re.selection.types);
            if (re.error != null) {
              _tip(re.error!);
            }
          });
        }
        return AlertDialog(
          title: const Text('选择恢复内容'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 备份概要
                  Text(
                    '${info.fileName}\n'
                    '${info.isZip ? 'zip' : '旧版JSON'}'
                    '${info.encrypted ? ' · 加密' : ''}'
                    '${info.deviceName != null ? ' · ${info.deviceName}' : ''}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  if (info.error != null && restoreTypes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('无法读取备份内容：${info.error}\n若是加密备份，请输入密码后点击「验证密码」。',
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ),
                  const Divider(),
                  // 内容多选
                  ...BackupType.values.map((t) {
                    final inBackup = info.selection.types.isEmpty || info.selection.contains(t);
                    final ignored = _restoreIgnore.contains(t);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: restoreTypes.contains(t),
                      title: Text(ignored ? '${t.label}（恢复忽略）' : (inBackup || info.selection.types.isEmpty ? t.label : '${t.label}（备份中无）')),
                      onChanged: ignored ? null : (v) => setDialogState(() {
                        if (v == true) {
                          restoreTypes.add(t);
                        } else {
                          restoreTypes.remove(t);
                        }
                      }),
                    );
                  }),
                  const Divider(),
                  // 恢复前自动备份保护
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('恢复前自动备份当前数据'),
                    value: autoBackup,
                    onChanged: (v) => setDialogState(() => autoBackup = v),
                  ),
                  // 加密备份密码
                  if (info.encrypted || info.error != null) ...[
                    const SizedBox(height: 8),
                    TextField(controller: pwdController, obscureText: true,
                      decoration: const InputDecoration(labelText: '备份密码', isDense: true)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: verifyPassword, child: const Text('验证密码')),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('开始恢复')),
          ],
        );
      }),
    );
    if (ok != true) return;
    if (restoreTypes.isEmpty) { _tip('请至少勾选一项恢复内容'); return; }
    if (autoBackup != _restoreAutoBackup) {
      _restoreAutoBackup = autoBackup;
      await _saveBackupPrefs();
    }
    setState(() => _isWorking = true);
    try {
      // 恢复前自动备份当前数据，避免恢复后丢失
      if (autoBackup) {
        final autoPath = await _backupService.autoBackupBeforeRestore();
        if (autoPath != null) {
          _tip('已自动备份当前数据: ${autoPath.split('/').last}');
        }
      }
      final res = await _backupService.restoreFromFile(
        filePath,
        password: pwdController.text.isEmpty ? null : pwdController.text,
        only: BackupSelection(restoreTypes),
      );
      _tip(res.summary);
      await _loadBackupFiles();
    } catch (e) {
      _tip('恢复失败: $e');
    }
    if (mounted) setState(() => _isWorking = false);
  }

  /// 从文件恢复（支持 zip / 旧版 json）
  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'zip', 'bak'],
      );
      if (result == null || result.files.isEmpty) return;
      await _showRestoreDialog(result.files.first.path!);
    } catch (e) {
      _tip('恢复失败: $e');
    }
  }

  Future<void> _importSources() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final bytes = await file.readAsBytes();
      // 检测 gzip 压缩（特殊书源常用 gzip 传输）
      var content = '';
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        content = utf8.decode(gzip.decode(bytes));
      } else {
        content = utf8.decode(bytes);
      }
      final count = await _backupService.importSources(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $count 个书源')),
        );
      }
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
      final content = await _backupService.exportSources();
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/book_sources.json');
      await file.writeAsString(content);
      await Share.shareXFiles([XFile(file.path)], text: '书源导出');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteBackup(File file) async {
    await _backupService.deleteBackup(file.path);
    await _loadBackupFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: _isWorking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 备份内容勾选 + 加密 + 保留份数
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('备份内容', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          TextButton(onPressed: () => setState(() {
                            for (final t in _selected.keys) { _selected[t] = true; }
                          }), child: const Text('全选')),
                          TextButton(onPressed: () => setState(() {
                            for (final t in _selected.keys) { _selected[t] = false; }
                          }), child: const Text('全不选')),
                        ]),
                        const SizedBox(height: 8),
                        // 内容多选（chip 形式，紧凑展示 17 类）
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: BackupType.values.map((t) => FilterChip(
                            label: Text(t.label),
                            selected: _selected[t] == true,
                            onSelected: (v) => setState(() => _selected[t] = v),
                          )).toList(),
                        ),
                        const SizedBox(height: 12),
                        // 加密开关（zip 内敏感数据加密）
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('加密敏感内容'),
                          subtitle: const Text('书源/服务器等含登录信息的数据将以密码加密后存入 zip'),
                          value: _encryptBackup,
                          onChanged: (v) { setState(() => _encryptBackup = v); _saveBackupPrefs(); },
                        ),
                        // 保留份数
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('本地备份保留份数'),
                          trailing: DropdownButton<int>(
                            value: _keepCount,
                            items: const [
                              DropdownMenuItem(value: 3, child: Text('3 份')),
                              DropdownMenuItem(value: 5, child: Text('5 份')),
                              DropdownMenuItem(value: 10, child: Text('10 份')),
                              DropdownMenuItem(value: 20, child: Text('20 份')),
                              DropdownMenuItem(value: 100, child: Text('不限')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _keepCount = v);
                              _saveBackupPrefs();
                              _backupService.cleanOldBackups(keep: v).then((_) => _loadBackupFiles());
                            },
                          ),
                        ),
                        // 恢复忽略项（restoreIgnore）
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('恢复忽略项'),
                          subtitle: Text(
                            _restoreIgnore.isEmpty
                                ? '无，恢复时勾选备份中的全部内容'
                                : '已忽略：${_restoreIgnore.map((t) => t.label).join('、')}',
                            style: const TextStyle(fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _showRestoreIgnoreDialog,
                        ),
                        // 仅恢复最新备份（onlyLatestBackup）
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('仅恢复最新备份'),
                          subtitle: const Text('从 WebDAV 恢复时直接使用最新备份，跳过选择弹窗'),
                          value: _onlyLatestBackup,
                          onChanged: (v) {
                            setState(() => _onlyLatestBackup = v);
                            _saveBackupPrefs();
                          },
                        ),
                        // 自动检查新备份（autoCheckNewBackup）
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('自动检查新备份'),
                          subtitle: const Text('进入本页面时静默比对 WebDAV 云端备份数量，有变化时提示'),
                          value: _autoCheckNewBackup,
                          onChanged: (v) {
                            setState(() => _autoCheckNewBackup = v);
                            _saveBackupPrefs();
                            if (v) _checkNewBackupSilently();
                          },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _createBackup,
                            icon: const Icon(Icons.backup),
                            label: const Text('创建备份（zip）'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 恢复
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.restore),
                        title: const Text('从文件恢复'),
                        subtitle: const Text('支持 zip / 旧版 JSON 备份，可选择恢复内容'),
                        onTap: _restoreBackup,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.file_download),
                        title: const Text('导入书源'),
                        subtitle: const Text('从JSON/TXT文件导入书源'),
                        onTap: _importSources,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.file_upload),
                        title: const Text('导出书源'),
                        subtitle: const Text('导出所有书源为JSON文件'),
                        onTap: _exportSources,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildWebdavCard(),
                const SizedBox(height: 16),
                // 本地备份列表
                if (_backupFiles.isNotEmpty) ...[
                  Text('本地备份', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._backupFiles.map((file) => Card(
                    child: ListTile(
                      leading: Icon(file.path.endsWith('.zip') ? Icons.folder_zip : Icons.description),
                      title: Text(file.path.split('/').last),
                      subtitle: Text('${file.lengthSync() ~/ 1024} KB'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteBackup(file),
                      ),
                      onTap: () => _showRestoreDialog(file.path),
                    ),
                  )),
                ],
              ],
            ),
    );
  }
}

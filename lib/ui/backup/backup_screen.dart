import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/help/storage/webdav_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/help/storage/backup_service.dart';
import 'package:legado_md3/data/local/app_database.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final BackupService _backupService = BackupService();
  bool _includeBooks = true;
  bool _includeSources = true;
  bool _includeRules = true;
  bool _includeRecords = true;
  bool _isWorking = false;
  List<File> _backupFiles = [];
  final _webdavUrl = TextEditingController();
  final _webdavUser = TextEditingController();
  final _webdavPass = TextEditingController();
  final _webdavDir = TextEditingController();
  bool _syncProgress = false;

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
    _loadWebdav();
  }

  Future<void> _loadBackupFiles() async {
    final files = await _backupService.getBackupFiles();
    if (mounted) setState(() => _backupFiles = files);
  }

  Future<void> _loadWebdav() async {
    final p = await SharedPreferences.getInstance();
    _webdavUrl.text = p.getString('webdav_url') ?? '';
    _webdavUser.text = p.getString('webdav_user') ?? '';
    _webdavPass.text = p.getString('webdav_pass') ?? '';
    _webdavDir.text = p.getString('webdav_dir') ?? 'Legado/backup';
    setState(() => _syncProgress = p.getBool('webdav_syncProgress') ?? false);
  }
  Future<void> _saveWebdav() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('webdav_url', _webdavUrl.text);
    await p.setString('webdav_user', _webdavUser.text);
    await p.setString('webdav_pass', _webdavPass.text);
    await p.setString('webdav_dir', _webdavDir.text);
    await p.setBool('webdav_syncProgress', _syncProgress);
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

  Future<void> _uploadWebDav() async {
    if (_webdavUrl.text.trim().isEmpty) { _tip('请先填写 WebDAV 地址'); return; }
    await _saveWebdav();
    setState(() => _isWorking = true);
    try {
      final data = await _backupService.createBackup(
        includeBooks: _includeBooks, includeSources: _includeSources,
        includeReplaceRules: _includeRules, includeReadRecords: _includeRecords,
      );
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      var ok = await _webdav().uploadBackup('backup_$ts.json', utf8.encode(jsonEncode(data)));
      // 勾选「同步阅读进度」时，额外上传一份阅读进度
      if (ok && _syncProgress) {
        final progress = await DatabaseService().getAllBookProgress();
        await _webdav().uploadReadingProgress(progress.map((e) => e.toMap()).toList());
      }
      _tip(ok ? '已上传到 WebDAV' : '上传失败');
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
    final chosen = await showDialog<String>(context: context, builder: (d) => SimpleDialog(
      title: const Text('选择云端备份'),
      children: list.reversed.map((name) => SimpleDialogOption(child: Text(name), onPressed: () => Navigator.pop(d, name))).toList(),
    ));
    if (chosen == null) return;
    setState(() => _isWorking = true);
    try {
      final bytes = await _webdav().downloadBackup(chosen);
      if (bytes == null) { _tip('下载失败'); return; }
      final dir = await getTemporaryDirectory();
      final tmp = File('${dir.path}/webdav_restore.json');
      await tmp.writeAsBytes(bytes);
      final res = await _backupService.restoreFromFile(tmp.path);
      _tip(res.summary);
      await _loadBackupFiles();
    } catch (e) {
      _tip('恢复失败: $e');
    }
    if (mounted) setState(() => _isWorking = false);
  }

  Future<void> _createBackup() async {
    setState(() => _isWorking = true);
    try {
      final path = await _backupService.exportBackupToFile(
        includeBooks: _includeBooks,
        includeSources: _includeSources,
        includeReplaceRules: _includeRules,
        includeReadRecords: _includeRecords,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已保存: $path')),
        );
        await _loadBackupFiles();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e')),
        );
      }
    }
    if (mounted) setState(() => _isWorking = false);
  }

  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      setState(() => _isWorking = true);
      final backupResult = await _backupService.restoreFromFile(result.files.first.path!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(backupResult.summary)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败: $e')),
        );
      }
    }
    if (mounted) setState(() => _isWorking = false);
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
                // 备份选项
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('备份内容', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SwitchListTile(title: const Text('书籍'), value: _includeBooks, onChanged: (v) => setState(() => _includeBooks = v)),
                        SwitchListTile(title: const Text('书源'), value: _includeSources, onChanged: (v) => setState(() => _includeSources = v)),
                        SwitchListTile(title: const Text('替换规则'), value: _includeRules, onChanged: (v) => setState(() => _includeRules = v)),
                        SwitchListTile(title: const Text('阅读记录'), value: _includeRecords, onChanged: (v) => setState(() => _includeRecords = v)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _createBackup,
                            icon: const Icon(Icons.backup),
                            label: const Text('创建备份'),
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
                        subtitle: const Text('选择备份文件恢复数据'),
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
                // 备份文件列表
                if (_backupFiles.isNotEmpty) ...[
                  Text('本地备份', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._backupFiles.map((file) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.description),
                      title: Text(file.path.split('/').last),
                      subtitle: Text('${file.lengthSync() ~/ 1024} KB'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteBackup(file),
                      ),
                      onTap: () async {
                        final result = await _backupService.restoreFromFile(file.path);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.summary)));
                        }
                      },
                    ),
                  )),
                ],
              ],
            ),
    );
  }
}

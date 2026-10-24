import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:legado_md3/ui/book/import/remote_book_screen.dart';

class LocalImportScreen extends StatefulWidget {
  const LocalImportScreen({super.key});

  @override
  State<LocalImportScreen> createState() => _LocalImportScreenState();
}

class _LocalImportScreenState extends State<LocalImportScreen> {
  final ImportBookService _importService = ImportBookService();
  final List<File> _selectedFiles = [];
  bool _isImporting = false;
  double _progress = 0;

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // 对齐 legado-E：txt/epub/umd/pdf/mobi/azw3/azw + zip 压缩包
        allowedExtensions: [
          'txt', 'TXT', 'epub', 'EPUB', 'umd', 'UMD', 'mobi', 'MOBI',
          'azw', 'AZW', 'azw3', 'AZW3', 'pdf', 'PDF', 'zip', 'ZIP',
        ],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            if (file.path != null) {
              final f = File(file.path!);
              if (!_selectedFiles.any((e) => e.path == f.path)) {
                _selectedFiles.add(f);
              }
            }
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }

  Future<void> _importBooks() async {
    if (_selectedFiles.isEmpty) return;
    setState(() {
      _isImporting = true;
      _progress = 0;
    });

    int successCount = 0;
    int totalBooks = 0;
    String? lastError;
    for (var i = 0; i < _selectedFiles.length; i++) {
      try {
        final file = _selectedFiles[i];
        // 统一走导入服务：TXT/EPUB/UMD/MOBI/PDF/ZIP 全格式（对齐 legado-E）
        final res = await _importService.importPath(file.path);
        successCount++;
        totalBooks += res.totalBooks;
      } catch (e) {
        lastError = e.toString();
        debugPrint('导入失败: $e');
      }
      setState(() => _progress = (i + 1) / _selectedFiles.length);
    }

    setState(() => _isImporting = false);
    if (mounted) {
      final msg = successCount == _selectedFiles.length
          ? (totalBooks > successCount ? '成功导入 $totalBooks 本书' : '成功导入 $successCount 本书')
          : '成功导入 $successCount/${_selectedFiles.length} 个文件${lastError != null ? '（最后一个错误: $lastError）' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地导入'),
        actions: [
          IconButton(tooltip: '远程书籍', icon: const Icon(Icons.cloud_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteBookScreen()))),
          if (_selectedFiles.isNotEmpty)
            TextButton(
              onPressed: _isImporting ? null : _importBooks,
              child: Text('导入 (${_selectedFiles.length})'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isImporting)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: _selectedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('还没有选择文件', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        const Text('支持TXT / EPUB / UMD / MOBI / PDF / ZIP',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _selectedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _selectedFiles[index];
                      return ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${(file.lengthSync() / 1024).toStringAsFixed(1)} KB'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _pickFiles,
        icon: const Icon(Icons.add),
        label: const Text('选择文件'),
      ),
    );
  }
}

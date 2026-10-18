import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/read_record.dart';

class ReadRecordScreen extends StatefulWidget {
  const ReadRecordScreen({super.key});

  @override
  State<ReadRecordScreen> createState() => _ReadRecordScreenState();
}

class _ReadRecordScreenState extends State<ReadRecordScreen> {
  final DatabaseService _db = DatabaseService();
  List<ReadRecord> _records = [];
  bool _loading = true;
  int _totalDuration = 0;
  int _totalDays = 0;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await _db.getReadRecords(100);
    final totalDuration = records.fold<int>(0, (sum, r) => sum + (r.duration));
    final days = records.map((r) => DateTime.fromMillisecondsSinceEpoch(r.date).day).toSet().length;
    setState(() {
      _records = records;
      _totalDuration = totalDuration;
      _totalDays = days;
      _loading = false;
    });
  }

  String _formatDuration(int ms) {
    final minutes = ms ~/ 60000;
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) return '$hours小时$mins分钟';
    return '$mins分钟';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读记录')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(padding: const EdgeInsets.all(16), color: Theme.of(context).colorScheme.primaryContainer, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _buildStat('阅读天数', '$_totalDays天'),
                _buildStat('总时长', _formatDuration(_totalDuration)),
                _buildStat('记录数', '${_records.length}条'),
              ])),
              Expanded(child: _records.isEmpty ? const Center(child: Text('暂无阅读记录')) : ListView.builder(
                itemCount: _records.length,
                itemBuilder: (context, index) {
                  final record = _records[index];
                  final date = DateTime.fromMillisecondsSinceEpoch(record.date);
                  return Card(child: ListTile(
                    leading: CircleAvatar(child: Text(record.bookName.isNotEmpty ? record.bookName[0] : '?')),
                    title: Text(record.bookName),
                    subtitle: Text('${record.author} · ${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}'),
                    trailing: Text(_formatDuration(record.duration), style: const TextStyle(fontSize: 12)),
                  ));
                },
              )),
            ]),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 12))]);
  }
}

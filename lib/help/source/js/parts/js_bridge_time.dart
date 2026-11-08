/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsBridgeTime。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 对齐 java.timeFormat / timeFormatUTC（桥侧 __timeFormat 的 yyyy/MM/dd/HH/mm/ss）。
class JsBridgeTime {
  JsBridgeTime._();

  /// [time] 可为秒/毫秒时间戳或日期字符串；[pattern] 默认 yyyy-MM-dd HH:mm:ss。
  static String timeFormat(Object? time,
      [String pattern = 'yyyy-MM-dd HH:mm:ss', bool utc = false]) {
    if (time == null) return '';
    DateTime? d;
    if (time is int) {
      d = DateTime.fromMillisecondsSinceEpoch(_ms(time), isUtc: utc);
    } else {
      final s = time.toString();
      if (RegExp(r'^\d+$').hasMatch(s)) {
        d = DateTime.fromMillisecondsSinceEpoch(_ms(int.parse(s)), isUtc: utc);
      } else {
        d = DateTime.tryParse(s.replaceAll('-', '/'));
        if (d != null && utc) d = d.toUtc();
      }
    }
    if (d == null) return '';
    if (!utc) d = d.toLocal();
    String p2(int n) => n.toString().padLeft(2, '0');
    return pattern
        .replaceAll('yyyy', d.year.toString())
        .replaceAll('yy', d.year.toString().substring(2))
        .replaceAll('MM', p2(d.month))
        .replaceAll('dd', p2(d.day))
        .replaceAll('HH', p2(d.hour))
        .replaceAll('mm', p2(d.minute))
        .replaceAll('ss', p2(d.second));
  }

  static int _ms(int n) => n < 1000000000000 ? n * 1000 : n;
}

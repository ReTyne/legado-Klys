/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsBridgeCache。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 对齐 cache 对象：put/get 为可回写态，putMemory/getFromMemory 为纯内存态。
class JsBridgeCache {
  final Map<String, String> _disk = <String, String>{};
  final Map<String, dynamic> _memory = <String, dynamic>{};

  /// 存入持久化态（非字符串按 JSON 序列化，对齐桥 cache.put）。
  bool put(String key, Object? value) {
    _disk[key] = value is String ? value : jsonEncode(value);
    return true;
  }

  /// 读取持久化态（能解析成 JSON 则还原对象，对齐桥 cache.get）。
  Object? get(String key) {
    final v = _disk[key];
    if (v == null) return null;
    try {
      return jsonDecode(v);
    } catch (_) {
      return v;
    }
  }

  bool contains(String key) => _disk.containsKey(key);
  void remove(String key) => _disk.remove(key);

  /// 内存态写入：不落盘、不参与 __envelope 回写。
  bool putMemory(String key, Object? value) {
    _memory[key] = value;
    return true;
  }

  /// 内存态读取：仅命中本进程内存，缺省返回 null。
  Object? getFromMemory(String key) => _memory[key];
  void removeMemory(String key) => _memory.remove(key);

  /// 持久化态快照（供运行时回写 SharedPreferences，对齐 __state.kv）。
  Map<String, String> get diskSnapshot => Map<String, String>.unmodifiable(_disk);
}

/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsBridgeSource。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 对齐 source 对象的登录头 / 变量 / 登录信息管理。
class JsBridgeSource {
  JsBridgeSource({required this.url, this.variable = ''});

  final String url;
  String variable;
  String loginInfo = '';
  String loginHeader = '';

  /// 书源地址（对齐 source.getKey / 全局 getKey）。
  String getKey() => url;

  /// 无 key 返回整份变量；有 key 时按 JSON 对象取值（对齐桥 source.getVariable）。
  String getVariable([String? key]) {
    if (key == null || key.isEmpty) return variable;
    try {
      final o = jsonDecode(variable.isEmpty ? '{}' : variable);
      if (o is Map) {
        final v = o[key];
        return v == null ? '' : (v is String ? v : jsonEncode(v));
      }
    } catch (_) {}
    return '';
  }

  /// 写入变量（对象按 JSON 序列化，对齐桥 source.setVariable）。
  String setVariable(Object? v) {
    variable = v is String ? v : jsonEncode(v);
    return variable;
  }

  String getLoginInfo() => loginInfo;

  /// 写入登录信息（对齐桥 source.putLoginInfo）。
  bool putLoginInfo(Object? v) {
    loginInfo = v is String ? v : jsonEncode(v);
    return true;
  }

  /// 登录信息解析为 Map（对齐桥 source.getLoginInfoMap）。
  Map<String, dynamic> getLoginInfoMap() {
    try {
      final o = jsonDecode(loginInfo.isEmpty ? '{}' : loginInfo);
      return o is Map ? Map<String, dynamic>.from(o) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String getLoginHeader() => loginHeader;
  bool putLoginHeader(String header) {
    loginHeader = header;
    return true;
  }
}

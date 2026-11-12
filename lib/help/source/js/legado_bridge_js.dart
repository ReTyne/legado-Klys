/// 注入到无头 WebView（V8）中的 legado 兼容桥。
///
/// （legado/app/src/main/java/io/legado/app/help/JsExtensions.kt
/// 与 AnalyzeUrl / AnalyzeRule）在书源脚本里使用的运行时环境：
///
///   * 全局对象：java / cookie / source / book / cache / result / key / page / baseUrl
///   * java.ajax / get / post / connect —— 以「同步 XHR」实现，由原生
///     shouldInterceptRequest 接管发请求（绕过 CORS、统一 Cookie/编码）。
///   * source.getVariable/setVariable/getLoginInfo/putLoginInfo
///   * cookie.getCookie/setCookie/removeCookie/getKey
///   * cache / java.put / java.get 跨阶段键值
///   * 编码：base64、hex；时间格式化；deviceID/androidId；UA
///   * startBrowser* / showBrowser* / reLoginView —— 走原生可见 WebView 交互登录
///   * 文件：readTxtFile / deleteFile / downloadFile（含 hex 兼容签名）/
///     importScript / cacheFile / getTxtInFolder / readFile / getFile
///     （后两者 JsExtensions，返回 Uint8Array / File-like 对象，
///      路径经 Dart 侧 canonicalPath 白名单校验）
///   * 压缩包：getZipStringContent / get7zStringContent / getRarStringContent /
///     getZipByteArrayContent / get7zByteArrayContent / getRarByteArrayContent /
///     unzipFile / un7zFile / unrarFile / unArchiveFile（7z/rar 走 Android 原生解压）
///   * 字体反爬：queryTTF / queryBase64TTF（后者为 E 已废弃 API 的兼容委托）
///
/// 该脚本在每个书源的无头 WebView 创建后于「全局作用域」执行一次；
/// 书源的 jsLib / loginUrl 随后也在全局作用域执行（定义全局函数）。
///
/// 阅读/主题相关接口（java.getReadBookConfig / getThemeConfig / getThemeMode /
/// getTxtInFolder / openVideoPlayer）在 JS 侧读 `__state` 快照并回退默认值；
/// 原生需要实时数据时，可用本类的 Dart 静态助手生成 JSON 后种子注入
/// `__state.readConfig` / `__state.theme` / `__state.themeMode`。
/// 库声明：承载上方库级文档注释（同时供离线兼容测试读取桥源码做断言）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter/services.dart';

import '../../../constant/app_theme.dart';
import '../../../data/model/read_config.dart';

import 'js_packages.dart';
import 'bridge/parts.dart';

class LegadoBridgeJs {
  /// 注入脚本 = 桥主体 + [JsPackages.definition]（Rhino `Packages.*` 真实映射）
  /// + IIFE 闭合。映射段放在主体末尾，是为了能直接引用桥里已定义好的
  /// java / cookie / cache / __b64Unicode 等工具，而不是恒 null 的死 Proxy。
  static const String code = _codeHead + JsPackages.definition + _codeTail;

  static const String _codeHead = '\n$legadoBridgeJsPart01$legadoBridgeJsPart02$legadoBridgeJsPart03$legadoBridgeJsPart04$legadoBridgeJsPart05$legadoBridgeJsPart06$legadoBridgeJsPart07$legadoBridgeJsPart08';

  /// IIFE 闭合：位于 JsPackages.definition 之后，保证 Packages 在 java /
  /// cookie / __b64Unicode 等全部桥工具就绪后才被定义。
  static const String _codeTail = r'''
})();
''';

  /// 尝试打开原生视频播放器。
  ///
  /// 走 MethodChannel('legado/video') 的 invokeMethod('open', ...)，由
  /// MainActivity 注册的 Kotlin 原生处理器用系统视频播放器打开（K 风格原生实现）。
  /// 平台不支持 / 调用失败时静默返回 false（不抛异常），由调用方降级到内置播放页。
  static Future<bool> openVideoPlayer(String url, String title) async {
    if (url.trim().isEmpty) return false;
    try {
      await const MethodChannel('legado/video')
          .invokeMethod('open', {'url': url, 'title': title});
      return true;
    } catch (e) {
      // 原生通道未实现 / 调用异常：容错降级
      return false;
    }
  }

  /// 列出 [path] 目录下的 .txt 文件（返回绝对路径，按名称排序）。
  /// 目录不存在 / 无权限 / IO 异常时返回空列表，不抛异常。
  static List<String> txtFilesInFolder(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return const [];
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.txt'))
          .map((f) => f.path)
          .toList()
        ..sort();
      return files;
    } catch (e) {
      return const [];
    }
  }

  /// ReadConfig 关键字段 JSON（对齐 JS 桥 java.getReadBookConfig 的返回结构）。
  static String readConfigJson(ReadConfig config) {
    return jsonEncode({
      'textSize': config.textSize,
      'textColor': config.textColor,
      'fontFamily': config.fontFamily ?? '',
      'fontWeight': config.fontWeight,
      'textAlign': config.textAlign,
      'lineSpacing': config.lineSpacing,
      'paragraphSpacing': config.paragraphSpacing,
      'paddingLeft': config.paddingLeft,
      'paddingRight': config.paddingRight,
      'paddingTop': config.paddingTop,
      'paddingBottom': config.paddingBottom,
      'bgColor': config.bgColor,
      'pageAnim': config.pageAnim,
      'chineseConverter': config.chineseConverter,
    });
  }

  /// 主题配置 JSON（对齐 JS 桥 java.getThemeConfig 的返回结构）。
  static String themeConfigJson(AppTheme theme) {
    final modeIndex = theme.themeMode.index;
    var isDark = modeIndex == 2;
    if (modeIndex == 0) {
      isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
    return jsonEncode({
      'isDark': isDark,
      'themeMode': modeIndex,
      'seedColor': theme.seedColor.value,
      'fontFamily': theme.fontFamily,
      'fontScale': theme.fontScale,
      'dynamicColor': theme.dynamicColor,
      'amoled': theme.amoled,
      'eink': theme.eink,
      'foregroundOpacity': theme.foregroundOpacity,
    });
  }

  /// 主题模式索引：0 跟随系统 / 1 浅色 / 2 深色（与 prefs theme_mode 存储一致）。
  static int themeModeIndex(AppTheme theme) => theme.themeMode.index;
}

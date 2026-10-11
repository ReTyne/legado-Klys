import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// 轻量崩溃/异常日志：捕获 Flutter 框架异常与 Zone 异常，落盘 crash.log（最多保留最近 200 行/约 64KB）
class CrashLogHelper {
  CrashLogHelper._();
  static final CrashLogHelper instance = CrashLogHelper._();

  static const String _fileName = 'crash.log';
  static const int _maxBytes = 64 * 1024;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 在 app 启动时安装：拦截 Flutter 框架错误与异步 Zone 错误
  void install() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previousOnError?.call(details);
      record(details.exceptionAsString(), details.stack?.toString());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error.toString(), stack.toString());
      return true;
    };
  }

  Future<void> record(String error, [String? stack]) async {
    try {
      final f = await _file();
      final ts = DateTime.now().toIso8601String();
      final entry = '===== $ts =====\n$error\n${stack ?? ''}\n\n';
      var old = f.existsSync() ? f.readAsStringSync() : '';
      old = entry + old;
      if (old.length > _maxBytes) old = old.substring(0, _maxBytes);
      f.writeAsStringSync(old);
    } catch (_) {}
  }

  Future<String> readLogs() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return '';
      return f.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}

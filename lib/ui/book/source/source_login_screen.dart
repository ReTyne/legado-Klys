import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/source_network_log.dart';
import 'package:legado_md3/help/source/source_server_probe.dart';
import 'package:legado_md3/ui/book/source/source_webview_login_screen.dart';

import 'package:legado_md3/ui/widgets/app_common.dart';
import 'package:legado_md3/ui/widgets/flex_fillet.dart';
import 'package:legado_md3/ui/theme/app_design.dart';
part 'parts/source_login_screen_state.dart';
part 'parts/login_button.dart';


/// 书源登录页：
/// SourceLoginActivity / WebViewLoginFragment / SourceLoginDialog。
///
/// * loginUrl 为 http(s) 且无自定义 loginUi：进入 [SourceWebViewLoginScreen]
///   做 WebView 登录（注入 header/UA、拦截 URL、回收 Cookie 回写书源，供网络层与 JS 消费）。
/// * loginUrl 为 <js>/JS：按 loginUi 渲染 text/password/button/switch/select，
///   loginUrl 先求值（定义 login()/register() 等全局函数），按钮 action 再求值；
///   result 为「字段名 -> 值」的对象，登录信息经 putLoginInfo 持久化。
/// * loginUi 为 `@js:` / `<js>`：先求值生成表单 JSON。
/// * 无 loginUi：回退为账号/密码表单，写入书源变量。
/// * 页面加载时执行书源 loginCheckJs，展示「已登录/未登录」状态；
///   AppBar 菜单 source_login.xml（查看/清除登录头、运行日志）。
class SourceLoginScreen extends StatefulWidget {
  const SourceLoginScreen({super.key, required this.source});
  final BookSource source;

  @override
  State<SourceLoginScreen> createState() => _SourceLoginScreenState();
}

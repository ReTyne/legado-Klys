/// 由 source_login_screen.dart 按「一类一文件」拆出的 _SourceLoginScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_login_screen.dart';


/// 登录 UI 条目类型。
enum _LoginItemType { input, button }

/// 单个登录 UI 条目的有序渲染单元：顺序与书源 loginUi 完全一致，
/// 仅按类型在 [_layoutLoginItems] 中做视觉分组（卡片/网格），不改相对顺序。
class _LoginItem {
  const _LoginItem({
    required this.type,
    required this.raw,
    this.widget,
    this.flexBasisPercent = 0.4,
  });
  final _LoginItemType type;
  final Map<String, dynamic> raw;
  final Widget? widget;
  final double flexBasisPercent;
}


class _SourceLoginScreenState extends State<SourceLoginScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final Map<String, TextEditingController> _controllers = {};
  // 所有创建过的 controller（动态 loginUi 重建表单时统一释放，避免泄漏）
  final List<TextEditingController> _allControllers = [];
  // switch 开关控件的勾选值（字段名 -> bool）
  final Map<String, bool> _switchValues = {};
  // select 下拉控件的选中值（字段名 -> 选项 value）
  final Map<String, String> _selectValues = {};
  final List<_LoginItem> _loginItems = [];
  final List<String> _logs = [];
  bool _busy = false;
  // loginCheckJs 登录状态检测：null=未配置/未知，true=已登录，false=未登录
  bool _checkingLogin = false;
  bool? _loggedIn;

  /// 表单草稿：所有控件（输入框 / 开关 / 下拉）的当前值，供重建表单时回填。
  /// 刷新、动态 loginUi 重建都不会清空它，因此输入内容得以保留。
  final Map<String, String> _draftForm = <String, String>{};
  /// 上一次「保存」落盘的快照，用于判断是否有未保存改动。
  Map<String, String> _persistedForm = <String, String>{};
  bool _saving = false;

  late BookSource source;

  String get _formKey => 'loginForm_${source.bookSourceUrl}';

  /// 当前全部控件值（字符串化），用于持久化与改动比较。
  Map<String, String> get _currentForm => <String, String>{
        for (final e in _controllers.entries) e.key: e.value.text,
        for (final e in _switchValues.entries) e.key: e.value.toString(),
        for (final e in _selectValues.entries) e.key: e.value.toString(),
      };

  bool get _hasUnsavedChanges {
    final cur = _currentForm;
    if (cur.length != _persistedForm.length) return true;
    for (final e in cur.entries) {
      if (_persistedForm[e.key] != e.value) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    source = widget.source;
    _buildUi();
    // 恢复上次保存的输入内容（退出再进来仍存在），随后再求值动态 loginUi
    _restoreForm();
    // 页面加载时检测登录状态（loginCheckJs）
    _checkLoginStatus();
  }

  /// 从本地存储读回上次保存的表单，并重建控件让保存值显示出来。
  /// 无论是否读到保存值，最后都触发一次动态 loginUi 求值，保证草稿回填。
  Future<void> _restoreForm() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_formKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final saved = decoded.map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          _draftForm
            ..clear()
            ..addAll(saved);
          _persistedForm = Map<String, String>.from(saved);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    // 静态 loginUi 立即可重建；动态 loginUi 交给 _maybeLoadDynamicUi。
    if (_extractLoginUiJs((source.loginUi ?? '').trim()) == null) {
      setState(_rebuildFields);
    }
    await _maybeLoadDynamicUi();
  }

  /// 只重建控件列表，不清空草稿（刷新 / 动态表单 / 恢复保存值共用）。
  /// 新控件的初始值从 [_draftForm] 读取，因此输入内容不会丢失。
  void _rebuildFields() {
    _loginItems.clear();
    _controllers.clear();
    _switchValues.clear();
    _selectValues.clear();
    final items = _loginItemsOriginal.isNotEmpty
        ? List<dynamic>.from(_loginItemsOriginal)
        : _fallbackLoginUi;
    _buildFields(items);
  }

  /// 保存最近一次成功解析的 loginUi 条目，供重建使用。
  final List<dynamic> _loginItemsOriginal = <dynamic>[];

  /// 保存表单输入、Cookie 与登录信息，退出再进入仍然存在。
  Future<void> _saveAll({bool showHint = true}) async {
    if (_saving) return;
    _saving = true;
    try {
      final cur = _currentForm;
      _draftForm
        ..clear()
        ..addAll(cur);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_formKey, jsonEncode(cur));
      _persistedForm = Map<String, String>.from(cur);
      // 把当前 JS 运行时的 Cookie 与登录信息一并落盘：登录动作写入的
      // qttoken 等 Cookie 需要跨「保存 / 退出 / 重进」保留。
      await _flushLoginState();
      if (mounted) setState(() {});
      if (showHint && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('已保存输入内容与登录状态'),
            duration: Duration(seconds: 2)));
      }
    } finally {
      _saving = false;
    }
  }

  /// 刷新页面：重载 JS 运行时并重建表单，但保留当前输入内容。
  Future<void> _reloadUi() async {
    await JsRuntimeManager.instance.invalidate(source.bookSourceUrl);
    if (!mounted) return;
    final dynamicUi = _extractLoginUiJs((source.loginUi ?? '').trim()) != null;
    setState(() {
      _logs.clear();
      _rebuildFields();
    });
    if (dynamicUi) await _maybeLoadDynamicUi();
    await _checkLoginStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已刷新，输入内容已保留'),
          duration: Duration(seconds: 2)));
    }
  }

  /// 让 JS 运行时把当前会话 Cookie / 登录信息回写数据库。
  /// 走一次轻量求值即可触发桥的 cookie 回收，不执行任何书源动作。
  Future<void> _flushLoginState() async {
    try {
      await JsRuntimeManager.instance.invalidate(source.bookSourceUrl);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = source.bookSourceUrl;
      final loginInfo = prefs.getString('loginInfo_$key');
      if (loginInfo == null || loginInfo.isEmpty) {
        // 未显式写入 loginInfo 时，用表单内容作为兜底，保证书源
        // `source.getLoginInfo()` 能读到用户填的账号信息。
        await prefs.setString('loginInfo_$key', jsonEncode(_draftForm));
      }
    } catch (_) {}
  }

  /// 返回确认：有未保存改动时询问是否保存。
  Future<bool> _confirmExit() async {
    if (!_hasUnsavedChanges) return true;
    if (!mounted) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('输入内容与登录状态尚未保存，是否保存后返回？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'discard'),
              child: const Text('不保存')),
          TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'save'),
              child: const Text('保存')),
        ],
      ),
    );
    if (choice == 'cancel' || choice == null) return false;
    if (choice == 'save') await _saveAll(showHint: false);
    return true;
  }

  /// 调用书源 loginCheckJs 检测登录状态并刷新界面提示
  Future<void> _checkLoginStatus() async {
    // 未配置 loginCheckJs 时不显示状态
    if ((source.loginCheckJs ?? '').trim().isEmpty) return;
    if (mounted) setState(() => _checkingLogin = true);
    var ok = false;
    try {
      ok = await _engine.checkLogin(source);
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() { _loggedIn = ok; _checkingLogin = false; });
  }

  void _buildUi() {
    final loginUrl = (source.loginUrl ?? '').trim();
    final uiText = (source.loginUi ?? '').trim();
    // 仅当没有自定义 loginUi 且 loginUrl 为
    // http(s) 时才自动进入 WebView；有 loginUi 时优先渲染自定义登录表单。
    if (uiText.isEmpty &&
        (loginUrl.startsWith('http://') || loginUrl.startsWith('https://'))) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openWebLogin(loginUrl));
      return;
    }
    // 动态 loginUi：先留空，由 _maybeLoadDynamicUi 求值后重建
    if (_extractLoginUiJs(uiText) != null) return;
    List<dynamic> items = [];
    if (uiText.isNotEmpty) {
      try {
        final decoded = jsonDecode(uiText);
        if (decoded is List) items = decoded;
      } catch (_) {
        items = [];
      }
    }
    if (items.isEmpty) {
      // 回退：账号/密码
      items = _fallbackLoginUi;
    }
    _buildFields(items);
  }

  static const List<Map<String, dynamic>> _fallbackLoginUi = [
    {'name': '用户名', 'type': 'text'},
    {'name': '密码', 'type': 'password'},
    {'name': '登录', 'type': 'button', 'action': 'login(true)'},
  ];

  /// loginUi 为 `@js:` / `<js>...</js>` 时先求值生成表单 JSON，再重建控件。
  Future<void> _maybeLoadDynamicUi() async {
    final raw = (source.loginUi ?? '').trim();
    final code = _extractLoginUiJs(raw);
    if (code == null) return;
    List<dynamic> items = _fallbackLoginUi;
    try {
      final rt = await JsRuntimeManager.instance.forSource(source);
      final res = await rt.eval(JsEvalRequest(
        source: source,
        script: code,
        result: _form,
        baseUrl: source.bookSourceUrl.startsWith('http')
            ? source.bookSourceUrl
            : '',
      ));
      final dynamic value = res.value;
      if (value is List) {
        // JS 直接返回 RowUi 数组
        items = value;
      } else {
        // evalUiJs 用 toString() 得到 JSON 字符串再解析
        final jsonStr = (res.stringValue ?? '').trim();
        if (jsonStr.isNotEmpty) {
          final decoded = jsonDecode(jsonStr);
          if (decoded is List) items = decoded;
        }
      }
    } catch (e) {
      _appendLog('动态 loginUi 求值失败，已回退：$e');
    }
    if (!mounted) return;
    setState(() {
      _clearFields();
      _buildFields(items);
    });
  }

  /// 提取 loginUi 里的 JS
  String? _extractLoginUiJs(String raw) {
    if (raw.startsWith('@js:')) return raw.substring(4);
    if (raw.startsWith('<js>')) {
      final end = raw.lastIndexOf('</js>');
      return raw.substring(4, end > 4 ? end : raw.length);
    }
    return null;
  }

  void _clearFields() {
    _loginItems.clear();
    _controllers.clear();
    _switchValues.clear();
    _selectValues.clear();
  }

  /// 单个登录 UI 条目（保留书源 loginUi 的原始顺序，仅按类型分组渲染）。
  /// - text/password/switch/select 直接携带已构建的控件；
  /// - button 携带 action 与 flexBasisPercent，由网格布局 Flexbox 规则排布。
  _LoginItem _mkInput(Map<String, dynamic> item, Widget widget) =>
      _LoginItem(type: _LoginItemType.input, raw: item, widget: widget);

  _LoginItem _mkButton(Map<String, dynamic> item) => _LoginItem(
        type: _LoginItemType.button,
        raw: item,
        flexBasisPercent: _flexBasisPercentOf(item),
      );

  /// 解析书源 style.layout_flexBasisPercent。
  /// 委托共享实现，登录页与发现页使用同一套分行规则。
  static double _flexBasisPercentOf(Map<String, dynamic> raw) =>
      flexBasisPercentOf(raw['style']);

  /// 依据 loginUi 条目构建有序列表（顺序与书源完全一致）。
  void _buildFields(List<dynamic> items) {
    _loginItemsOriginal
      ..clear()
      ..addAll(items);
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final name = item['name']?.toString() ?? '';
      final type = item['type']?.toString() ?? 'text';
      if (type == 'button') {
        _loginItems.add(_mkButton(item));
      } else if (type == 'switch') {
        final name0 = name.isEmpty ? '开关' : name;
        final draft = _draftForm[name0];
        final value = draft != null
            ? (draft == 'true' || draft == '1')
            : (_switchValues[name0] ?? false);
        _switchValues[name0] = value;
        _draftForm[name0] = value.toString();
        _loginItems.add(_mkInput(
          item,
          SwitchListTile(
            title: Text(name0),
            value: value,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() {
              _switchValues[name0] = v;
              _draftForm[name0] = v.toString();
            }),
          ),
        ));
      } else if (type == 'select') {
        final name0 = name.isEmpty ? '请选择' : name;
        final options = _parseSelectOptions(item['options']);
        if (options.isNotEmpty) {
          final draft = _draftForm[name0];
          final valid = options.any((o) => o['value'] == draft);
          final current = valid
              ? draft!
              : (_selectValues[name0] ?? options.first['value']!);
          _selectValues[name0] = current;
          _draftForm[name0] = current;
          _loginItems.add(_mkInput(
            item,
            DropdownButtonFormField<String>(
              value: current,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: name0,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
              ),
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o['value'],
                        child: Text(o['name'] ?? o['value'] ?? ''),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectValues[name0] = v;
                    _draftForm[name0] = v;
                  });
                }
              },
            ),
          ));
        }
      } else if (type == 'text' || type == 'password' || type.isEmpty) {
        final c = TextEditingController(text: _draftForm[name] ?? '');
        _draftForm[name] = c.text;
        c.addListener(() {
          _draftForm[name] = c.text;
        });
        _controllers[name] = c;
        _allControllers.add(c);
        _loginItems.add(_mkInput(
          item,
          TextField(
            controller: c,
            obscureText: type == 'password',
            decoration: InputDecoration(
              labelText: name,
              border: const OutlineInputBorder(),
              prefixIcon: Icon(type == 'password'
                  ? Icons.lock_outline
                  : Icons.person_outline),
            ),
          ),
        ));
      }
    }
  }

  /// 把有序条目按「连续同类」分组为区块：
  /// - 连续的输入框(switch/select/text/password) 收进同一张「账号/自定义设置」卡片；
  /// - 连续的按钮收进同一张弹性网格（按 flexBasisPercent 排布，还原原版规则排序）。
  /// 不改变条目相对顺序，仅做视觉分组，避免“顺序对却像乱排”。
  List<Widget> _layoutLoginItems() {
    final out = <Widget>[];
    final inputRun = <_LoginItem>[];
    final btnRun = <_LoginItem>[];
    var firstInputRunSeen = false;

    void flushInput() {
      if (inputRun.isEmpty) return;
      final label = firstInputRunSeen ? '自定义设置' : '账号信息';
      // 传副本：_inputCard 同步快照控件，清空本地 run 不影响已构建控件
      out.add(_inputCard(List<_LoginItem>.from(inputRun), label));
      firstInputRunSeen = true;
      inputRun.clear();
    }

    void flushButtons() {
      if (btnRun.isEmpty) return;
      // 传副本！_buttonGrid 用懒执行的 LayoutBuilder，若直接传 btnRun 引用，
      // 下面的 btnRun.clear() 会在布局时才清空列表，导致按钮全部消失。
      out.add(_buttonGrid(List<_LoginItem>.from(btnRun)));
      btnRun.clear();
    }

    for (final it in _loginItems) {
      if (it.type == _LoginItemType.button) {
        flushInput();
        btnRun.add(it);
      } else {
        flushButtons();
        inputRun.add(it);
      }
    }
    flushInput();
    flushButtons();
    return out;
  }

  /// 账号/自定义设置卡片：连续输入框聚合成一组，带分区标题。
  Widget _inputCard(List<_LoginItem> run, String label) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.primary)),
            const SizedBox(height: AppSpacing.s),
            for (final it in run) ...[
              it.widget!,
              if (it != run.last) const SizedBox(height: AppSpacing.s),
            ],
          ],
        ),
      ),
    );
  }

  /// 弹性按钮网格： FlexboxLayoutManager，按 flexBasisPercent
  /// 累加分行、每行铺满（layout_flexGrow=1），>=0.95 独占整行。
  /// 统一 fillet 样式，不再三色分级；每行两侧齐平，中文标签更少被截断。
  Widget _buttonGrid(List<_LoginItem> run) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: FlexPercentLayout(
        percents: run.map((it) => it.flexBasisPercent).toList(),
        children: run
            .map((it) => _LoginButton(
                  label: it.raw['name']?.toString() ?? '按钮',
                  busy: _busy,
                  onPressed: () =>
                      _runAction(it.raw['action']?.toString() ?? ''),
                ))
            .toList(),
      ),
    );
  }

  /// 书源更新日志 / 使用说明：默认折叠，置于底部，不再占据表单顶部。
  Widget _buildCommentCard() {
    final cs = Theme.of(context).colorScheme;
    final comment = (source.bookSourceComment ?? '').trim();
    if (comment.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.m),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.info_outline, size: 20),
          title: const Text('使用说明 / 更新日志',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l, 0, AppSpacing.l, AppSpacing.m),
              child: SelectableText(
                comment,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 表单值：文本框 + switch + select 的当前值，作为 JS action 的 result
  Map<String, dynamic> get _form {
    final m = <String, dynamic>{};
    _controllers.forEach((k, c) => m[k] = c.text);
    m.addAll(_switchValues);
    m.addAll(_selectValues);
    return m;
  }

  /// 解析 select 控件的 options：支持字符串数组或 [{name, value}] 对象数组
  List<Map<String, String>> _parseSelectOptions(dynamic raw) {
    final out = <Map<String, String>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String) {
          if (e.isNotEmpty) out.add({'name': e, 'value': e});
        } else if (e is Map) {
          final name = (e['name'] ?? e['value'] ?? '').toString();
          final value = (e['value'] ?? e['name'] ?? '').toString();
          if (name.isNotEmpty || value.isNotEmpty) {
            out.add({'name': name, 'value': value});
          }
        }
      }
    }
    return out;
  }

  /// 打开 WebView 登录并打通闭环。
  /// 新页完成登录时已把 Cookie 回写内存 CookieJar、cookies 表并开启
  /// enabledCookieJar；这里 await 结果后让 JS 运行时重新读取会话 Cookie，
  /// 再刷新 loginCheckJs 状态，网络层下一次请求即自动携带登录 Cookie。
  Future<void> _openWebLogin(String url) async {
    final result = await Navigator.of(context).push<SourceWebLoginResult>(
      MaterialPageRoute(
        builder: (_) =>
            SourceWebViewLoginScreen(source: source, loginUrl: url),
      ),
    );
    if (!mounted) return;
    await JsRuntimeManager.instance.invalidate(source.bookSourceUrl);
    await _checkLoginStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result == null
          ? '已取消网页登录'
          : result.cookieCount > 0
              ? '登录完成：已回写 ${result.cookieCount} 项 Cookie，书源请求与 JS 将自动携带'
              : '登录完成：未检测到 Cookie（可能已登录或该源无需 Cookie）'),
      duration: const Duration(seconds: 3),
    ));
  }

  /// 查看登录头 / 登录信息
  Future<void> _showLoginHeader() async {
    final key = source.bookSourceUrl;
    final prefs = await SharedPreferences.getInstance();
    final loginInfo = prefs.getString('loginInfo_$key') ?? '';
    final loginHeader = prefs.getString('loginHeader_$key') ?? '';
    final dbCookie = await _db.getCookie(key) ?? '';
    final memCookie = CookieManager().cookieHeader(
            key.startsWith('http') ? key : 'https://$key/') ??
        '';
    final parts = <String>[
      '书源 Header：${(source.header ?? '').isEmpty ? '无' : source.header}',
      '登录信息 loginInfo：${loginInfo.isEmpty ? '无' : loginInfo}',
      '登录头 loginHeader：${loginHeader.isEmpty ? '无' : loginHeader}',
      '持久化 Cookie(DB)：${dbCookie.isEmpty ? '无' : dbCookie}',
      '内存 Cookie：${memCookie.isEmpty ? '无' : memCookie}',
    ];
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('登录头 / 登录信息'),
        content: SingleChildScrollView(
          child: SelectableText(parts.join('\n\n'),
              style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('关闭')),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: parts.join('\n')));
              if (c.mounted) Navigator.pop(c);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制')));
              }
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  /// 清除登录头 / 登录信息 / Cookie
  Future<void> _clearLoginHeader() async {
    final key = source.bookSourceUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loginInfo_$key');
    await prefs.remove('loginHeader_$key');
    await _db.deleteCookie(key);
    try {
      final host = Uri.tryParse(key)?.host ?? '';
      if (host.isNotEmpty) CookieManager().removeHost(host);
    } catch (_) {}
    await JsRuntimeManager.instance.invalidate(key);
    await _checkLoginStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已清除登录头、登录信息与持久化 Cookie')));
    }
  }

  /// 运行日志
  void _showLogs() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('运行日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              _logs.isEmpty ? '暂无日志' : _logs.join('\n'),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('关闭')),
          TextButton(
            onPressed: () {
              setState(() => _logs.clear());
              Navigator.pop(c);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  /// 诊断书源内置备用服务器，并在默认服务器 502 / 不可用时一键切换。
  /// 不依赖书源 JS 自身的「切换服务器」按钮，避免服务器挂掉时连诊断都跑不了。
  Future<void> _showServerDiagnostics() async {
    final hosts = SourceServerProbe.extractHosts(source);
    if (hosts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该书源未内置备用服务器列表')));
      }
      return;
    }
    final current = SourceServerProbe.currentServer(source);
    final future = SourceServerProbe.probeAll(hosts);
    await showDialog<void>(
      context: context,
      builder: (c) {
        var applying = false;
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('服务器诊断 / 切换'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.isEmpty ? '当前：书源默认服务器' : '当前：$current',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    FutureBuilder<List<ServerProbeResult>>(
                      future: future,
                      builder: (_, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const AppLoadingIndicator(compact: true);
                        }
                        if (snap.hasError) {
                          return Text('诊断失败：${snap.error}',
                              style: TextStyle(color: cs.error));
                        }
                        final results =
                            snap.data ?? const <ServerProbeResult>[];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final r in results)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  r.unhealthy || !r.reachable
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                  size: 18,
                                  color: r.unhealthy || !r.reachable
                                      ? cs.error
                                      : cs.primary,
                                ),
                                title: Text(r.host,
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'monospace')),
                                subtitle: Text(
                                    '${r.label} · ${r.latencyMs}ms'
                                    '${r.error != null ? '\n${r.error}' : ''}',
                                    style: const TextStyle(fontSize: 10)),
                                trailing: TextButton(
                                  onPressed: applying
                                      ? null
                                      : () async {
                                          setDialogState(
                                              () => applying = true);
                                          await SourceServerProbe.applyServer(
                                              source, r.host, _db);
                                          if (ctx.mounted) {
                                            Navigator.of(ctx).pop();
                                          }
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                              content: Text(
                                                  '已切换服务器为 ${r.host}，请重新登录或刷新'),
                                              duration:
                                                  const Duration(seconds: 4),
                                            ));
                                          }
                                        },
                                  child: const Text('使用'),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(c).pop(),
                  child: const Text('关闭')),
            ],
          );
        });
      },
    );
  }

  Future<void> _runAction(String action) async {
    final act = action.trim();
    if (act.isEmpty) return;
    // 只记录本次动作产生的网络请求，避免把上一次的失败带进诊断
    SourceNetworkLog.instance.clear();
    setState(() => _busy = true);
    _appendLog('执行: $act');
    for (final e in SourceNetworkLog.instance.scriptErrors) {
      _appendLog('脚本加载: $e');
    }
    try {
      final rt = await JsRuntimeManager.instance.forSource(source);
      // 登录按钮以表单对象作为 result
      final res = await rt.eval(JsEvalRequest(
        source: source,
        script: act,
        result: _form,
        baseUrl: source.bookSourceUrl.startsWith('http')
            ? source.bookSourceUrl
            : '',
      ));
      for (final t in res.toasts) {
        _appendLog(t);
      }
      for (final l in res.logs) {
        _appendLog(l);
      }
      if (res.error != null && res.error!.isNotEmpty) {
        _appendLog('异常: ${res.error!.split('\n').first}');
      }
      // 把底层真实网络失败写进运行日志：书源常把所有异常都伪装成
      // "HTTP 502"，这里额外给出请求 URL 与原始错误，便于判断是服务端
      // 故障还是本机网络问题。
      final netFail = SourceNetworkLog.instance.lastFailure;
      if (netFail != null) {
        _appendLog('网络失败: ${netFail.method} ${netFail.statusLabel} ${netFail.url}');
        if (netFail.error != null) _appendLog('原因: ${netFail.error}');
      }
      // variable 在求值过程中可能被 setVariable 更新，落库
      await _db.updateSource(source);
      // 登录动作可能改变登录状态，重新检测 loginCheckJs
      await _checkLoginStatus();
      if (mounted) {
        final lastToast = res.toasts.isNotEmpty ? res.toasts.last : null;
        final serverDown =
            netFail != null && (netFail.statusCode ?? 0) >= 500;
        final hint = serverDown
            ? '\n服务器返回 ${netFail.statusCode}，点右上角「服务器诊断」切换备用服务器'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${lastToast ?? '操作已完成'}$hint'),
          duration: Duration(seconds: serverDown ? 5 : 2),
        ));
      }
    } catch (e) {
      _appendLog('运行失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _appendLog(String s) {
    final line = s.trim();
    if (line.isEmpty) return;
    setState(() {
      _logs.add(line);
      if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    });
  }

  /// 登录状态横幅：展示 loginCheckJs 检测结果（已登录/未登录），支持手动刷新
  Widget _loginStatusBanner() {
    // 未配置 loginCheckJs 时不展示
    if ((source.loginCheckJs ?? '').trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final ok = _loggedIn == true;
    final color = _checkingLogin
        ? cs.onSurfaceVariant
        : (ok ? cs.primary : cs.error);
    final text = _checkingLogin ? '正在检测登录状态…' : (ok ? '已登录' : '未登录');
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: AppRadius.mAll,
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          _checkingLogin
              ? Icons.hourglass_empty
              : (ok ? Icons.verified_user : Icons.error_outline),
          color: color,
        ),
        title: Text(
          '登录状态：$text',
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: const Text('由 loginCheckJs 检测', style: TextStyle(fontSize: 11)),
        trailing: IconButton(
          tooltip: '重新检测',
          icon: const Icon(Icons.refresh_outlined, size: 20),
          onPressed: _checkingLogin ? null : _checkLoginStatus,
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loginUrl = (source.loginUrl ?? '').trim();
    final isWeb = loginUrl.startsWith('http') &&
        (source.loginUi ?? '').trim().isEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmExit();
        if (!ok || !mounted) return;
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('登录 - ${source.bookSourceName}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // 有自定义 loginUi 且 loginUrl 为网页时，仍保留 WebView 登录入口
          if (!isWeb && loginUrl.startsWith('http'))
            IconButton(
              tooltip: '网页登录',
              icon: const Icon(Icons.open_in_browser_outlined),
              onPressed: () => _openWebLogin(loginUrl),
            ),
          // 刷新与服务器切换统一收进三点菜单，避免顶栏图标拥挤。
          PopupMenuButton<String>(
            tooltip: '更多功能',
            onSelected: (v) {
              switch (v) {
                case 'reload':
                  _reloadUi();
                  break;
                case 'server':
                  _showServerDiagnostics();
                  break;
                case 'web_login':
                  _openWebLogin(loginUrl);
                  break;
                case 'show_header':
                  _showLoginHeader();
                  break;
                case 'clear_header':
                  _clearLoginHeader();
                  break;
                case 'logs':
                  _showLogs();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'reload', child: Text('刷新页面（保留输入）')),
              const PopupMenuItem(
                  value: 'server', child: Text('切换服务器 / 诊断')),
              if (!isWeb && loginUrl.startsWith('http'))
                const PopupMenuItem(
                    value: 'web_login', child: Text('网页登录')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'show_header', child: Text('查看登录头 / 登录信息')),
              const PopupMenuItem(
                  value: 'clear_header', child: Text('清除登录头 / Cookie')),
              const PopupMenuItem(value: 'logs', child: Text('运行日志')),
            ],
          ),
          // 原刷新位置改为「保存」：持久化输入内容、Cookie 与登录信息。
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
            onPressed: _busy || _saving ? null : () => _saveAll(),
          ),
        ],
      ),
      body: isWeb
          ? Column(
              children: [
                const SizedBox(height: AppSpacing.s),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                  child: _loginStatusBanner(),
                ),
                Expanded(
                  child: Center(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('打开网页登录'),
                      onPressed: () => _openWebLogin(loginUrl),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    children: [
                      // 登录状态检测横幅（loginCheckJs）
                      _loginStatusBanner(),
                      // 按书源 loginUi 顺序分组渲染：账号卡片 / 按钮网格 / 自定义设置卡片
                      ..._layoutLoginItems(),
                      const Divider(height: 32),
                      if (_logs.isNotEmpty) ...[
                        const Text('运行日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.s),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: AppRadius.mAll,
                          ),
                          child: SelectableText(
                            _logs.join('\n'),
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                      // 书源更新日志 / 使用说明：默认折叠，置于底部
                      _buildCommentCard(),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

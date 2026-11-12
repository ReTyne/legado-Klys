import 'package:flutter/material.dart';

import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 封面配置页面 -  CoverConfigFragment。
///
/// 取舍结论（对照 `pref_config_cover.xml` 的 6 项下线配置）：
/// 保留 4 项「有真实消费方」的设置（cover_onlyWifi / bs_coverShadow /
/// cover_showName / cover_showAuthor）；其余 6 项**从 UI 与模型一并下线**：
/// coverRule / useDefaultCover / defaultCover / defaultCoverDark /
/// coverShowNameN / coverShowAuthorN。原因是书架统一改用 `DefaultCover` /
/// `BookCover` 固定色表 + MD3 单主题，无昼夜双套封面配色，这些项既无渲染
/// 消费方也无独立语义，继续暴露即为死开关。页面提供「清理残留配置」动作，
/// 真实删除历史遗留的 SharedPreferences 键，而非只留文字说明。
class CoverConfigScreen extends StatefulWidget {
  const CoverConfigScreen({super.key});

  @override
  State<CoverConfigScreen> createState() => _CoverConfigScreenState();
}

class _CoverConfigScreenState extends State<CoverConfigScreen> {
  bool _onlyWifi = false;
  bool _coverShadow = true;
  bool _showName = true;
  bool _showAuthor = true;

  /// 由 NetworkMonitor.isWifi（原生 ConnectivityManager）精确判断。
  static const String _onlyWifiNote =
      '移动数据下不加载网络封面，改用默认封面（Android 原生判断）';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    AppPrefs.loadFrom(p);
    if (!mounted) return;
    setState(() {
      _onlyWifi = p.getBool('cover_onlyWifi') ?? false;
      _coverShadow = p.getBool('bs_coverShadow') ?? true;
      _showName = AppPrefs.coverShowName;
      _showAuthor = AppPrefs.coverShowAuthor;
    });
  }

  Future<void> _setBool(String key, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
  }

  /// 已下线的封面配置键（历史遗留，可能仍写在本机 SharedPreferences 中）。
  static const List<String> _retiredKeys = <String>[
    'coverRule',
    'cover_useDefault',
    'cover_defaultColor',
    'cover_dayTextColor',
    'cover_nightTextColor',
    'cover_showNameN',
    'cover_showAuthorN',
  ];

  /// 真实清理：删除 6 项下线配置对应的残留键，避免「字段已从模型删除但仍占存储」。
  Future<void> _purgeLegacyKeys() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '清理残留封面配置',
      content: '将删除 ${_retiredKeys.length} 个已下线且无消费方的旧封面配置键。',
      confirmText: '清理',
    );
    if (!ok) return;
    final p = await SharedPreferences.getInstance();
    for (final key in _retiredKeys) {
      await p.remove(key);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理 ${_retiredKeys.length} 个残留配置键')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('封面配置')),
      body: ListView(
        children: [
          AppSettingsGroup(
            title: '网络封面',
            children: [
              AppSwitchTile(
                title: '仅 WiFi 下加载网络封面',
                subtitle: _onlyWifiNote,
                value: _onlyWifi,
                onChanged: (v) {
                  setState(() => _onlyWifi = v);
                  _setBool('cover_onlyWifi', v);
                },
              ),
              AppSwitchTile(
                title: '封面显示阴影',
                subtitle: '书架封面阴影（bs_coverShadow）',
                value: _coverShadow,
                onChanged: (v) {
                  setState(() => _coverShadow = v);
                  _setBool('bs_coverShadow', v);
                },
              ),
            ],
          ),
          AppSettingsGroup(
            title: '封面文字',
            children: [
              AppSwitchTile(
                title: '显示书名',
                subtitle: '无封面占位上叠加书名（cover_showName）',
                value: _showName,
                onChanged: (v) {
                  setState(() => _showName = v);
                  AppPrefs.coverShowName = v;
                },
              ),
              AppSwitchTile(
                title: '显示作者',
                subtitle: '无封面占位上叠加作者（cover_showAuthor）',
                value: _showAuthor,
                onChanged: (v) {
                  setState(() => _showAuthor = v);
                  AppPrefs.coverShowAuthor = v;
                },
              ),
            ],
          ),
          AppSettingsGroup(
            title: '已下线配置（取舍说明）',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
                child: Text(
                  '下列 6 项已从 UI 与模型下线（无消费方 / MD3 单主题无昼夜配色）：\n'
                  '1. coverRule —— 封面 JS 规则，无渲染消费方\n'
                  '2. useDefaultCover(cover_useDefault) —— 书架统一用 DefaultCover\n'
                  '3. defaultCover(cover_defaultColor) —— 固定色表，无自定义底色\n'
                  '4. defaultCoverDark(cover_nightTextColor) —— 无夜间文字色语义\n'
                  '5. coverShowNameN(cover_showNameN) —— 合并到 cover_showName\n'
                  '6. coverShowAuthorN(cover_showAuthorN) —— 合并到 cover_showAuthor',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.6),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('清理残留的旧封面配置'),
                subtitle: const Text('删除上述已下线的 SharedPreferences 键',
                    style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _purgeLegacyKeys,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }
}

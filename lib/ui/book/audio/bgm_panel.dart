import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:legado_md3/help/bgm/bgm_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 从阅读页 / 音频页唤起 BGM 面板的统一入口。
///
/// 阅读页（C 组）只需 `import 'package:legado_md3/ui/book/audio/bgm_panel.dart';`
/// 然后 `showBgmPanel(context)` 即可，无需了解 [BgmService] 细节。
Future<void> showBgmPanel(BuildContext context) async {
  await BgmService.instance.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const BgmPanel(),
  );
}

/// BGM 背景音乐面板：播放控制 / 音量 / 朗读 duck / 歌单（本地文件 + 在线 URL）。
class BgmPanel extends StatefulWidget {
  const BgmPanel({super.key});

  @override
  State<BgmPanel> createState() => _BgmPanelState();
}

class _BgmPanelState extends State<BgmPanel> {
  final BgmService _bgm = BgmService.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bgm,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('背景音乐',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_outlined),
                      tooltip: '添加曲目',
                      onPressed: _showAddSheet,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                _buildNowPlaying(cs),
                const SizedBox(height: AppSpacing.s),
                Row(
                  children: [
                    Icon(Icons.volume_up_outlined,
                        size: 18, color: cs.onSurfaceVariant),
                    Expanded(
                      child: Slider(
                        value: _bgm.volume,
                        onChanged: (v) => _bgm.setVolume(v),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text('${(_bgm.volume * 100).round()}',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('朗读时自动降音量（混音 duck）'),
                  subtitle: Text(
                    _bgm.readAloudActive
                        ? '朗读中：已压低到 ${(_bgm.effectiveVolume * 100).round()}%'
                        : '朗读开始时 BGM 自动降到 ${(_bgm.duckFactor * 100).round()}%',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                  value: _bgm.duckEnabled,
                  onChanged: (v) => _bgm.setDuckEnabled(v),
                ),
                Row(
                  children: [
                    const SizedBox(width: 76, child: Text('降音量比例')),
                    Expanded(
                      child: Slider(
                        value: _bgm.duckFactor,
                        min: 0.05,
                        max: 1.0,
                        divisions: 19,
                        label: '${(_bgm.duckFactor * 100).round()}%',
                        onChanged: (v) => _bgm.setDuckFactor(v),
                      ),
                    ),
                  ],
                ),
                const Divider(),
                AppSectionHeader('歌单（${_bgm.tracks.length}）'),
                SizedBox(
                  height: 240,
                  child: _bgm.tracks.isEmpty
                      ? AppEmptyState(
                          icon: Icons.library_music_outlined,
                          title: '歌单为空',
                          message: '点右上角 + 添加本地音频或在线 URL',
                          action: FilledButton(
                            onPressed: _showAddSheet,
                            child: const Text('添加曲目'),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _bgm.tracks.length,
                          itemBuilder: (context, i) {
                            final t = _bgm.tracks[i];
                            final active = i == _bgm.index;
                            return ListTile(
                              dense: true,
                              selected: active,
                              leading: Icon(
                                t.source == 'online'
                                    ? Icons.cloud_outlined
                                    : Icons.audiotrack_outlined,
                                color: active ? cs.primary : cs.onSurfaceVariant,
                              ),
                              title: Text(t.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${t.artist.isEmpty ? (t.source == "online" ? "在线" : "本地") : t.artist} · ${t.url}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '从歌单移除',
                                onPressed: () => _bgm.removeTrack(t),
                              ),
                              onTap: () => _bgm.playTrack(i),
                            );
                          },
                        ),
                ),
                if (_bgm.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s),
                    child: Text(_bgm.error!,
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNowPlaying(ColorScheme cs) {
    final t = _bgm.current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.mAll,
      ),
      child: Row(
        children: [
          Icon(Icons.music_note, color: cs.primary),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              t?.title ?? '未在播放',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_outlined),
            tooltip: '上一首',
            onPressed: _bgm.tracks.isEmpty ? null : () => _bgm.prev(),
          ),
          IconButton(
            icon: Icon(_bgm.playing ? Icons.pause : Icons.play_arrow),
            tooltip: _bgm.playing ? '暂停' : '播放',
            onPressed: () => _bgm.toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_outlined),
            tooltip: '下一首',
            onPressed: _bgm.tracks.isEmpty ? null : () => _bgm.next(),
          ),
        ],
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('添加本地音频文件'),
            onTap: () {
              Navigator.pop(c);
              _pickLocalFile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('添加在线 URL'),
            subtitle: const Text('直链 mp3 / m3u8，由 audioplayers 播放在线流'),
            onTap: () {
              Navigator.pop(c);
              _showOnlineDialog();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pickLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) return;
    final name = file.name;
    await _bgm.addLocalTrack(title: name, path: path);
    _toast('已添加本地曲目：$name');
  }

  Future<void> _showOnlineDialog() async {
    final titleCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final artistCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加在线曲目'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleCtl,
              decoration: const InputDecoration(labelText: '曲名'),
            ),
            TextField(
              controller: artistCtl,
              decoration: const InputDecoration(labelText: '作者 / 来源（可选）'),
            ),
            TextField(
              controller: urlCtl,
              decoration: const InputDecoration(
                  labelText: '音频 URL', hintText: 'https://…/music.mp3'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok != true) return;
    final url = urlCtl.text.trim();
    if (url.isEmpty) return;
    await _bgm.addOnlineTrack(
      title: titleCtl.text.trim().isEmpty ? url : titleCtl.text.trim(),
      url: url,
      artist: artistCtl.text.trim(),
    );
    _toast('已添加在线曲目');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

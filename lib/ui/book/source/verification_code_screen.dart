import 'package:flutter/material.dart';

/// 图片验证码输入界面（对齐 legado-E ui/association/VerificationCodeDialog.kt）
///
/// 由书源 JS 的 `getVerificationCode(imageUrl)` 触发：JS 返回 Promise，
/// 本界面提交/取消后由 JS 运行时回传结果、resolve 该 Promise。
class VerificationCodeScreen extends StatefulWidget {
  final String imageUrl;
  final String? sourceName;

  const VerificationCodeScreen({super.key, required this.imageUrl, this.sourceName});

  @override
  State<VerificationCodeScreen> createState() => _VerificationCodeScreenState();
}

class _VerificationCodeScreenState extends State<VerificationCodeScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String code) {
    if (_submitted) return;
    _submitted = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('验证码'),
            if (widget.sourceName != null)
              Text(widget.sourceName!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('请输入下图中的字符', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showFullImage(context, widget.imageUrl),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (c, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (c, e, s) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                        const SizedBox(height: 4),
                        Text('图片加载失败', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('点击图片可查看大图', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '验证码',
                hintText: '输入图中字符',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _submit,
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (_submitted) return;
                      _submitted = true;
                      Navigator.pop(context);
                    },
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _submit(_controller.text.trim()),
                    child: const Text('确定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 查看大图（对齐 E 的 PhotoDialog）
  void _showFullImage(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

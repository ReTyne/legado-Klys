/// 从 crypto_utils.dart 拆分： `help/crypto/` 按算法分文件。
/// 以 part 归属同一库，私有类型互引保持可用。
part of '../../utils/crypto_utils.dart';


// =====================================================================
// RC4（流密码）
// =====================================================================

class _Rc4Engine {
  _Rc4Engine(Uint8List key) {
    if (key.isEmpty || key.length > 256) {
      throw ArgumentError('RC4 密钥长度须在 1..256 字节');
    }
    _s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + _s[i] + key[i % key.length]) & 0xff;
      final t = _s[i];
      _s[i] = _s[j];
      _s[j] = t;
    }
  }

  late final List<int> _s;
  int _i = 0;
  int _j = 0;

  void process(Uint8List data, int off, int len, Uint8List out, int outOff) {
    for (var k = 0; k < len; k++) {
      _i = (_i + 1) & 0xff;
      _j = (_j + _s[_i]) & 0xff;
      final t = _s[_i];
      _s[_i] = _s[_j];
      _s[_j] = t;
      final ks = _s[(_s[_i] + _s[_j]) & 0xff];
      out[outOff + k] = data[off + k] ^ ks;
    }
  }
}

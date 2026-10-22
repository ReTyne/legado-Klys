import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// 备份内容类型枚举。
/// key   —— 数据键名（与旧版纯 JSON 备份的顶层键保持一致，保证向后兼容）
/// file  —— zip 包内对应的文件名
/// label —— 备份界面展示的中文名
enum BackupType {
  books('书籍'),
  bookSources('书源'),
  replaceRules('替换规则'),
  rssSources('RSS源'),
  rssStars('RSS收藏'),
  bookmarks('书签'),
  groups('分组'),
  readRecords('阅读记录'),
  txtTocRules('TXT目录'),
  dictRules('词典'),
  httpTts('HTTP TTS'),
  ruleSubs('规则订阅'),
  searchHistory('搜索历史'),
  servers('服务器'),
  readConfig('阅读排版'),
  theme('主题'),
  settings('全部配置');

  const BackupType(this.label);

  /// 数据键名（旧版 JSON 备份兼容键）
  String get key {
    switch (this) {
      case BackupType.readConfig:
        return 'readConfig';
      case BackupType.httpTts:
        return 'httpTts';
      default:
        return name;
    }
  }

  /// zip 包内文件名
  String get file => '$key.json';

  /// 是否敏感数据（含登录/密码信息，单独加密后放入 zip）
  bool get sensitive {
    switch (this) {
      case BackupType.bookSources:
      case BackupType.servers:
      case BackupType.httpTts:
      case BackupType.settings:
        return true;
      default:
        return false;
    }
  }

  final String label;
}

/// 备份内容勾选集合
class BackupSelection {
  final Set<BackupType> types;
  const BackupSelection(this.types);

  /// 默认全选
  factory BackupSelection.all() => BackupSelection(Set.from(BackupType.values));

  bool contains(BackupType t) => types.contains(t);

  /// 反序列化：从 index.json 的 types 列表还原（未知类型自动忽略）
  factory BackupSelection.fromList(List<dynamic>? list) {
    final names = (list ?? []).map((e) => e.toString()).toSet();
    return BackupSelection(
      Set.from(BackupType.values.where((t) => names.contains(t.name))),
    );
  }

  List<String> toList() => types.map((t) => t.name).toList();
}

/// 轻量对称加密工具（XOR 流加密）。
///
/// 说明：项目未引入 encrypt 包（pubspec 仅有 crypto 哈希库），
/// 因此这里基于 crypto 的 SHA-256 实现一个「密钥流异或」的可逆加密：
///   1. 由用户密码 + 随机盐派生 32 字节种子：seed = sha256(password + salt)
///   2. 按块生成密钥流：block[i] = sha256(seed || i)，明文逐字节与密钥流异或
///   3. 密文尾部追加 4 字节 sha256(明文) 校验和，用于识别密码是否正确
/// 这不是军用级加密，但满足「备份中的敏感项非明文存放」的需求。
/// 文件头固定为 "KLYSAES1"（8 字节 ASCII）+ 8 字节盐。
class LightCrypto {
  LightCrypto._();

  /// 加密文件头标识
  static const String magic = 'KLYSAES1';

  static const int _saltLen = 8;
  static const int _checksumLen = 4;

  /// 判断字节是否为本方案加密的数据（检测文件头）
  static bool isEncrypted(List<int> data) {
    if (data.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (data[i] != magic.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// 加密：返回 magic + salt + 密文 + 校验和
  static Uint8List encrypt(List<int> plaintext, String password) {
    final rand = Random.secure();
    final salt = List<int>.generate(_saltLen, (_) => rand.nextInt(256));
    final seed = _deriveSeed(password, salt);
    final cipher = _xorKeystream(plaintext, seed);
    final checksum = sha256.convert(plaintext).bytes.sublist(0, _checksumLen);
    final out = BytesBuilder(copy: false);
    out.add(ascii.encode(magic));
    out.add(salt);
    out.add(cipher);
    out.add(checksum);
    return out.toBytes();
  }

  /// 解密：传入整段数据（含文件头）。密码错误或数据损坏时抛出异常。
  static Uint8List decrypt(List<int> data, String password) {
    if (!isEncrypted(data)) {
      throw const FormatException('不是有效的加密数据（缺少 KLYSAES1 文件头）');
    }
    final salt = data.sublist(magic.length, magic.length + _saltLen);
    final bodyLen = data.length - magic.length - _saltLen;
    if (bodyLen < _checksumLen) {
      throw const FormatException('加密数据长度异常');
    }
    final cipher = data.sublist(magic.length + _saltLen, data.length - _checksumLen);
    final checksum = data.sublist(data.length - _checksumLen);
    final seed = _deriveSeed(password, salt);
    final plaintext = _xorKeystream(cipher, seed);
    final expect = sha256.convert(plaintext).bytes.sublist(0, _checksumLen);
    for (var i = 0; i < _checksumLen; i++) {
      if (expect[i] != checksum[i]) {
        throw const FormatException('密码错误或数据已损坏');
      }
    }
    return plaintext;
  }

  /// 由密码与盐派生 32 字节种子
  static List<int> _deriveSeed(String password, List<int> salt) {
    return sha256.convert([...utf8.encode(password), ...salt]).bytes;
  }

  /// 密钥流异或：block[i] = sha256(seed || 大端 4 字节块号)
  static Uint8List _xorKeystream(List<int> data, List<int> seed) {
    final out = Uint8List(data.length);
    var block = 0;
    var pos = 0;
    while (pos < data.length) {
      final keyBlock = sha256.convert([
        ...seed,
        (block >> 24) & 0xFF,
        (block >> 16) & 0xFF,
        (block >> 8) & 0xFF,
        block & 0xFF,
      ]).bytes;
      final n = min(keyBlock.length, data.length - pos);
      for (var i = 0; i < n; i++) {
        out[pos + i] = data[pos + i] ^ keyBlock[i];
      }
      pos += n;
      block++;
    }
    return out;
  }
}

/// zip 备份的元信息（index.json）
class ZipBackupIndex {
  final String version;
  final String time;
  final String deviceName;
  final String appVersion;
  final bool encrypted; // 是否包含加密内容
  final BackupSelection selection;

  ZipBackupIndex({
    required this.version,
    required this.time,
    required this.deviceName,
    required this.appVersion,
    required this.encrypted,
    required this.selection,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'time': time,
        'deviceName': deviceName,
        'appVersion': appVersion,
        'encrypted': encrypted,
        'types': selection.toList(),
      };

  factory ZipBackupIndex.fromJson(Map<String, dynamic> json) => ZipBackupIndex(
        version: json['version']?.toString() ?? '1.0',
        time: json['time']?.toString() ?? '',
        deviceName: json['deviceName']?.toString() ?? '未知设备',
        appVersion: json['appVersion']?.toString() ?? '',
        encrypted: json['encrypted'] == true,
        selection: BackupSelection.fromList(json['types'] as List<dynamic>?),
      );
}

/// 解析后的 zip 备份数据
class ZipBackupData {
  final ZipBackupIndex index;
  /// 文件名 -> 明文内容（敏感文件已解密）
  final Map<String, String> files;
  ZipBackupData(this.index, this.files);

  bool hasType(BackupType t) => files.containsKey(t.file);
}

/// zip 备份构建器：把各类型 JSON 打成一个 zip 包（.zip）
class ZipBackupBuilder {
  /// 构建 zip 字节
  /// [payloads]：类型 -> 明文 JSON 字符串
  /// [password]：非空时，敏感类型的数据先加密再放入 zip
  static Uint8List build({
    required ZipBackupIndex index,
    required Map<BackupType, String> payloads,
    String? password,
  }) {
    final archive = Archive();
    archive.addFile(_file('index.json', utf8.encode(jsonEncode(index.toJson()))));
    payloads.forEach((type, json) {
      var bytes = utf8.encode(json);
      // 敏感数据单独加密后再放入 zip，非明文存放
      if (type.sensitive && password != null && password.isNotEmpty) {
        bytes = LightCrypto.encrypt(bytes, password);
      }
      archive.addFile(_file(type.file, bytes));
    });
    final encoded = ZipEncoder().encode(archive, level: 9);
    if (encoded == null) {
      throw StateError('zip 打包失败');
    }
    return Uint8List.fromList(encoded);
  }

  /// 从 zip 字节解析备份
  /// [password]：解密敏感文件所需的密码（加密备份必须提供）
  static ZipBackupData parse(Uint8List bytes, {String? password}) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, String>{};
    ZipBackupIndex? index;
    for (final f in archive.files) {
      if (f.isFile != true) continue;
      final name = f.name.split('/').last; // 兼容带目录前缀的条目
      final content = f.content;
      if (name == 'index.json') {
        index = ZipBackupIndex.fromJson(
          Map<String, dynamic>.from(jsonDecode(utf8.decode(content))),
        );
        continue;
      }
      // 敏感文件带加密头，先解密再解码
      if (LightCrypto.isEncrypted(content)) {
        if (password == null || password.isEmpty) {
          throw const FormatException('该备份包含加密内容，需要密码');
        }
        final plain = LightCrypto.decrypt(content, password);
        files[name] = utf8.decode(plain);
      } else {
        files[name] = utf8.decode(content);
      }
    }
    if (index == null) {
      throw const FormatException('无效的备份 zip：缺少 index.json');
    }
    return ZipBackupData(index, files);
  }

  static ArchiveFile _file(String name, List<int> bytes) =>
      ArchiveFile(name, bytes.length, Uint8List.fromList(bytes));
}

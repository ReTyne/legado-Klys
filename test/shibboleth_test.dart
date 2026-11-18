import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/storage/shibboleth.dart';

void main() {
  const url = 'https://example.com/source.json';

  String encode(Map<String, dynamic> payload) =>
      '${Shibboleth.prefix}${base64Url.encode(utf8.encode(jsonEncode(payload)))}';

  test('六类类型标记往返一致', () {
    for (final type in ShareType.values) {
      final code = generateShareCode(url, type);
      expect(code.startsWith(Shibboleth.prefix), isTrue);
      final parsed = tryParse(code);
      expect(parsed, isNotNull, reason: '$type 应可解析');
      expect(parsed!.url, url);
      expect(parsed.type, type);
      expect(parsed.importType, type.importType);
      expect(parsed.expiresAt, isNull);
      expect(parsed.isExpired, isFalse);
    }
  });

  test('importType 与 DeepLinkService.importRaw 归一化类型名一致', () {
    expect(ShareType.bookSource.importType, 'bookSource');
    expect(ShareType.rssSource.importType, 'rss');
    expect(ShareType.dictRule.importType, 'dictRule');
    expect(ShareType.replaceRule.importType, 'replaceRule');
    expect(ShareType.tocRule.importType, 'txtRule');
    expect(ShareType.ttsRule.importType, 'httpTts');
  });

  test('expiryDays=0 永久有效，>0 写入到期时间戳', () {
    final permanent = tryParse(generateShareCode(url, ShareType.bookSource))!;
    expect(permanent.expiresAt, isNull);
    expect(permanent.isExpired, isFalse);

    final limited =
        tryParse(generateShareCode(url, ShareType.rssSource, expiryDays: 7))!;
    expect(limited.expiresAt, isNotNull);
    final days = limited.expiresAt!.difference(DateTime.now()).inDays;
    expect(days, greaterThanOrEqualTo(6));
    expect(days, lessThanOrEqualTo(7));
    expect(limited.isExpired, isFalse);
  });

  test('过期口令能被解析但标记为已过期', () {
    final past = DateTime.now()
        .subtract(const Duration(days: 1))
        .millisecondsSinceEpoch;
    final code = encode({
      'v': 1,
      't': ShareType.ttsRule.token,
      'e': past,
      'u': url,
    });
    final parsed = tryParse(code)!;
    expect(parsed.type, ShareType.ttsRule);
    expect(parsed.expiresAt, isNotNull);
    expect(parsed.isExpired, isTrue);
  });

  test('非法输入：空地址、负天数、损坏/篡改口令返回 null', () {
    expect(
      () => generateShareCode('   ', ShareType.bookSource),
      throwsArgumentError,
    );
    expect(
      () => generateShareCode(url, ShareType.bookSource, expiryDays: -1),
      throwsArgumentError,
    );

    expect(tryParse(''), isNull);
    expect(tryParse('not-a-code'), isNull);
    expect(tryParse('#L:!!!'), isNull);
    expect(
      tryParse(encode({'v': 99, 't': 'bs', 'e': 0, 'u': url})),
      isNull,
      reason: '版本不符',
    );
    expect(
      tryParse(encode({'v': 1, 't': 'xx', 'e': 0, 'u': url})),
      isNull,
      reason: '未知类型标记',
    );
    expect(
      tryParse(encode({'v': 1, 't': 'bs', 'e': 0, 'u': ''})),
      isNull,
      reason: '空地址',
    );
  });

  test('生成的口令能被 bootstrap 复用的统一解析识别（含/不含前缀）', () {
    final code = generateShareCode(url, ShareType.tocRule);
    expect(tryParse(code), isNotNull);
    expect(
      tryParse(code.substring(Shibboleth.prefix.length)),
      isNotNull,
      reason: 'bootstrap 会先剥掉 #L: 再调用同一解析',
    );
  });
}

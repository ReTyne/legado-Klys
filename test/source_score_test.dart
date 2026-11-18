import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/source/source_score.dart';

void main() {
  const origin = 'http://src.example';
  const origin2 = 'http://other.example';
  const name = '斗破苍穹';
  const author = '天蚕土豆';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SourceScore.load();
  });

  group('SourceScore 用户评分', () {
    test('单书评分增量语义：先 +1 再改 -1 应为 -1', () async {
      await SourceScore.setBookScore(origin, name, author, 1);
      expect(SourceScore.getBookScore(origin, name, author), 1);

      await SourceScore.setBookScore(origin, name, author, -1);
      expect(SourceScore.getBookScore(origin, name, author), -1);
    });

    test('来源总分按增量累加，始终等于各单书评分之和', () async {
      expect(SourceScore.getSourceScore(origin), 0);

      await SourceScore.setBookScore(origin, name, author, 1);
      expect(SourceScore.getSourceScore(origin), 1);

      // 同一本书由 +1 改 -1：增量 -2，总分 1 -> -1
      await SourceScore.setBookScore(origin, name, author, -1);
      expect(SourceScore.getSourceScore(origin), -1);

      // 另一本书 +1：总分 -1 -> 0
      await SourceScore.setBookScore(origin, '另一本', '作者', 1);
      expect(SourceScore.getSourceScore(origin), 0);

      // 第一本由 -1 改中性 0：增量 +1，总分 0 -> 1
      await SourceScore.setBookScore(origin, name, author, 0);
      expect(SourceScore.getBookScore(origin, name, author), 0);
      expect(SourceScore.getSourceScore(origin), 1);
    });

    test('不同来源评分互不干扰', () async {
      await SourceScore.setBookScore(origin, name, author, 1);
      await SourceScore.setBookScore(origin2, name, author, -1);

      expect(SourceScore.getSourceScore(origin), 1);
      expect(SourceScore.getSourceScore(origin2), -1);
    });

    test('removeSource 删除来源总分与该来源全部单书评分键', () async {
      await SourceScore.setBookScore(origin, name, author, 1);
      await SourceScore.setBookScore(origin, '另一本', '作者', -1);
      await SourceScore.setBookScore(origin2, name, author, 1);

      await SourceScore.removeSource(origin);

      expect(SourceScore.getBookScore(origin, name, author), 0);
      expect(SourceScore.getBookScore(origin, '另一本', '作者'), 0);
      expect(SourceScore.getSourceScore(origin), 0);
      // 其它来源不受影响
      expect(SourceScore.getBookScore(origin2, name, author), 1);
      expect(SourceScore.getSourceScore(origin2), 1);

      // 磁盘上该来源的键已全部移除
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => k.contains(origin)), isFalse);
      expect(prefs.getKeys().any((k) => k.contains(origin2)), isTrue);
    });
  });

  group('batchChangeSourceDelay 换源间隔偏好', () {
    test('键值往返与钳制 0~9999', () async {
      SharedPreferences.setMockInitialValues({});
      await AppPrefs.load();
      expect(AppPrefs.batchChangeSourceDelay, 0);

      // 落盘并可从 SharedPreferences 重新加载（往返）
      AppPrefs.batchChangeSourceDelay = 321;
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AppPrefs.keyBatchChangeSourceDelay), 321);
      await AppPrefs.load();
      expect(AppPrefs.batchChangeSourceDelay, 321);

      // 上界钳制
      AppPrefs.batchChangeSourceDelay = 99999;
      expect(AppPrefs.batchChangeSourceDelay, 9999);
      // 下界钳制
      AppPrefs.batchChangeSourceDelay = -5;
      expect(AppPrefs.batchChangeSourceDelay, 0);
    });
  });
}

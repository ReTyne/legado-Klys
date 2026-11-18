import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/reading/simulated_reading.dart';

void main() {
  group('simulatedTotalChapterNum', () {
    test('默认配置（空日期 / daily<=0）不限制章节', () {
      expect(
        simulatedTotalChapterNum(
          88,
          startChapter: 0,
          startDate: '',
          dailyChapters: 0,
        ),
        88,
      );
      expect(
        simulatedTotalChapterNum(
          88,
          startChapter: 10,
          startDate: '2026-01-01',
          dailyChapters: -3,
          now: DateTime(2026, 2, 1),
        ),
        88,
      );
    });

    test('非法日期不限制章节', () {
      for (final date in ['', '2026-1-1', '2026-02-30', 'not-a-date', '2026/01/01']) {
        expect(
          simulatedTotalChapterNum(
            100,
            startChapter: 5,
            startDate: date,
            dailyChapters: 3,
            now: DateTime(2026, 1, 10),
          ),
          100,
          reason: '非法日期 $date 应返回总章数',
        );
      }
    });

    test('开始当天 daysPassed=1，解锁 startChapter + dailyChapters', () {
      expect(
        simulatedTotalChapterNum(
          100,
          startChapter: 10,
          startDate: '2026-03-01',
          dailyChapters: 3,
          now: DateTime(2026, 3, 1, 23, 59),
        ),
        13,
      );
    });

    test('按日历天累计解锁', () {
      expect(
        simulatedTotalChapterNum(
          200,
          startChapter: 10,
          startDate: '2026-03-01',
          dailyChapters: 3,
          now: DateTime(2026, 3, 5, 8),
        ),
        25, // 10 + (4 + 1) * 3
      );
    });

    test('解锁数不超过总章数', () {
      expect(
        simulatedTotalChapterNum(
          20,
          startChapter: 10,
          startDate: '2026-03-01',
          dailyChapters: 3,
          now: DateTime(2026, 4, 1),
        ),
        20,
      );
    });

    test('开始日期在未来时解锁数钳制到 0，不为负', () {
      expect(
        simulatedTotalChapterNum(
          50,
          startChapter: 5,
          startDate: '2026-03-01',
          dailyChapters: 3,
          now: DateTime(2026, 2, 1),
        ),
        0,
      );
    });
  });
}

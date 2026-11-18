import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/config/prefer_key_map.dart';
import 'package:legado_md3/help/reading/click_area_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('纯 Dart 校验', () {
    test('缺省配置已含菜单，不触发守卫', () {
      expect(clickAreaNeedsGuard(defaultClickActions), isFalse);
      expect(applyClickAreaGuard(defaultClickActions), equals(defaultClickActions));
    });

    test('九区全非菜单时触发守卫，中心区恢复为 3 且不改动原列表', () {
      final actions = List<int>.filled(9, 2);
      expect(clickAreaNeedsGuard(actions), isTrue);
      final fixed = applyClickAreaGuard(actions);
      expect(fixed[4], 3);
      expect(clickAreaNeedsGuard(fixed), isFalse);
      expect(actions[4], 2);
    });

    test('非 9 区不受理', () {
      expect(clickAreaNeedsGuard(List<int>.filled(8, 2)), isFalse);
      expect(clickAreaNeedsGuard(List<int>.filled(10, 2)), isFalse);
    });

    test('任意区域含 3 即无需守卫', () {
      final actions = List<int>.filled(9, 2);
      actions[0] = 3;
      expect(clickAreaNeedsGuard(actions), isFalse);
      expect(applyClickAreaGuard(actions), equals(actions));
    });
  });

  group('SharedPreferences 守卫', () {
    test('命中后逐区持久化到九个独立键并写回 CSV', () async {
      SharedPreferences.setMockInitialValues({
        PreferKeyMap.clickActionsKey: List<int>.filled(9, 2).join(','),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(await detectClickArea(prefs), isTrue);
      final fixed = readClickActions(prefs)!;
      expect(fixed[4], 3);
      expect(prefs.getString(PreferKeyMap.clickActionsKey), fixed.join(','));
      expect(prefs.getInt(UpstreamPrefKey.clickActionMC), 3);
      expect(prefs.getInt(UpstreamPrefKey.clickActionTL), 2);
      expect(prefs.getInt(UpstreamPrefKey.clickActionBR), 2);
      // 修复后再次调用不再改动
      expect(await detectClickArea(prefs), isFalse);
    });

    test('未配置或长度异常时不写入', () async {
      SharedPreferences.setMockInitialValues({
        PreferKeyMap.clickActionsKey: '2,2,1',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await detectClickArea(prefs), isFalse);
      expect(prefs.getInt(UpstreamPrefKey.clickActionMC), isNull);
    });
  });
}

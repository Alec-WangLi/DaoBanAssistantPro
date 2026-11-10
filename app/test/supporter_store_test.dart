// app/test/supporter_store_test.dart
//
// 支持者解锁状态是本地 prefs：默认未解锁，解锁后读回 true。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/features/profile/supporter_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认未解锁，解锁后读回 true', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await readSupporterUnlocked(), isFalse);

    await unlockSupporter();
    expect(await readSupporterUnlocked(), isTrue);
  });
}

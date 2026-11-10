// app/lib/features/profile/supporter_store.dart
//
// 「支持者专属」的本地状态。
//
// 个人收款码没有支付回调，App 不可能知道「这个人真的付了」。所以这里不做校验，
// 只做一件事：用户在打赏弹层里自报「我已完成支付」之后，把状态落进
// SharedPreferences，下次打开 App 还在。打赏本来就是自愿的，未支付也不影响
// 任何功能 —— 这条状态只决定「支持者专属」那一行显示锁还是信。
import 'package:shared_preferences/shared_preferences.dart';

/// 本地键。**清空重置时要特意保留**（见 `profile_screen.dart` 的 `_confirmReset`）：
/// 用户不该因为一次重置丢掉自己支持过的记录。
const String kSupporterUnlockedKey = 'supporterUnlocked';

Future<bool> readSupporterUnlocked() async {
  try {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(kSupporterUnlockedKey) ?? false;
  } catch (_) {
    // 读设置失败（极少见）就当未解锁；不阻断「我的」页渲染。
    return false;
  }
}

Future<void> unlockSupporter() async {
  final sp = await SharedPreferences.getInstance();
  await sp.setBool(kSupporterUnlockedKey, true);
}

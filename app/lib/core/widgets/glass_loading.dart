import 'package:flutter/material.dart';

/// 加载态的转圈 —— 全 app 唯一实现。
///
/// 收口之前七个加载点各写各的：五个页面占位是裸 `CircularProgressIndicator()`
/// （`strokeWidth` 取 Flutter 默认的 **4.0**），另外两处（权限卡那一行、下载更新
/// 弹窗）手写了 `strokeWidth: 2` / `2.6`。同一个「加载中」在 app 里因此有
/// 4.0 / 2.6 / 2 三种粗细，谁也没共享过实现 —— 与「空态」「小节标题」那两件同一类
/// 病（见 `empty_state.dart` 顶上那段）。这一版收进一处：**粗细只由 [size] 推出来**
/// （`size / 12`），调用点不再手写描边宽度。
///
/// 两档，由调用点按语义挑：
/// - **整页占位**（页面 / 面板加载态）用默认 **36**（→ 3.0）；
/// - **行内小号**（权限卡那一行、下载更新弹窗）传 **`size: 24`**（→ 2.0）。
///
/// 之所以取 `size / 12`：36 → 3.0 落在这套设计语言里既有两条横线之间，而 24 → 2.0
/// 正好对上权限卡原先手写的那个 2。带一层 [Center]，所以整页占位那几处直接换掉
/// 原来的 `Center(child: CircularProgressIndicator())` 即可（不重复套 [Center]）。
class GlassLoading extends StatelessWidget {
  const GlassLoading({super.key, this.size = 36});

  /// 转圈的外框边长；描边宽度由它推出来（`size / 12`），不在调用点手写。
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: size / 12),
      ),
    );
  }
}

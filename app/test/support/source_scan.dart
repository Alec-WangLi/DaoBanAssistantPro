// app/test/support/source_scan.dart
//
// 源码剥壳器：把 Dart 源码里的**非代码部分**（行注释、块注释、字符串字面量的
// 内容）替换成**等长空格**，供「按模式扫源码」的守门测试共用。
//
// 原本长在 `design_tokens_test.dart` 里。触觉守门测试（`haptics_guard_test.dart`）
// 也要用它，所以抽到这里 —— 抄一份的话，两份迟早走偏，而走偏的表现是**漏检**
// （把真代码当成注释清掉），不会报错。
//
// 注意：**豁免标记写在注释里**，所以「有没有具名豁免」必须回到**原始源码**上查，
// 不能查这个副本（注释在这里已经是空格了）。
//
// 本文件**不需要任何 import** —— `blankNonCode` 只用 `String` / `RegExp`，都在
// `dart:core` 里。
final _identChar = RegExp(r'[A-Za-z0-9_$]');

/// 把源码里的**非代码部分**替换成**等长空格**：行注释、块注释、字符串字面量的内容。
///
/// 为什么要等长替换而不是删掉：所有规则都靠「命中偏移 → 行号」定位，删字符会让
/// 偏移全错。换成空格则偏移与行号纹丝不动。
///
/// 换行**保留** —— 行数也不能变。
///
/// 注意：**具名豁免标记写在注释里**，所以豁免判定必须回到**原始源码**上查，
/// 不能查这个副本（注释在这里已经是空格了）。
///
/// 两处必须按 Dart 词法走对，否则会**漏检**（把真代码当成注释/字符串清掉）：
///   - **原始字符串** `r'…'` / `R"…"` 里 `\` **不转义**：`r'a\'` 在结束引号前
///     有一个 `\`，若照普通字符串「跳转义」就会以为引号没结束、一路吞到下一个
///     引号（或文件尾），把中间真代码静默清掉。故先看引号前是不是 `r`/`R`
///     前缀（且它前面不是标识符字符）。
///   - **块注释可嵌套**：`/* a /* b */ c */` 里 `indexOf('*/')` 会停在内层，
///     把内层之后的正文当代码露出来（误报）。故按深度找配对的 `*/`。
///
/// 已知边界（有意不处理）：字符串**插值里嵌套同引号字面量**
/// （`Text('${m['k']}')`）会把内层内容露出来 —— 是**误报**方向，且引号奇偶
/// 仍平衡、不会跑飞。要处理需真正的插值感知解析，本轮不做。
String blankNonCode(String src) {
  final out = src.split('');
  void blank(int from, int to) {
    for (var k = from; k < to && k < out.length; k++) {
      if (out[k] != '\n') out[k] = ' ';
    }
  }

  var i = 0;
  while (i < src.length) {
    // 行注释：到行尾（不含换行）
    if (src.startsWith('//', i)) {
      final nl = src.indexOf('\n', i);
      final stop = nl < 0 ? src.length : nl;
      blank(i, stop);
      i = stop;
      continue;
    }
    // 块注释：**可嵌套**，按深度找配对的 `*/`。未闭合则到文件尾
    // （j 每轮至少 +1，不会死循环）。
    if (src.startsWith('/*', i)) {
      var depth = 1;
      var j = i + 2;
      while (j < src.length && depth > 0) {
        if (src.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (src.startsWith('*/', j)) {
          depth--;
          j += 2;
        } else {
          j++;
        }
      }
      blank(i, j);
      i = j;
      continue;
    }
    final c = src[i];
    if (c == "'" || c == '"') {
      // 原始字符串前缀：`r'…'` / `R"…"`。`r` 前面若还是标识符字符，那 `r` 是
      // 标识符的一部分（`abr'…'`），不是前缀。
      final raw = i > 0 &&
          (src[i - 1] == 'r' || src[i - 1] == 'R') &&
          (i < 2 || !_identChar.hasMatch(src[i - 2]));
      final triple = i + 2 < src.length && src[i + 1] == c && src[i + 2] == c;
      final quote = triple ? c * 3 : c;
      var j = i + quote.length;
      while (j < src.length) {
        // 原始字符串里 `\` 不转义，只有普通字符串才跳过转义的下一个字符。
        if (!raw && src[j] == '\\') {
          j += 2;
          continue;
        }
        if (src.startsWith(quote, j)) break;
        j++;
      }
      final stop = j >= src.length ? src.length : j + quote.length;
      // 只清**内容**，引号（含 `r` 前缀）保留 —— 更直观，也不影响任何规则。
      blank(i + quote.length, j);
      i = stop;
      continue;
    }
    i++;
  }
  return out.join();
}

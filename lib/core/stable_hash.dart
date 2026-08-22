/// 与平台/运行次数无关的字符串哈希。
///
/// Dart 的 `String.hashCode` 不保证跨进程稳定，而通知 id 和课程配色都需要
/// 「同样的输入永远得到同样的输出」，所以自己算。结果限制在 31 位内，
/// Android 的通知 id 要求 32 位 int。
int stableHash(String input) {
  var h = 17;
  for (final unit in input.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return h;
}

import 'jsplugin_api.dart';

/// 按持久化的 entryPath 顺序重排 [plugins]。
///
/// - 只对可展示的（已启用且带 entryPath）插件排序；调用方传入的列表通常已过滤。
/// - 出现在 [order] 中但已不存在的 entryPath 会被跳过（卸载竞态兜底）。
/// - 未列入 [order] 的插件按原始相对顺序追加到末尾（新装插件默认落尾）。
/// - 重复 entryPath 只取首个匹配位置。
List<JSPlugin> applyPluginOrder(List<JSPlugin> plugins, List<String> order) {
  if (order.isEmpty) return List.of(plugins);

  final byEntry = <String, JSPlugin>{};
  for (final p in plugins) {
    final ep = p.entryPath;
    if (ep == null || ep.isEmpty) continue;
    byEntry.putIfAbsent(ep, () => p);
  }

  final result = <JSPlugin>[];
  final used = <String>{};
  for (final ep in order) {
    if (used.contains(ep)) continue;
    final p = byEntry[ep];
    if (p == null) continue;
    result.add(p);
    used.add(ep);
  }

  for (final p in plugins) {
    final ep = p.entryPath;
    if (ep == null || ep.isEmpty) continue;
    if (used.contains(ep)) continue;
    result.add(p);
    used.add(ep);
  }

  return result;
}

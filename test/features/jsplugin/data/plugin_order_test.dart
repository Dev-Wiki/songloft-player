import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/jsplugin/data/jsplugin_api.dart';
import 'package:songloft_flutter/features/jsplugin/data/plugin_order.dart';

JSPlugin _plugin(int id, String entryPath, {String status = 'active'}) {
  final now = DateTime(2026);
  return JSPlugin(
    id: id,
    name: entryPath,
    entryPath: entryPath,
    filePath: '/plugins/$entryPath',
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('applyPluginOrder', () {
    test('空 order 保留原顺序', () {
      final plugins = [_plugin(1, 'a'), _plugin(2, 'b'), _plugin(3, 'c')];
      final result = applyPluginOrder(plugins, const []);
      expect(result.map((p) => p.entryPath).toList(), ['a', 'b', 'c']);
    });

    test('按 order 重排已有插件', () {
      final plugins = [_plugin(1, 'a'), _plugin(2, 'b'), _plugin(3, 'c')];
      final result = applyPluginOrder(plugins, ['c', 'a', 'b']);
      expect(result.map((p) => p.entryPath).toList(), ['c', 'a', 'b']);
    });

    test('新装的插件追加到末尾', () {
      final plugins = [_plugin(1, 'a'), _plugin(2, 'b'), _plugin(3, 'c')];
      final result = applyPluginOrder(plugins, ['b', 'a']);
      expect(result.map((p) => p.entryPath).toList(), ['b', 'a', 'c']);
    });

    test('已卸载的 entryPath 会被跳过', () {
      final plugins = [_plugin(1, 'a'), _plugin(2, 'b')];
      final result = applyPluginOrder(plugins, ['a', 'gone', 'b']);
      expect(result.map((p) => p.entryPath).toList(), ['a', 'b']);
    });

    test('order 中重复的 entryPath 只取首个位置', () {
      final plugins = [_plugin(1, 'a'), _plugin(2, 'b'), _plugin(3, 'c')];
      final result = applyPluginOrder(plugins, ['a', 'b', 'a', 'c']);
      expect(result.map((p) => p.entryPath).toList(), ['a', 'b', 'c']);
    });
  });
}

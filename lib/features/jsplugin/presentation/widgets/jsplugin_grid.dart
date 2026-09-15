import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../../config/app_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/jsplugin_api.dart';
import '../../data/plugin_order.dart';
import '../providers/jsplugin_provider.dart';
import 'plugin_icon.dart';

/// JS 插件入口网格组件
class JSPluginGrid extends ConsumerStatefulWidget {
  const JSPluginGrid({super.key});

  @override
  ConsumerState<JSPluginGrid> createState() => _JSPluginGridState();
}

class _JSPluginGridState extends ConsumerState<JSPluginGrid> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final pluginsAsync = ref.watch(jsPluginsProvider);

    return pluginsAsync.when(
      data: (plugins) {
        final activePlugins =
            plugins
                .where(
                  (p) =>
                      p.isActive &&
                      p.entryPath != null &&
                      p.entryPath!.isNotEmpty,
                )
                .toList();

        if (activePlugins.isEmpty) {
          if (_editing) _editing = false;
          return const SizedBox.shrink();
        }

        // 只有真正有插件要展示时才拉排序配置，避免宿主页面测试里
        // 短路了 jsPlugins 但没短路 pluginOrder 时留下 pending 请求。
        final order = ref.watch(pluginOrderProvider).value ?? const <String>[];
        final ordered = applyPluginOrder(activePlugins, order);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).jspluginGridTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _editing = !_editing),
                    child: Text(
                      _editing
                          ? AppLocalizations.of(context).jspluginGridDoneEditing
                          : AppLocalizations.of(context).jspluginGridEditOrder,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                final containerWidth = constraints.maxWidth - 24;
                final int crossAxisCount;
                if (context.isMobile ||
                    containerWidth < ResponsiveBreakpoints.tablet) {
                  crossAxisCount = (containerWidth / 90).floor().clamp(3, 5);
                } else if (containerWidth < ResponsiveBreakpoints.desktop) {
                  crossAxisCount = (containerWidth / 110).floor().clamp(4, 5);
                } else {
                  crossAxisCount = (containerWidth / 120).floor().clamp(5, 8);
                }

                final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.88,
                );

                if (_editing) {
                  return ReorderableGridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    gridDelegate: gridDelegate,
                    itemCount: ordered.length,
                    // 按下即拖，不用长按。库默认是 kLongPressTimeout（~500ms），
                    // 用户反馈"每个插件上加个拖动按钮更方便"——此处配合卡片
                    // 右上角的 drag_indicator 图标做视觉提示，用户按到卡片
                    // 任意位置都能立刻开始拖动。
                    dragStartDelay: Duration.zero,
                    itemBuilder: (context, index) {
                      final plugin = ordered[index];
                      return _JSPluginCard(
                        key: ValueKey(plugin.entryPath),
                        plugin: plugin,
                        editing: true,
                      );
                    },
                    onReorder: (oldIndex, newIndex) {
                      final next = List<JSPlugin>.of(ordered);
                      final moved = next.removeAt(oldIndex);
                      next.insert(newIndex, moved);
                      final entryPaths = next.map((p) => p.entryPath!).toList();
                      // 乐观提交给后端；provider 内部会以服务端返回为准
                      ref
                          .read(pluginOrderProvider.notifier)
                          .updateOrder(entryPaths);
                    },
                  );
                }

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  gridDelegate: gridDelegate,
                  itemCount: ordered.length,
                  itemBuilder: (context, index) {
                    final plugin = ordered[index];
                    return _JSPluginCard(
                      key: ValueKey(plugin.entryPath),
                      plugin: plugin,
                    );
                  },
                );
              },
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// JS 插件卡片组件
class _JSPluginCard extends StatelessWidget {
  final JSPlugin plugin;
  final bool editing;

  const _JSPluginCard({super.key, required this.plugin, this.editing = false});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PluginIcon(
            iconUrl: plugin.iconUrl,
            displayName: plugin.displayName,
            size: 46,
          ),
          const SizedBox(height: 8),
          Text(
            plugin.displayName,
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color:
          editing
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerLow,
      child:
          editing
              // 编辑态：卡片任意位置按下即拖（见外层 dragStartDelay: Duration.zero）；
              // 右上角小图标只做视觉提示，告诉用户这张卡是可拖的。
              ? Stack(
                children: [
                  Positioned.fill(child: content),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IgnorePointer(
                      child: Icon(
                        Icons.drag_indicator,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              )
              : InkWell(onTap: () => _openPlugin(context), child: content),
    );
  }

  /// 打开插件入口
  void _openPlugin(BuildContext context) {
    if (plugin.entryPath == null || plugin.entryPath!.isEmpty) {
      return;
    }

    final url =
        '${AppConfig.resolvedBaseUrl}${AppConfig.basePath}/api/v1/jsplugin/${plugin.entryPath}';

    context.push(
      Uri(
        path: AppRoutes.plugin,
        queryParameters: {'url': url, 'name': plugin.displayName},
      ).toString(),
    );
  }
}

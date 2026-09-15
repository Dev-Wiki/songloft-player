import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/app_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/jsplugin_api.dart';
import '../../data/plugin_order.dart';
import '../providers/jsplugin_provider.dart';
import 'plugin_icon.dart';

/// JS 插件入口网格
///
/// 非编辑态：GridView 排布卡片。编辑态：切换成 ReorderableListView + 拖拽把手
/// （与曲库"自定义视图"编辑器一致的模式）—— 抛掉二维 flex-wrap 拖拽，走单列
/// 拖动条，交互统一且能在 Web/桌面/移动都稳定工作。
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
            if (_editing)
              _PluginReorderList(
                plugins: ordered,
                onReorder: (next) {
                  final entryPaths = next.map((p) => p.entryPath!).toList();
                  ref
                      .read(pluginOrderProvider.notifier)
                      .updateOrder(entryPaths);
                },
              )
            else
              _PluginGrid(plugins: ordered),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _PluginGrid extends StatelessWidget {
  final List<JSPlugin> plugins;

  const _PluginGrid({required this.plugins});

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth - 24;
        final crossAxisCount = _crossAxisCountFor(containerWidth, isMobile);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.88,
          ),
          itemCount: plugins.length,
          itemBuilder: (context, index) {
            final plugin = plugins[index];
            return _JSPluginCard(
              key: ValueKey(plugin.entryPath),
              plugin: plugin,
            );
          },
        );
      },
    );
  }
}

/// 网格列数：随宽度自适应，逻辑与原实现保持一致（手机 / 平板 / 桌面阶梯）。
int _crossAxisCountFor(double containerWidth, bool isMobile) {
  if (isMobile || containerWidth < ResponsiveBreakpoints.tablet) {
    return (containerWidth / 90).floor().clamp(3, 5);
  }
  if (containerWidth < ResponsiveBreakpoints.desktop) {
    return (containerWidth / 110).floor().clamp(4, 5);
  }
  return (containerWidth / 120).floor().clamp(5, 8);
}

class _PluginReorderList extends StatelessWidget {
  final List<JSPlugin> plugins;
  final ValueChanged<List<JSPlugin>> onReorder;

  const _PluginReorderList({required this.plugins, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: plugins.length,
        onReorderItem: (oldIndex, newIndex) {
          final next = List<JSPlugin>.of(plugins);
          final moved = next.removeAt(oldIndex);
          next.insert(newIndex, moved);
          onReorder(next);
        },
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder:
                (context, child) => Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                ),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final plugin = plugins[index];
          return ListTile(
            key: ValueKey(plugin.entryPath),
            leading: PluginIcon(
              iconUrl: plugin.iconUrl,
              displayName: plugin.displayName,
              size: 32,
            ),
            title: Text(plugin.displayName),
            trailing: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _JSPluginCard extends StatelessWidget {
  final JSPlugin plugin;

  const _JSPluginCard({super.key, required this.plugin});

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
      color: colorScheme.surfaceContainerLow,
      child: InkWell(onTap: () => _openPlugin(context), child: content),
    );
  }

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

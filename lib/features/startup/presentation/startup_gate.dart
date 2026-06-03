import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../core/network/base_url_provider.dart';
import '../../../core/network/server_entry.dart';
import '../../../core/network/server_probe.dart';
import '../../../core/network/servers_provider.dart';

/// 启动时显示一个简单 Splash，期间完成：
/// 1. 读取持久化的服务器列表
/// 2. 并行探测可达性（最长 2.5s）
/// 3. 选优先级最高的成功项写入 baseUrlProvider；全失败则 fallback 列表首项
/// 4. 设置 probeOutcomeProvider 供首屏 SnackBar 提示
///
/// embedded 模式不做任何探测，直接渲染 child。
class StartupGate extends ConsumerStatefulWidget {
  final Widget child;
  const StartupGate({super.key, required this.child});

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  bool _ready = false;
  String _hint = '正在启动…';

  @override
  void initState() {
    super.initState();
    if (AppConfig.isEmbedded) {
      _ready = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    }
  }

  Future<void> _bootstrap() async {
    try {
      final servers = await ref.read(serversProvider.future);

      if (servers.isEmpty) {
        ref.read(probeOutcomeProvider.notifier).set(ProbeOutcome.noServers);
      } else if (servers.length == 1) {
        ref.read(baseUrlProvider.notifier).set(servers.first.url);
        ref.read(probeOutcomeProvider.notifier).set(ProbeOutcome.success);
      } else {
        setState(() {
          _hint = '正在连接 ${_describe(servers.first)}…';
        });

        final picked = await ServerProbe.pickFirstReachable(servers);
        final chosen = picked ?? servers.first;
        ref.read(baseUrlProvider.notifier).set(chosen.url);
        ref.read(probeOutcomeProvider.notifier).set(
              picked == null ? ProbeOutcome.fallbackUsed : ProbeOutcome.success,
            );
      }
    } catch (e) {
      debugPrint('[StartupGate] 启动初始化失败: $e');
      ref.read(probeOutcomeProvider.notifier).set(ProbeOutcome.fallbackUsed);
    } finally {
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    }
  }

  String _describe(ServerEntry e) {
    if (e.name.isNotEmpty) return e.name;
    return e.displayName;
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icons/app_icon.png', width: 64, height: 64),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(_hint),
            ],
          ),
        ),
      ),
    );
  }
}

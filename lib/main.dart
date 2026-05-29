import 'dart:io' show Platform, exit;
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'config/app_config.dart';
import 'core/audio/audio_service.dart';
import 'core/storage/app_preferences.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/responsive.dart';
import 'core/router/app_router.dart';
import 'core/utils/window_tray_manager.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

/// 全局 AudioHandler Provider
final audioHandlerProvider = Provider<SongloftAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden');
});

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    bool isFirstInstance = await WindowsSingleInstance.ensureSingleInstance(
      args,
      "songloft_player_instance",
      onSecondWindow: (List<String> args) {
        // 关键修复：必须异步执行窗口恢复操作。
        // 因为底层插件是通过同步的 SendMessage 跨进程通信的。如果在回调里直接同步调用 windowManager（反向调用 Native），
        // 会导致主线程的方法通道死锁，造成第一个进程卡死，第二个进程也无法走完 exit() 而残留后台。
        Future.delayed(const Duration(milliseconds: 200), () async {
          await windowManager.show();
          await windowManager.focus();
        });
      },
    );
    if (!isFirstInstance) {
      exit(0);
    }
  }

  // Windows 和 Linux 平台需要 media_kit 作为 just_audio 的后端
  // 必须在 AudioService.init() 之前调用
  if (!kIsWeb) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Windows 和 Linux 平台配置托盘和窗口行为
  if (Platform.isWindows || Platform.isLinux) {
    await WindowTrayManager.setup();
    
    // 强制确保窗口在首次启动时显示
    // 加入 windows_single_instance 后，可能会导致 Flutter 的默认首帧显示失效
    if (Platform.isWindows) {
      await windowManager.waitUntilReadyToShow(null, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }

  // 全局异常处理，防止未捕获异常导致白屏
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformError] $error\n$stack');
    return true;
  };

  if (AppConfig.isEmbedded) {
    // 嵌入模式：Flutter Web 嵌入 Go 后端，直接使用当前页面的 origin 作为后端 API 地址
    // 两者同域，无需手动配置
    AppConfig.baseUrl = Uri.base.origin;
  } else {
    // 独立部署模式：从本地存储恢复用户之前配置的 API 地址
    final prefs = await AppPreferences.create();
    final savedUrl = prefs.getApiBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      AppConfig.baseUrl = savedUrl;
    }
  }

  // Android 13+ 需要运行时请求通知权限
  if (!kIsWeb && Platform.isAndroid) {
    final status = await Permission.notification.status;
    debugPrint('[Main] 📱 Android 平台检测');
    debugPrint('[Main] 通知权限状态: $status');
    if (status.isDenied) {
      debugPrint('[Main] 请求通知权限...');
      final result = await Permission.notification.request();
      debugPrint('[Main] 通知权限请求结果: $result');
    }
    // 检查权限是否永久拒绝
    if (status.isPermanentlyDenied) {
      debugPrint('[Main] ⚠️ 通知权限被永久拒绝，需要在系统设置中手动开启');
    }
  }

  // 预加载 access token 到内存缓存，避免 UI 首帧渲染时 cachedAccessToken 为 null
  // 解决 Windows 等平台上封面图和音乐 URL 中 access_token= 为空导致 401 的竞态问题
  // （checkAuth() 使用 Future.microtask 异步执行，比 UI 首帧渲染更晚填充缓存）
  await SecureStorageService().getAccessToken();
  debugPrint(
    '[Main] 预加载 token 完成: cachedAccessToken is ${SecureStorageService.cachedAccessToken != null ? "set" : "null"}',
  );

  // 初始化 audio_service（带降级保护）
  SongloftAudioHandler audioHandler;
  try {
    debugPrint('[Main] 🚀 开始初始化 AudioService...');
    debugPrint('[Main] AudioServiceConfig:');
    debugPrint('[Main]   - channelId: com.songloft.playback');
    debugPrint('[Main]   - channelName: Songloft 播放控制');

    audioHandler = await AudioService.init<SongloftAudioHandler>(
      builder: () {
        debugPrint('[Main] 调用 SongloftAudioHandler builder...');
        return SongloftAudioHandler();
      },
      // androidStopForegroundOnPause 设为 false 保持前台服务持续运行：
      // HyperOS3 等系统在前台服务停止后会激进回收资源，
      // 导致歌曲播放完成后 playNext() 命令失效无法自动切歌
      // 注意：audio_service 要求 androidStopForegroundOnPause=false 时
      // androidNotificationOngoing 也必须为 false
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.songloft.playback',
        androidNotificationChannelName: 'Songloft 播放控制',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
    // 等待 handler 内部初始化完成（AudioSession + stream listeners）
    debugPrint('[Main] 等待 handler 初始化完成...');
    await audioHandler.ensureInitialized();
    debugPrint(
      '[Main] ✅ AudioService 初始化成功, handler type: ${audioHandler.runtimeType}',
    );
  } catch (e, stackTrace) {
    debugPrint('[Main] ❌ AudioService.init 失败: $e');
    debugPrint('[Main] Stack trace: $stackTrace');
    debugPrint('[Main] ⚠️ 使用降级 handler (通知栏功能将不可用)');
    audioHandler = SongloftAudioHandler();
    await audioHandler.ensureInitialized();
  }

  runApp(
    ProviderScope(
      overrides: [
        // 将 audioHandler 注入到 Riverpod 中
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const SongloftApp(),
    ),
  );
}

/// 支持鼠标拖拽滚动的 ScrollBehavior（macOS / desktop）
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class SongloftApp extends ConsumerWidget {
  const SongloftApp({super.key});

  /// 根据屏幕宽度获取 ScreenType
  ScreenType _getScreenType(double width) {
    if (width >= ResponsiveBreakpoints.tv) return ScreenType.tv;
    if (width >= ResponsiveBreakpoints.desktop) return ScreenType.desktop;
    if (width >= ResponsiveBreakpoints.tablet) return ScreenType.tablet;
    return ScreenType.mobile;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Songloft',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScrollBehavior(),
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // 在 builder 中获取 MediaQuery 来应用响应式主题
        final width = MediaQuery.of(context).size.width;
        final screenType = _getScreenType(width);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data:
              isDark
                  ? AppTheme.darkTheme(screenType: screenType)
                  : AppTheme.lightTheme(screenType: screenType),
          child: child!,
        );
      },
    );
  }
}

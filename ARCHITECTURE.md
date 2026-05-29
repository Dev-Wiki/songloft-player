# 项目架构分析

## 模块依赖关系图
- `lib/features/` (业务特性 UI 与逻辑)
  - `lib/shared/` (通用组件、布局、工具)
    - `lib/core/` (核心能力：音频引擎、路由、存储、网络)

## 核心功能流
- 用户操作 UI -> Riverpod State (Notifier) 修改 -> 调用 `lib/core/audio/` Service -> 触发 `just_audio` 播放 -> 状态变化回流 UI。

## 架构模式
- Feature-First (按特性分包) + Riverpod 状态管理。

## 模块接口与通信方式
- **状态同步**: `ref.watch()` / `ConsumerWidget`
- **页面跳转**: `GoRouter` 声明式路由
- **依赖注入**: 纯通过 Riverpod Providers 提供全局实例

## 关键模块标记
- `lib/core/`: 核心基建（audio播放控制, storage本地存储, network请求, router路由, theme主题）。
- `lib/features/`: 核心业务模块（player播放器, playlist歌单, library媒体库, auth认证, settings设置）。
- `lib/shared/`: 跨业务共享组件（widgets通用UI, layouts页面布局, models通用模型）。
- `windows/` / `linux/`: 桌面端原生宿主工程。


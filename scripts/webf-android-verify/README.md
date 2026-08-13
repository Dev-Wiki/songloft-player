# WebF Android verification

This harness builds a plugin and starts a temporary Songloft server on the host.
Docker builds an x86_64 release APK, runs the Android Emulator, installs the
APK, opens the real WebF plugin page, and runs automated verification.

## Downloader plugin test

```bash
./scripts/webf-android-verify/run.sh
```

Builds the downloader plugin, opens its settings page, and verifies switch
alignment from a screenshot. This is the original / primary test.

## MIoT plugin test

```bash
./scripts/webf-android-verify/run-miot-test.sh
```

Builds and uploads the miot plugin (`jsplugins-src/songloft-plugin-miot`),
opens the miot WebF page, navigates to settings, and captures screenshots.
Requires a pre-built APK (run `run.sh` at least once first to build it).

Outputs are written to `scripts/webf-android-verify/out/miot-test/`:

| File | Description |
|------|-------------|
| `miot-main.png` | 主页面截图（歌单选择器、播放栏、控件） |
| `miot-settings.png` | 设置页面截图（分类菜单） |
| `miot-settings-scrolled.png` | 设置页面滚动后截图 |
| `miot-ui.xml` | 主页面 UI 树 dump |
| `miot-settings-ui.xml` | 设置页面 UI 树 dump |
| `miot-logcat.txt` | 完整 logcat 日志 |

验证覆盖点：
- WebF 页面加载成功（无 startupError）
- SlSelect / SlButton / SlIcon 组件渲染
- Player icon font codepoints 映射正确
- PlayerProgress 时间标签显示
- 设置页面高度（100dvh → 100vh fix）生效

## MIoT 播放器控件 / 图标字体竞态

```bash
SHOT_TAG=before SLOW_FONT=3 ./scripts/webf-android-verify/run-player-icons.sh
```

专门盯 miot 的**底部播放条 / 全屏播放器 / 音量弹出层**，产物落在
`out/player-icons/`（`icons-<TAG>-boot1..4` 是进入插件后的首屏连拍，
`-bar` / `-full` / `-volume` / `-back-main` / `-full2` 是各交互步骤）。

`SLOW_FONT=<秒>` 会在设备与后端之间插一个只拖慢 `.otf` 响应的透传代理
（`runner-miot/slow-font-proxy.py`），用来复现 WebF 的 **@font-face 迟到竞态**：

- WebF 的 `@font-face` 是布局期懒加载，字体到货后**只重排「第一个请求者」**
  （`webf/lib/src/css/font_face.dart`）。同一批并发请求者永远拿不到脏标记，
  段落缓存永久停在 fallback 字形。
- 本地 localhost 上字体几乎瞬时到达，**这个 bug 在本地环境是复现不出来的** ——
  必须用这个代理人为拉开延迟，否则会误判为「没问题」。
- 代理**逐条请求**识别（不是只看首行）：Dio 的连接是 keep-alive 复用的，
  字体常常是同一条 TCP 连接上的第 N 个请求，只看首行会全程零命中。

`SHOT_TAG` 区分修复前后两轮截图，方便并排比对。
参考案例：songloft-org/songloft-plugin-miot#81。

> 注意：播放条与全屏播放器需要「已选中设备」才渲染，而测试环境没有真实小米账号。
> 复现这两块时需要临时在插件前端注入假设备/假播放状态（用完删掉，不要提交）。

## Host requirements

Linux with Go, npm, Docker, and `/dev/kvm`. The temporary server listens on
port `58192` (downloader) or `58394` (miot) by default. The Android device
reaches it through `adb reverse`; override with `SERVER_PORT` when needed.

The default emulator is the official Google API 30 x86_64 container image.
Override it when a locally-built newer image is available:

```bash
EMULATOR_IMAGE=us-docker.pkg.dev/android-emulator-268719/images/30-google-x64:30.1.2 \
  ./scripts/webf-android-verify/run.sh
```

Set `KEEP_RUNNING=1` to keep the server and emulator up after a run. Results are
written to `scripts/webf-android-verify/out/`.

The default emulator image is headless and uses ADB. Screenshots are captured
with `adb exec-out screencap -p` by the runner.

# HARNESS

## 项目类型
Flutter 跨平台应用

## 构建命令
`flutter build windows` (或运行 `./scripts/build-frontend.sh windows`)

## 编译启动诊断
- **WorkingDirectory**: `D:\Code\github\songloft-player`
- **RecommendedTerminal**: powershell
- **CanRunBuildHere**: yes
- **MissingCommands**: 无
- **FailureEvidence**: 记录完整命令、工作目录、终端类型、退出码、前 50 行和最后 100 行构建日志

## 快速验证命令
`flutter test`

## Bugfix 验证命令
`flutter analyze && flutter test`

## 完整验证命令
`flutter clean && flutter pub get && flutter analyze && flutter test`

## 高风险目录
- `windows/runner/`: 包含 C++ 宿主桥接，影响 media_kit 音频加载，未经确认禁止修改
- `linux/runner/`: 包含 C++ 宿主桥接，影响 media_kit 音频加载，未经确认禁止修改

## 禁改区域
- .git: version control metadata

## 自动识别候选
- `windows/runner/flutter_window.cpp`: 检测到 Win32 API 使用
- `windows/runner/flutter_window.h`: 检测到 Win32 API 使用
- `windows/runner/main.cpp`: 检测到 Win32 API 使用
- `windows/runner/utils.cpp`: 检测到 Win32 API 使用
- `windows/runner/win32_window.cpp`: 检测到 Win32 API 使用
- `windows/runner/win32_window.h`: 检测到 Win32 API 使用

## 需人工确认
- `windows/runner/flutter_window.cpp` 是否允许 AI 直接修改，需人工确认


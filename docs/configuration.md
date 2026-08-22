# 配置与运行环境

源码和 Xcode 工程设置是 target、build setting 与依赖版本的真源；本页只记录操作边界。

## Targets 与命令

| Target | 用途 | 常用验证 |
| --- | --- | --- |
| `HappyPianistAVP` / `HappyPianistAVPTests` | visionOS App 与 Swift Testing | `make build:simulator`、`make test:simulator` |
| `HappyPianistMac` / `HappyPianistMacTests` | 独立 macOS MusicXML/MIDI host | `make build:mac`、`make test:mac` |
| `Packages/HappyPianistCore` | 共享业务核心 | `swift test --package-path Packages/HappyPianistCore` |

先运行 `make doctor`；`make destinations` 会同时列出 visionOS 与 macOS scheme 的可用 destination。Makefile 使用 Xcode 默认 DerivedData，测试 result bundle 位于 `.build/TestResults`。完整的 timeout、日志和证据要求见[测试](testing.md)。

## App 权限与资源

visionOS target 仅声明实际使用的权限：

- Bluetooth MIDI、麦克风、手部追踪；
- 虚拟钢琴平面放置所需的 world sensing；
- 用户选择 Aria 网络后端时的 Local Network 与 Bonjour `_lpduet._tcp`。

MusicXML 和 MXL 的 imported type 已在两个 App host 声明。仓库中的 `HappyPianistAVP/Resources/SeedScores` 是两个 host 共用的一份内置曲谱资源：两个 target 都打包该目录，并通过 `BundledSongLibraryProvider` 发现。`Packages/RealityKitContent` 承载空间资产；私有 SoundFont、CoreML 模型和未分发的 SeedScores 仍会使相关资源测试跳过，不能视为集成通过。

## 用户设置与可选 Aria 服务

练习范围、左右手、速度、循环、音量、输入/输出端点、round defaults 与 AI backend 都由各自的 settings provider 保存；key、默认值和迁移逻辑以代码为准，新增设置不得绕过 provider 直接散落读写 `UserDefaults`。

Aria v2 是可选的 Mac 本地服务，不是 App 运行前提。安装、启动、smoketest 和网络排查见[Python 后端说明](../python_backend/README.md)。用户选择网络后端后才请求发现和连接；失败不自动回退到其他后端。

## 常见问题

| 现象 | 先检查 |
| --- | --- |
| Simulator 不可用 | `make destinations`、配置的 `SIMULATOR_ID` 与 Xcode 版本。 |
| `make test:simulator` 超时 | `.build/TestResults` 中的 result bundle/Simulator 诊断；保留 timeout，定位卡住的测试或生命周期。 |
| 没有手部或虚拟琴 | 权限、Full Space、provider 状态和真机能力；Simulator 不能证明真实追踪。 |
| 找不到 Aria | 同一局域网、服务端口、防火墙、Bonjour 与模型 checkpoint。 |

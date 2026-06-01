# 配置

## 构建入口

| 项目 | 位置 | 说明 |
| --- | --- | --- |
| Xcode 工程 | `LonelyPianist.xcodeproj` | 包含 macOS app、visionOS app 与测试 target。 |
| macOS scheme | `LonelyPianist` | recorder app 与 `LonelyPianistTests`。 |
| visionOS scheme | `LonelyPianistAVP` | AVP app 与 `LonelyPianistAVPTests`。 |
| Python 工作区（可选） | `python_backend/` | 包含 Aria 模型源码与可运行的本地服务 `python_backend/aria_server/`（用于 AVP 网络即兴后端）。 |

当前仓库没有 `.github/workflows/`，自动化验证以本地命令为准。

## macOS app 配置

| 配置面 | 位置 | 说明 |
| --- | --- | --- |
| 沙盒与权限 | `LonelyPianist/LonelyPianist.entitlements` | App Sandbox、network client、Bluetooth、user-selected read-only files。 |
| 蓝牙说明 | `LonelyPianist/Info.plist` | `NSBluetoothAlwaysUsageDescription` 支持在 app 内打开 Bluetooth MIDI 面板。 |
| 文件类型 | `LonelyPianist/Info.plist` | 导入 MIDI 文件。 |
| 持久化 | `ModelContainerFactory` | SwiftData store 名为 `LonelyPianist.store`。 |
| 回放输出 | recorder UI + `RoutedMIDIPlaybackService` | 内建 sampler 或外部 MIDI destination。 |

## visionOS app 配置

| 配置面 | 位置 | 说明 |
| --- | --- | --- |
| 权限说明 | `LonelyPianistAVP/Resources/Info.plist` | Hand Tracking、World Sensing、Microphone、Bluetooth。 |
| 网络（可选） | `LonelyPianistAVP/Resources/Info.plist` | 为网络即兴后端（Aria v2）预留 Local Network + Bonjour：`NSLocalNetworkUsageDescription`、`NSBonjourServices = _lpduet._tcp`、`NSAllowsLocalNetworking = true`。仅当用户在练习设置中选择网络后端时才会使用。 |
| MusicXML 文件类型 | `UTImportedTypeDeclarations` | 导入 `.musicxml` / `.xml`。 |
| 字体 | `UIAppFonts` | `Bravura.otf`。 |
| soundfont | `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2` | 仓库默认不内置；需要本地 sampler 回放时手动放入。 |

`PracticeSessionSettingsProvider` 使用 `UserDefaults` 保存练习相关设置；修改时优先从 provider 和对应 UI 查找真实 key。

### 可选：启动 Aria v2 网络后端（Mac）

用于 AVP 真机选择 `网络本地连接（Aria v2）` / `网络本地连接（Aria v2 Streaming）` 时连接：

```bash
cd python_backend/aria_server && uv sync
cd .. && uv run --project aria_server python scripts/aria_server.py --host 0.0.0.0 --port 8766
```

更多说明见 `python_backend/README.md`。

### 练习发声路由与音量（AVP）

以下键值由 `UserDefaultsPracticeSessionSettingsProvider` 与练习设置 UI 共同维护（以代码为准）：

| Key | 说明 |
| --- | --- |
| `practiceSoundOutputRoute` | 发声路由：`localSampler`（仅 AVP 发声）或 `externalMIDIDestination`（仅真实钢琴发声）。 |
| `practiceMIDIDestinationUniqueID` | 外部 MIDI 输出目的地的 `kMIDIPropertyUniqueID`（`Int32`，可能为负数；`0` 表示未选择）。 |
| `practiceSendLocalControlOff` | 是否 best-effort 向目的地发送 Local Control Off（CC122）。兼容性不保证，默认关闭。 |
| `AudioOutputVolumeSettings.userDefaultsKey` | AVP 本地采样器输出音量（0…1）。仅影响 AVP sampler，不影响外部 MIDI 发往真实钢琴的力度/音量。 |

说明（练习判定与设置项）：
- “练习判定：左右手分别满足”已改为强制启用（不再作为可配置项，也不再暴露 UI 开关）。
- 当前仍会通过 `UserDefaults` 保存练习手（左/右/双手）、手动推进方式与音频识别模式等设置项。

## 常见误配

| 现象 | 可能原因 | 检查点 |
| --- | --- | --- |
| AI 对弹不可用 | CoreML 模型文件未加入 app bundle | 练习设置页的后端状态提示；检查 `AIDuetPerformanceRNN.mlpackage` / `AIDuetPerformanceRNN.mlmodelc`。 |
| 网络后端不可用/找不到 | Mac 未启动 Aria 服务或 Local Network 权限被拒绝 | Mac 先启动 `python_backend/aria_server/`；AVP 真机允许 Local Network；确认同一局域网与防火墙设置。 |
| BLE MIDI source 不显示 | Bluetooth 权限或系统连接未完成 | `CABTMIDICentralViewController` 面板、系统蓝牙、app Bluetooth 权限。 |
| 真实音频模式无法推进 | Microphone 权限、输入源噪声、音频识别阈值 | `PracticeAudioRecognitionService` 状态与 debug snapshot。 |
| 虚拟钢琴无法继续 | 平面检测或放置确认未完成 | `VirtualPianoPlacementViewModel`、`GazePlaneHitTestService`。 |
| CoreML 首次加载慢 | `.mlpackage` 首次运行会触发编译 | 属正常现象；建议提交 `.mlmodelc` 或预先编译。 |

## 代码格式化（SwiftFormat）

仓库根目录提供 `.swiftformat` 配置文件，供 `swiftformat`（nicklockwood/SwiftFormat）统一 Swift 代码风格。

常用命令（需本机安装 SwiftFormat）：
- `brew install swiftformat`：通过 Homebrew 安装命令行工具。
- `swiftformat .`：格式化整个仓库（会跳过 `.swiftformat` 中 `--exclude` 的目录）。
- `swiftformat . --lint`：仅检查格式差异，不改文件。

# 配置

## 构建入口

| 项目 | 位置 | 说明 |
| --- | --- | --- |
| Xcode 工程 | `LonelyPianist.xcodeproj` | 包含 macOS app、visionOS app 与测试 target。 |
| macOS scheme | `LonelyPianist` | recorder app 与 `LonelyPianistTests`。 |
| visionOS scheme | `LonelyPianistAVP` | AVP app 与 `LonelyPianistAVPTests`。 |
| Python 服务 | `piano_dialogue_server/scripts/run_server.sh` | 创建 `.venv`、安装依赖并启动 uvicorn。 |

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
| 权限说明 | `LonelyPianistAVP/Resources/Info.plist` | Hand Tracking、World Sensing、Microphone、Bluetooth、Local Network。 |
| Bonjour | `NSBonjourServices` | `_lonelypianist._tcp`，用于发现本地 Python 后端。 |
| ATS local networking | `NSAppTransportSecurity` | 允许局域网 HTTP 连接。 |
| MusicXML 文件类型 | `UTImportedTypeDeclarations` | 导入 `.musicxml` / `.xml`。 |
| 字体 | `UIAppFonts` | `Bravura.otf`。 |
| soundfont | `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2` | 仓库默认不内置；需要本地 sampler 回放时手动放入。 |

`PracticeSessionSettingsProvider` 使用 `UserDefaults` 保存练习相关设置；修改时优先从 provider 和对应 UI 查找真实 key。

说明（练习判定与设置项）：
- “练习判定：左右手分别满足”已改为强制启用（不再作为可配置项，也不再暴露 UI 开关）。
- 当前仍会通过 `UserDefaults` 保存练习手（左/右/双手）、手动推进方式与音频识别模式等设置项。

## Python 服务配置

| 项 | 默认值 / 位置 | 说明 |
| --- | --- | --- |
| host | `0.0.0.0` in `piano_dialogue_server/scripts/run_server.sh` | 便于 AVP 真机访问。 |
| port | `8765` | HTTP、WebSocket 与 Bonjour 广播使用同一端口。 |
| Bonjour service type | `_lonelypianist._tcp.local.` | `piano_dialogue_server/server/media/bonjour.py` 与 AVP discovery 对齐。 |
| `AMT_MODEL_DIR` | 无默认硬编码目录优先级之一 | 本地模型目录。 |
| `AMT_MODEL_ID` | `stanford-crfm/music-large-800k` | Hugging Face 模型 ID。 |
| `AMT_DEVICE` | 自动选择 | `mps` / `cuda` / `cpu`。 |
| `HF_ENDPOINT` | 可选 | Hugging Face 镜像地址。 |
| `DIALOGUE_DEBUG` | unset | 设为 `1` 时写调试包。 |

## 常见误配

| 现象 | 可能原因 | 检查点 |
| --- | --- | --- |
| AVP 找不到后端 | Python 服务未启动、Local Network 权限被拒、设备不在同一局域网 | `/health`、Bonjour 日志、visionOS 设置中的 Local Network 权限。 |
| BLE MIDI source 不显示 | Bluetooth 权限或系统连接未完成 | `CABTMIDICentralViewController` 面板、系统蓝牙、app Bluetooth 权限。 |
| 真实音频模式无法推进 | Microphone 权限、输入源噪声、音频识别阈值 | `PracticeAudioRecognitionService` 状态与 debug snapshot。 |
| 虚拟钢琴无法继续 | 平面检测或放置确认未完成 | `VirtualPianoPlacementViewModel`、`GazePlaneHitTestService`。 |
| Python 首次生成很慢 | 使用 `strategy=model` 加载模型 | 使用 `strategy=rule` 或 `strategy=deterministic` 验证轻量链路。 |

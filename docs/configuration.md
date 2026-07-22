# 配置

## Xcode 工程

| 项目 | 当前值 |
| --- | --- |
| 工程 | `HappyPianist.xcodeproj` |
| App target / scheme | `HappyPianistAVP` |
| Test target | `HappyPianistAVPTests` |
| App / Test target Swift language mode | 6.0 |
| RealityKitContent manifest | `swift-tools-version: 6.2`，visionOS 26 |
| 部署目标 | visionOS 26.0 |
| 支持平台 | `xros`、`xrsimulator` |
| SwiftPM | 本地 `RealityKitContent`、远程 `ZIPFoundation` 0.9.20 |
| 本地开发入口 | 根目录 `Makefile`；结果包写入 `.build/TestResults/`，DerivedData 使用 Xcode 默认目录 |

仓库没有 macOS App target。日常本地构建和测试使用 Makefile：`make doctor` 检查工具链，`make config` 查看本机解析配置，`make destinations` 列出目标，`make test` 运行配置好的 visionOS Simulator 测试。Makefile 默认的 Simulator / Vision Pro ID 属于本机配置，运行时可覆盖 `SIMULATOR_ID` 或 `DEVICE_ID`。

`.github/workflows/swift-ci.yml` 通过 Makefile 执行测试：先在 runner 上解析可用的 `Apple Vision Pro` UDID，再注入 `SIMULATOR_ID` 调用 `make test`。workflow 仅支持手动触发，运行在 `macos-26`，通过 `DEVELOPER_DIR` 固定到 `/Applications/Xcode_26.6.app/Contents/Developer`；Makefile 内部实际调用原生 `xcodebuild test`。需要精确复现或 Makefile 未覆盖的场景时，本地仍可直接调用 `xcodebuild`。

## 依赖边界

- `RealityKitContent` 是仓库内仅支持 visionOS 26 的 SwiftPM 内容包。
- `ZIPFoundation` 0.9.20 用于解包 `.mxl`；普通 MusicXML 不依赖它。
- SwiftPM 锁定版本见 `HappyPianist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。
- 正常练习不依赖 Python 服务；本地规则 AI 也不依赖 CoreML 模型或 Python。
- Apple framework 的最终行为只能在 Xcode、Simulator 或设备环境中验证。

## Info.plist 与权限

配置文件：`HappyPianistAVP/Resources/Info.plist`。

| Key | 用途 |
| --- | --- |
| `NSHandsTrackingUsageDescription` | 手部追踪和按键接触。 |
| `NSWorldSensingUsageDescription` | 虚拟钢琴平面检测。 |
| `NSMicrophoneUsageDescription` | 真实钢琴音频识别。 |
| `NSBluetoothAlwaysUsageDescription` | Bluetooth MIDI。 |
| `NSLocalNetworkUsageDescription` | 可选 Aria v2 网络后端。 |
| `NSBonjourServices` | `_lpduet._tcp` 服务发现。 |
| `NSAllowsLocalNetworking` | 本地 HTTP/WS 连接。 |
| `UTImportedTypeDeclarations` | `.musicxml` 与 `.mxl`；`.xml` 通过文件 importer 接受。 |
| `UIAppFonts` | 声明 `Fonts/Bravura.otf`。 |

权限只应在对应功能实际启用时请求。ARKit provider 只在沉浸空间内运行。

## 资源边界

仓库包含 `HappyPianistAVP/Resources/Fonts/Bravura.otf`。源码不提交按曲目子目录组织的 `SeedScores/`；开发者可在本地将其放入 `HappyPianistAVP/Resources/`。内置曲谱以 `SeedScores` 下的相对路径作为唯一身份，MusicXML 与同目录 MP3 成对发现；不要把目录展平后再按 basename 去重。

以下资源必须由开发者自行加入 App target：

| 文件 | 消费方 | 缺失行为 |
| --- | --- | --- |
| `SalC5Light2.sf2` | `AVAudioSequencerPracticePlaybackService` | 本地 sampler 返回“未找到音色文件”。 |
| `AIDuetPerformanceRNN.mlpackage` 或 `.mlmodelc` | `PerformanceRNNCoreMLModelLoader` | 本地 CoreML 后端不可用。 |

依赖私有 `SeedScores` 或 CoreML 模型的集成测试在资源缺失时会跳过。不要用 `Info.plist` 声明、代码中的资源名、测试跳过或旧测试记录代替实际 bundle 检查。

## 练习设置

`UserDefaultsPracticeSessionSettingsProvider` 读取以下 key：

| Key | 含义 |
| --- | --- |
| `practiceManualAdvanceMode` | 手动推进策略。 |
| `practiceHandMode` | 左手、右手或双手。 |
| `practiceStep3AudioRecognitionMode` | 音频识别 detector。 |
| `practiceSoundOutputRoute` | `localSampler` 或 `externalMIDIDestination`。 |
| `practiceMIDIDestinationUniqueID` | CoreMIDI destination unique ID；`0` 或缺失表示未选择。 |
| `practiceSendLocalControlOff` | 是否发送 Local Control Off（CC122）。 |
| `practiceTempoScale` | 下一轮速度比例。 |
| `practiceLoopEnabled` | 下一轮是否循环。 |
| `practiceRequiredSuccesses` | 连续成功目标。 |
| `practiceImprovBackendKind` | AI 即兴后端选择。 |
| `audioOutputVolume` | AVP 本地 sampler 与试听音频音量，范围 0...1。 |

练习配置分为：

- UserDefaults 中的长期默认值
- 下一轮 pending configuration
- 当前轮 immutable active configuration

修改手别、速度、循环和成功目标时，不得直接改变正在进行的一轮。

## 手部触键校准

`PianoTouchCalibration` 是真实钢琴和虚拟琴共用的版本化触键契约，但两种模式使用各自的保守默认值。真实钢琴的校准随现有 world-anchor JSON 保存；虚拟琴使用 composition root 注入的当前默认值。解码只接受当前版本，不提供旧字段或旧版本 fallback。

| 参数 | 作用 | 调整依据 |
| --- | --- | --- |
| `planeOffsetMeters` | 键面下压触发距离 | 真机键面偏差与手部追踪噪声 |
| `releaseHysteresisMeters` | 释放阈值相对触发阈值的滞回 | 消除键面附近抖动且不拖慢重复音 |
| `minimumStrikeSpeedMetersPerSecond` | 可发声的最低向下速度 | 排除悬停和慢压误触发 |
| `fullScaleStrikeSpeedMetersPerSecond` | 映射到最大力度的速度 | 设备与演奏者的重击样本 |
| `minimumVelocity` / `maximumVelocity` | MIDI velocity 输出范围 | 目标音源的有效动态范围 |
| `curveExponent` | 速度到力度的曲线形状 | 轻、中、重三档实测手感 |
| `retriggerDebounceSeconds` | 同指再次触发的最短间隔 | 快速重复音与 tracking jitter |

真机调整时记录 calibration ID/version、设备、OS、模式、聚合 velocity/latency 桶和误触发计数即可。原始逐帧 finger、palm、world position 属于隐私敏感数据，不得写入 JSON、诊断日志或导出文件。

## 发声路由

| 路由 | 实现 | 说明 |
| --- | --- | --- |
| 仅 AVP 发声 | `AVAudioSequencerPracticePlaybackService` | 需要 `SalC5Light2.sf2`。 |
| 仅真实钢琴发声 | `CoreMIDIPracticePlaybackService` | 需要有效 MIDI destination。 |

`practiceSendLocalControlOff` 是 best-effort 选项，默认关闭；不同钢琴对 CC122 的支持不一致。

## 可选 Aria v2 服务

安装并启动：

```bash
cd python_backend/aria_server
uv sync

cd ..
uv run --project aria_server \
  python scripts/aria_server.py \
  --host 0.0.0.0 \
  --port 8766
```

本机 smoketest：

```bash
cd python_backend
uv run --project aria_server \
  python scripts/aria_server_smoketest.py \
  --host 127.0.0.1 \
  --port 8766

uv run --project aria_server \
  python scripts/ws_client_smoketest.py \
  ws://127.0.0.1:8766/stream
```

前提：

- Python 3.11+
- `uv`
- `python_backend/aria/hf/model-demo.safetensors`
- Mac 与 Vision Pro 位于同一局域网
- Vision Pro 允许 Local Network 权限

## 常见误配

| 现象 | 检查点 |
| --- | --- |
| 五线谱符号异常 | `Bravura.otf` 是否实际在 App target 的 Copy Bundle Resources。 |
| 本地回放无声 | `SalC5Light2.sf2` 是否在 bundle；设置是否选择本地 sampler。 |
| CoreML 后端不可用 | 模型文件是否在 bundle；设置页后端状态。 |
| 找不到 Aria 服务 | 服务是否监听 `0.0.0.0`、防火墙、同一 Wi-Fi、Bonjour 与 Local Network 权限。 |
| BLE MIDI source 为空 | 系统 Bluetooth MIDI 面板、蓝牙权限和 CoreMIDI source。 |
| 麦克风模式不推进 | 麦克风权限、输入设备、噪声与 detector 状态。 |
| 虚拟琴无法继续 | 平面检测、放置确认和沉浸空间状态。 |

## SwiftFormat

仓库根目录提供 `.swiftformat`：

```bash
swiftformat . --lint
swiftformat .
```

运行前需本机安装 SwiftFormat。

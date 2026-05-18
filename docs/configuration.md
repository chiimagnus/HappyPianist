# 配置

## 运行时配置入口
| 配置面 | 位置 | 默认 / 结果 |
| --- | --- | --- |
| Dialogue 打断策略 | macOS `UserDefaults` | `.interrupt` |
| 录制 / 播放输出 | macOS playback UI | built-in sampler fallback |
| AVP MusicXML 选项 | `UserDefaults` | structure / wedge / grace / fermata / arpeggiate / words semantics |
| Python 模型选择 | 环境变量 | 本地目录优先，其次 `AMT_MODEL_ID` |
| CI workflows | （无） | 当前仓库不包含 `.github/workflows/` |

## 关键默认值
| 配置项 | 默认值 | 影响 |
| --- | --- | --- |
| Dialogue WS | `ws://127.0.0.1:8765/ws` | 对话连接 |
| AVP 后端发现 | `_lonelypianist._tcp.local.` | Bonjour 自动发现与解析 host/port |
| AVP 后端生成 | `POST http://<host>:8765/generate` | 即兴生成请求 |
| Silence window | `2.0s` | phrase 触发 |
| Provider timeout | `5s` | AVP 启动等待 |
| Localization timeout | `5s` | Step 3 失败门槛 |
| Press cooldown | `0.15s` | 手部按键去抖 |
| Chord window | `0.6s` | 和弦累积 |
| Practice note tolerance | `±1` 半音 | 练习匹配 |
| Hand-separated step matching | `false`（UserDefaults key: `practiceHandSeparatedStepMatchingEnabled`） | 开启后 step 通过判定要求左右手分别满足（默认关闭） |
| Guide decal alpha | `0.32` | 当前 step 的琴键贴皮高亮整体 alpha |
| Guide decal texture | `KeyDecalSoftRect` | 柔边矩形贴图（key-top decal） |
| Guide decal epsilon | `0.0015` meter | 贴皮与琴键表面的最小抬升，避免 z-fighting（见 `PianoGuideBeamDescriptor`） |

> 说明：单谱表 MusicXML 的自动分手（补 staff=1/2）当前**不提供回退开关**；行为属于导入管线固定逻辑（见 `MusicXMLHandRouter`）。

## 构建与工程配置
| 项目 | 位置 | 说明 |
| --- | --- | --- |
| Xcode 工程 | `LonelyPianist.xcodeproj/project.pbxproj` | macOS / AVP / Tests |
| macOS shared scheme | `LonelyPianist.xcodeproj/xcshareddata/xcschemes/LonelyPianist.xcscheme` | 本地 `xcodebuild test` 使用入口 |
| AVP scheme | `LonelyPianistAVP` | 本地 `xcodebuild test`（visionOS simulator）使用入口 |
| RealityKitContent 平台 | `Packages/RealityKitContent/Package.swift` | Swift tools 6.2，需 Xcode 26.2+ / Swift 6.2+ |
| Deployment targets | `LonelyPianist.xcodeproj/project.pbxproj` | macOS 26.0 / visionOS 26.0 |

## 自动化现状
当前仓库未提交 GitHub Actions workflows（`.github/workflows/` 不存在），因此没有 PR 自动测试/格式化；验证以本地 `xcodebuild test` 为准。

## 权限与 entitlements
| 文件 | 说明 |
| --- | --- |
| `LonelyPianist/LonelyPianist.entitlements` | sandbox、network client、user-selected files、Bluetooth（用于在 App 内打开系统 Bluetooth MIDI 连接窗口） |
| `LonelyPianistAVP/Info.plist` | `NSHandsTrackingUsageDescription`、`NSWorldSensingUsageDescription`（平面检测）、`NSBluetoothAlwaysUsageDescription`（蓝牙 MIDI 连接与 sources 可见性）、`NSLocalNetworkUsageDescription`（后端发现/连接）、`NSBonjourServices`（`_lonelypianist._tcp`）+ ATS local networking + MusicXML 导入类型 |
| `LonelyPianist/Info.plist` | macOS app 基本信息、`NSBluetoothAlwaysUsageDescription`（蓝牙 MIDI 连接） |

## Python 环境变量
| 变量 | 含义 | 来源 |
| --- | --- | --- |
| `AMT_MODEL_DIR` | 本地模型目录 | `server/engines/model_inference.py` |
| `AMT_MODEL_ID` | HuggingFace 模型 ID | `server/engines/model_inference.py` |
| `AMT_DEVICE` | `mps` / `cuda` / `cpu` | `server/engines/model_inference.py` |
| `DIALOGUE_DEBUG` | 是否落盘调试包 | `server/media/debug_artifacts.py` |
| `HF_ENDPOINT` | HF 镜像地址 | `server/engines/model_inference.py` |

## 误配和后果
| 误配 | 后果 | 修复 |
| --- | --- | --- |
| 未授权 Accessibility | macOS 不能注入按键 | 重新授权 |
| Bluetooth 权限被拒绝（macOS / AVP） | App 内 `Bluetooth MIDI…` 无法连接 BLE MIDI / 可能出现 “not supported / unknown error” | System Settings → Privacy & Security → Bluetooth → 允许 `LonelyPianist`（AVP 侧可从 App 内弹窗“打开设置”进入） |
| 系统蓝牙关闭 | BLE MIDI 无法发现/连接 | 打开系统蓝牙后重试 |
| 未启动 Python 服务 | Dialogue 无回复 | 启动 uvicorn |
| 模型目录无权重 | 服务启动或首个 generate 失败 | 补齐权重文件 |
| AVP Local Network denied | Bonjour 发现为 `.denied`，无法自动连接后端 | 重新允许本 app 的 Local Network 权限 |
| 没有 stored calibration | AVP Step 3 无法定位 | 回 Step 1 |
| 曲库索引和文件不一致 | 选曲失败 / 试听失败 | 重新导入或清理残留 |
| AVP test destination 变更 | `xcodebuild` 找不到 Apple Vision Pro simulator | 先跑 `xcodebuild -showdestinations` 再调整 destination |

## Coverage Gaps
- Python 依赖没有 lockfile；环境变量也没有统一 `.env.example`。
- 当前无 CI workflows，所有测试/格式化均为本地手动执行。
- AVP simulator tests 已验证可跑，但耗时高于 macOS tests；若后续不稳定，可拆为 `build-for-testing` 和手动完整 test。

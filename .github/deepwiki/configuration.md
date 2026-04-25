# 配置

## 运行时配置入口
| 配置面 | 位置 | 默认 / 结果 |
| --- | --- | --- |
| Dialogue 打断策略 | macOS `UserDefaults` | `.interrupt` |
| 录制 / 播放输出 | macOS playback UI | built-in sampler fallback |
| AVP MusicXML 选项 | `UserDefaults` | structure / wedge / grace / fermata / arpeggiate / words semantics |
| Python 模型选择 | 环境变量 | 本地目录优先，其次 `AMT_MODEL_ID` |
| PR Tests | `.github/workflows/pr-tests.yml` | 只在 PR 上按路径分流 macOS / AVP tests |
| Swift Quality | `.github/workflows/swift-quality.yml` | 只手动触发 SwiftFormat + SwiftLint |

## 关键默认值
| 配置项 | 默认值 | 影响 |
| --- | --- | --- |
| Dialogue WS | `ws://127.0.0.1:8765/ws` | 对话连接 |
| Silence window | `2.0s` | phrase 触发 |
| Provider timeout | `5s` | AVP 启动等待 |
| Localization timeout | `5s` | Step 3 失败门槛 |
| Press cooldown | `0.15s` | 手部按键去抖 |
| Chord window | `0.6s` | 和弦累积 |
| Practice note tolerance | `±1` 半音 | 练习匹配 |
| Guide beam height | `0.18` meter | 当前 step 的空间丁达尔光束高度（从 key surface 起） |
| Guide beam alpha | `0.32` | 光束整体 alpha（叠乘贴图透明度） |
| Guide beam atlas | `KeyBeamFourSideAtlas` | 四侧面 warm-gold 透明贴图 |

## 构建与工程配置
| 项目 | 位置 | 说明 |
| --- | --- | --- |
| Xcode 工程 | `LonelyPianist.xcodeproj/project.pbxproj` | macOS / AVP / Tests |
| macOS shared scheme | `LonelyPianist.xcodeproj/xcshareddata/xcschemes/LonelyPianist.xcscheme` | macOS CI 使用入口 |
| AVP scheme | `LonelyPianistAVP` | 已在 GitHub Actions 上通过 `xcodebuild -list` 和 AVP simulator test 验证 |
| RealityKitContent 平台 | `Packages/RealityKitContent/Package.swift` | Swift tools 6.2，需 Xcode 26.2+ / Swift 6.2+ |
| Deployment targets | `LonelyPianist.xcodeproj/project.pbxproj` | macOS 26.0 / visionOS 26.0 |
| SwiftFormat config | `.swiftformat` | Swift Quality workflow 使用 |
| SwiftLint config | `.swiftlint.yml` | Swift Quality workflow 使用 |

## GitHub Actions 配置
| Workflow | 触发 | Runner | 关键配置 |
| --- | --- | --- | --- |
| `PR Tests` | `pull_request` + path filters | `ubuntu-latest` + `macos-26` | `dorny/paths-filter@v3` 输出 macOS/AVP job 条件 |
| macOS tests | macOS 路径或 project/workflow 变更 | `macos-26` | `xcodebuild test -scheme LonelyPianist -destination 'platform=macOS'` |
| AVP tests | AVP 路径、RealityKitContent、project/workflow 变更 | `macos-26` | `xcodebuild test -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` |
| `Swift Quality` | `workflow_dispatch` only | `macos-latest` | brew 安装 SwiftFormat/SwiftLint，自动修复后 commit/push |

## PR path filters
| Filter | 匹配路径 | 运行 job |
| --- | --- | --- |
| `macos` | `LonelyPianist/**`, `LonelyPianistTests/**`, `LonelyPianist.xcodeproj/**`, `.github/workflows/pr-tests.yml` | macOS tests |
| `avp` | `LonelyPianistAVP/**`, `LonelyPianistAVPTests/**`, `Packages/RealityKitContent/**`, `LonelyPianist.xcodeproj/**`, `.github/workflows/pr-tests.yml` | AVP tests |

## 权限与 entitlements
| 文件 | 说明 |
| --- | --- |
| `LonelyPianist/LonelyPianist.entitlements` | sandbox、network client、user-selected files |
| `LonelyPianistAVP/Info.plist` | `NSHandsTrackingUsageDescription` + MusicXML 导入类型 |
| `LonelyPianist/Info.plist` | macOS app 基本信息 |
| `.github/workflows/swift-quality.yml` | `contents: write`，允许 bot commit formatter updates |
| `.github/workflows/pr-tests.yml` | `contents: read`，只读 checkout 和测试 |

## Python 环境变量
| 变量 | 含义 | 来源 |
| --- | --- | --- |
| `AMT_MODEL_DIR` | 本地模型目录 | `server/inference.py` |
| `AMT_MODEL_ID` | HuggingFace 模型 ID | `server/inference.py` |
| `AMT_DEVICE` | `mps` / `cuda` / `cpu` | `server/inference.py` |
| `DIALOGUE_DEBUG` | 是否落盘调试包 | `server/debug_artifacts.py` |
| `HF_ENDPOINT` | HF 镜像地址 | `server/inference.py` |

## 误配和后果
| 误配 | 后果 | 修复 |
| --- | --- | --- |
| 未授权 Accessibility | macOS 不能注入按键 | 重新授权 |
| 未启动 Python 服务 | Dialogue 无回复 | 启动 uvicorn |
| 模型目录无权重 | 服务启动或首个 generate 失败 | 补齐权重文件 |
| 没有 stored calibration | AVP Step 3 无法定位 | 回 Step 1 |
| 曲库索引和文件不一致 | 选曲失败 / 试听失败 | 重新导入或清理残留 |
| `macos-latest` 用于 Xcode tests | Swift tools 6.2 package graph 可能失败 | PR Tests 使用 `macos-26` |
| AVP test destination 变更 | `xcodebuild` 找不到 Apple Vision Pro simulator | 先跑 `xcodebuild -showdestinations` 再调整 destination |
| Swift Quality 在 PR 中自动触发 | workflow 可能自改 PR 分支并循环 | 当前只保留手动触发 |

## Coverage Gaps
- Python 依赖没有 lockfile；环境变量也没有统一 `.env.example`。
- Python smoke tests 尚未进入 GitHub Actions。
- AVP simulator tests 已验证可跑，但耗时高于 macOS tests；若后续不稳定，可拆为 `build-for-testing` 和手动完整 test。

## 更新记录（Update Notes）
- 2026-04-25: 更新 PR-only split tests、manual-only Swift Quality、`macos-26`、Swift tools 6.2 和 AVP light beam 参数。

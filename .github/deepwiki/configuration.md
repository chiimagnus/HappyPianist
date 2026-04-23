# 配置

## 运行时配置入口
| 配置面 | 位置 | 默认 / 结果 |
| --- | --- | --- |
| Dialogue 打断策略 | macOS `UserDefaults` | `.interrupt` |
| 录制 / 播放输出 | macOS playback UI | built-in sampler fallback |
| AVP MusicXML 选项 | `UserDefaults` | structure / wedge / grace / fermata / arpeggiate / words semantics |
| Python 模型选择 | 环境变量 | 本地目录优先，其次 `AMT_MODEL_ID` |

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

## 构建与工程配置
| 项目 | 位置 | 说明 |
| --- | --- | --- |
| Xcode 工程 | `LonelyPianist.xcodeproj/project.pbxproj` | macOS / AVP / Tests |
| macOS shared scheme | `LonelyPianist.xcodeproj/xcshareddata/xcschemes/LonelyPianist.xcscheme` | 共享构建入口 |
| AVP scheme | 当前仓库中未见共享 scheme | 需要本地 Xcode 环境 |
| RealityKitContent 平台 | `Packages/RealityKitContent/Package.swift` | visionOS 兼容 |

## 权限与 entitlements
| 文件 | 说明 |
| --- | --- |
| `LonelyPianist/LonelyPianist.entitlements` | sandbox、network client、user-selected files |
| `LonelyPianistAVP/Info.plist` | `NSHandsTrackingUsageDescription` + MusicXML 导入类型 |
| `LonelyPianist/Info.plist` | macOS app 基本信息 |

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

## Coverage Gaps
- Python 依赖没有 lockfile；环境变量也没有统一 `.env.example`。

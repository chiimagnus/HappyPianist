# 依赖关系

## 技术栈
| 维度 | 技术 | 作用 |
| --- | --- | --- |
| Swift 工具链 | Xcode 26 / Swift 6.2 | app target + SwiftPM package |
| macOS UI | SwiftUI + Observation | 页面和状态 |
| macOS 系统能力 | CoreMIDI / AppKit / AVFAudio / CoreGraphics | 输入、按键注入、回放 |
| 持久化 | SwiftData | mapping config + takes |
| visionOS UI | SwiftUI + RealityKit + ARKit | 窗口、沉浸空间、手部和世界追踪 |
| 资源包 | RealityKitContent | visionOS 场景内容 |
| Python 服务 | FastAPI + websockets + Uvicorn + zeroconf | HTTP/WS 生成 + Bonjour 广播 + MIDI 上传扩展 |
| 推理 | torch + transformers + anticipation | 回复生成 |
| 音乐符号字体 | Bravura（SMuFL） | 五线谱渲染（谱号/调号/拍号/升降号） |
| 压缩解包 | ZIPFoundation | MusicXML `.mxl` 解包 |

## 第三方依赖
| 依赖 | 用途 | 风险 |
| --- | --- | --- |
| `torch` | 模型加载和执行 | MPS/CUDA 差异 |
| `transformers` | CausalLM 加载 | 权重格式变化 |
| `anticipation` | token 采样 | 上游语义变动会影响输出 |
| `websockets` | `test_client.py` | 仅用于离线冒烟 |
| `mido` | MIDI 调试和测试脚本 | MIDI 文件结构要求 |
| `zeroconf` | Bonjour（mDNS/DNS-SD）广播 | 网络环境与权限差异 |
| `ZIPFoundation` | `.mxl` 解包 | 压缩包损坏会失败 |

## 第一方模块
| 模块 | 位置 | 说明 |
| --- | --- | --- |
| macOS app | `LonelyPianist/` | 主业务面 |
| AVP app | `LonelyPianistAVP/` | 三步练习面 |
| Dialogue service | `piano_dialogue_server/server/` | Python 对话服务（`api/` + `engines/` + `media/`） |
| RealityKitContent | `Packages/RealityKitContent/` | visionOS 内容包 |

## 外部服务与平台
| 服务 / 平台 | 调用方 | 接口 |
| --- | --- | --- |
| 本地 Python WS 服务 | macOS Dialogue | `ws://127.0.0.1:8765/ws` |
| 本地 Python HTTP 服务 | AVP Improv | `http://<resolved-host>:8765/generate`（host 由 Bonjour 发现/解析） |
| HuggingFace 镜像 | Python inference | 模型下载 |
| macOS Accessibility | `KeyboardEventService` | 全局按键注入 |
| Apple ARKit 权限 | `ARTrackingService` | Hand/World tracking |
| Local Network / Bonjour | `BonjourBackendDiscoveryService` | 浏览 `_lonelypianist._tcp.local.` |

## 构建与工具
| 工具 | 用途 | 约束 |
| --- | --- | --- |
| `xcodebuild` | macOS / visionOS build & test | 仓库级默认命令 |
| `python -m uvicorn server.api.main:app` | 启动服务 | 建议 `--host 0.0.0.0 --port 8765`（局域网可见） |
| `./scripts/run_server.sh` | 一键启动服务 | 自动创建 venv + 安装依赖 + 启动 uvicorn |
| `python scripts/test_generate.py` | 离线生成 sanity check | 改动 inference 时用 |
| `python -m server.api.test_client` | WS 回环测试 | 需要先启动服务（在 `piano_dialogue_server/` 下运行） |

## 配置耦合
| 配置 | 关联代码 | 影响 |
| --- | --- | --- |
| `AMT_MODEL_DIR` / `AMT_MODEL_ID` | `server/engines/model_inference.py` | 模型定位 |
| `AMT_DEVICE` | `server/engines/model_inference.py` | 执行设备 |
| `DIALOGUE_DEBUG` | `server/media/debug_artifacts.py` | 调试包写盘 |
| `practiceMusicXML*` defaults | AVP ViewModels | MusicXML 解析和步骤生成 |
| `DialoguePlaybackInterruptionBehavior` | macOS ViewModel | AI 回放期间输入策略 |
| `XROS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` | `project.pbxproj` | 当前工程目标为 26.0 |

## Coverage Gaps
- 没有统一 lockfile；Python 依赖和模型权重都依赖本地环境管理。

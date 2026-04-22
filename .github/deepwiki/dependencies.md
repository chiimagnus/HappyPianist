# 依赖关系

## 技术栈矩阵
| 维度 | 技术 / 框架 | 版本 / 约束 | 用途 |
| --- | --- | --- | --- |
| macOS 前端 | SwiftUI + Observation | Swift 6 / Xcode 26.x 工程 | UI 与状态编排 |
| MIDI / 试听播放 | CoreMIDI / AVFoundation | Apple 系统框架 | 实时输入、回放与试听 |
| 持久化 | SwiftData | App Support 下本地 store | 映射配置与录音 take |
| visionOS 空间层 | RealityKit + ARKit | visionOS 26+ | 手部追踪与空间高亮 |
| Python 服务层 | FastAPI + Uvicorn + websockets | `requirements.txt` | WS 对话 |
| 推理层 | torch + transformers + anticipation | `requirements.txt` | 对话音符生成 |

## 第一方模块 / 包
| 模块 / 包 | 位置 | 产物 | 被谁依赖 |
| --- | --- | --- | --- |
| LonelyPianist | `LonelyPianist/` | `LonelyPianist.app` | 用户主入口 |
| LonelyPianistTests | `LonelyPianistTests/` | `LonelyPianistTests.xctest` | 本地单元测试 |
| LonelyPianistAVP | `LonelyPianistAVP/` | `LonelyPianistAVP.app` | Vision Pro 端 |
| LonelyPianistAVPTests | `LonelyPianistAVPTests/` | `LonelyPianistAVPTests.xctest` | AVP 单元测试 |
| RealityKitContent | `Packages/RealityKitContent/` | Swift Package library | AVP target |
| piano_dialogue_server | `piano_dialogue_server/` | 本地 Python 服务与脚本 | macOS Dialogue 流 |

## 第三方库 / 框架
| 依赖 | 类型 | 版本 | 用途 | 风险 / 注意事项 |
| --- | --- | --- | --- | --- |
| `torch` | runtime | `>=2.2` | 模型推理 | MPS/CUDA 兼容差异 |
| `transformers` | runtime | `>=4.41` | 加载 CausalLM | 大模型加载耗时高 |
| `anticipation` | runtime | GitHub 源安装 | 音符事件生成 | 依赖外网与上游稳定性 |
| `fastapi` / `uvicorn` | runtime | `>=0.110` / `>=0.27` | HTTP/WS 服务 | 本地端口占用导致启动失败 |
| `mido` | tool/runtime | `>=1.3.2` | MIDI 调试文件读写 | 依赖标准 MIDI 结构 |

## 外部服务与平台
| 服务 / 平台 | 调用方 | 协议 / 接口 | 用途 |
| --- | --- | --- | --- |
| 本地 Python 服务 | macOS App | `ws://127.0.0.1:8765/ws` | Dialogue 生成 |
| HuggingFace / 镜像 | Python 推理脚本 | HTTP 下载模型权重 | 模型文件获取 |
| Shortcuts URL Scheme | macOS Shortcut 服务 | `shortcuts://run-shortcut` | 扩展自动化动作 |
| macOS Accessibility | KeyboardEventService | 系统权限接口 | 发送全局按键事件 |

## 构建、测试与开发工具
| 工具 / 命令 | 位置 | 用途 | 备注 |
| --- | --- | --- | --- |
| `xcodebuild` | 仓库根目录 | macOS/visionOS build & test | AGENTS 明确要求 |
| `python -m uvicorn` | `piano_dialogue_server/` | 启动服务 | 默认 `127.0.0.1:8765` |
| `scripts/test_generate.py` | `piano_dialogue_server/scripts/` | 离线模型生成检查 | 不依赖服务进程 |

## 平台兼容性
- Xcode 工程 target 覆盖 macOS 与 visionOS（项目中可见 `LonelyPianist` / `LonelyPianistAVP`）。
- `Packages/RealityKitContent/Package.swift` 声明最低平台为 `v26`（visionOS/macOS/iOS/tvOS）。
- Python 环境 README 推荐 `python3.12` 虚拟环境。

## 版本与锁定策略
- Swift 侧无单独 lockfile，依赖由 Xcode 工程与系统框架约束。
- Python 依赖通过 `requirements.txt` 管理，多数为下限版本（`>=`），并非严格锁定。
- 模型版本优先级：`AMT_MODEL_DIR` > 本地 `models/music-large-800k` > `AMT_MODEL_ID` 默认值。

## 升级热点与风险
- 升级 `anticipation` / `transformers` 可能影响事件 token 语义与采样行为。
- Apple SDK 升级可能影响 HandTrackingProvider 可用性与权限行为。

## 示例片段
```txt
# piano_dialogue_server/requirements.txt（节选）
torch>=2.2
transformers>=4.41
anticipation @ git+https://github.com/jthickstun/anticipation.git
fastapi>=0.110
```

```swift
// Packages/RealityKitContent/Package.swift（节选）
platforms: [
    .visionOS(.v26),
    .macOS(.v26),
    .iOS(.v26),
    .tvOS(.v26)
]
```

## Coverage Gaps
- 未发现仓库内统一依赖锁定（如 Python lockfile），跨机器可重复性仍依赖本地环境管理。

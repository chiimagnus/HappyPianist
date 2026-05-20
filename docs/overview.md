# 概览

## 仓库目标

LonelyPianist 是一个本地优先的钢琴交互系统。当前仓库包含 macOS MIDI recorder、visionOS 练习端和本地 Python 后端；三者可以独立运行，也可以通过 BLE MIDI、MusicXML、Bonjour 和 `/generate` 协议联动。

## 运行面

| 运行面 | 入口 | 用户价值 | 深入文档 |
| --- | --- | --- | --- |
| macOS recorder | `LonelyPianist/` | MIDI 监听、take 录制、MIDI 导入、sampler/外部 MIDI 回放 | [modules/lonelypianist-macos.md](modules/lonelypianist-macos.md) |
| visionOS app | `LonelyPianistAVP/` | MusicXML 曲库、三种钢琴模式、空间练习、虚拟钢琴、BLE MIDI、AI 即兴 | [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md) |
| AVP Practice | `LonelyPianistAVP/ViewModels/PracticeSession/` + `Services/Practice/` | step 推进、五线谱、自动播放、输入匹配、贴皮高亮 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| Python backend | `piano_dialogue_server/` | `/generate`、`/ws`、`/upload-expand`、Bonjour、调试包 | [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md) |

## 本地验证命令

| 场景 | 命令 |
| --- | --- |
| macOS tests | `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` |
| 查看 AVP destinations | `xcodebuild -showdestinations -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP` |
| AVP tests | `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO` |
| Python server | `cd piano_dialogue_server && ./scripts/run_server.sh` |
| Python health check | `curl -s http://127.0.0.1:8765/health` |
| Python WS smoke | `cd piano_dialogue_server && python -m server.api.test_client` |

## 关键事实

- macOS app 当前不是映射器，也不包含 Piano Dialogue WebSocket client；它是 recorder/playback 面。
- visionOS app 的跨窗口流程由 `PracticeSetupState` 与 `WindowTransitionState` 维护，不存在 `FlowState` 或 `WindowCoordinator` 文件。
- `LonelyPianistAVP` 的 app 资源里声明了 Bravura 字体和 MusicXML UTI；`SalC5Light2.sf2` 需要本地补齐后才有完整音色回放。
- Python 的轻量生成策略是 `deterministic` 和 `rule`；`model` 策略会触发模型加载。

## Coverage Gaps

- 没有提交 `.github/workflows/`，自动化验证以本地命令为准。
- AVP 的手部追踪、平面检测、BLE MIDI、Bonjour/Local Network 与视觉舒适度需要 Apple Vision Pro 真机验证。
- Python 依赖无 lockfile，模型权重和下载镜像依赖本地环境。

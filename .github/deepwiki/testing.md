# 测试

## 测试策略
| 维度 | 方法 | 自动化程度 | 目标 |
| --- | --- | --- | --- |
| 业务逻辑 | Swift Testing 单元测试 | 高 | 稳定核心算法与状态迁移 |
| 服务契约 | 协议与模型约束测试（Swift/Python） | 中 | 避免跨进程字段漂移 |
| UI 流程 | 手工冒烟（README/AGENTS 指南） | 中 | 覆盖权限、设备、交互闭环 |
| 本地服务连通 | 健康检查与 test client | 中 | 验证 Dialogue 实际可用 |

## 测试层次
| 层次 | 位置 | 覆盖对象 | 备注 |
| --- | --- | --- | --- |
| macOS 单元测试 | `LonelyPianistTests/` | Mapping、Recording、Silence Detection、ViewModel Recorder 状态 | 使用 `import Testing` |
| AVP 单元测试 | `LonelyPianistAVPTests/` | MusicXMLParser、PracticeStepBuilder、StepMatcher、ChordAccumulator | 不使用 XCTest |
| Python 脚本验证 | `piano_dialogue_server/scripts/` / `server/test_client.py` | 模型生成、对话端到端回环 | 依赖本地模型与服务状态 |
| 手工验收 | 各 README / AGENTS | 权限、设备、沉浸式交互 | 覆盖真实硬件与系统权限 |

## 命令与执行顺序
| 命令 | 位置 | 用途 | 何时执行 |
| --- | --- | --- | --- |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS'` | 仓库根 | macOS 单元测试 | 改动 `LonelyPianist/` 后 |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` | 仓库根 | AVP 单元测试 | 改动 `LonelyPianistAVP/` 后 |
| `curl -s http://127.0.0.1:8765/health` | 任意 | Python 服务健康检查 | 启动服务后 |
| `../.venv/bin/python test_client.py`（在 `server/`） | `piano_dialogue_server/server/` | WS 对话链路检查 | 改动推理或协议后 |
| `python scripts/test_generate.py` | `piano_dialogue_server/` | 离线生成 sanity check | 模型或 sampling 逻辑变更后 |

## 高风险回归区
- `DialogueManager` 状态流转（idle/listening/thinking/playing）及回放打断策略。
- `DefaultMappingEngine` 的 velocity 阈值与 chord 严格匹配逻辑。
- `MusicXMLParser` 对 chord / backup / forward 时间线处理。
- `PressDetectionService` + `ChordAttemptAccumulator` 的联合判定窗口。

## 测试数据、fixture 与 mock
- macOS 测试使用 `TestDoubles/RecorderTestDoubles.swift` 提供 MIDI/Permission/Playback/Repository mock。
- `MappingConfigRepositoryTestDouble` 用于验证映射编辑持久化与重载行为。
- AVP 测试在代码内构造最小 MusicXML 字符串与 step 样本，避免外部 fixture 依赖。

## 人工冒烟流程
1. macOS 首次授权 Accessibility，确认 Runtime 状态与 Sources 刷新正常。
2. Start Listening 后分别验证 Single/Chord/Melody（含 velocity shift）映射行为。
3. Recorder 录音、停止、回放、切换输出，确认 take 持久化后重启仍在。
4. 启动 Python 服务，Dialogue 触发一次“弹奏->静默->AI 回放”闭环。
5. AVP 导入 MusicXML，完成 A0/C8 校准后验证高亮与 Skip/Mark Correct。

## CI / 质量门禁
- 当前仓库未发现 `.github/workflows/*`，未形成可见 CI 门禁定义。
- 质量门槛主要依赖本地 `xcodebuild test` + Python 脚本验证 + 手工冒烟。
- 若新增自动化流程，优先把现有命令固化到 workflow，避免文档与执行漂移。

## 常见失败点
- visionOS simulator 不可用或名称不匹配导致 AVP 测试命令失败。
- Python 虚拟环境未激活导致依赖缺失（尤其 `torch`）。
- 模型目录存在但无权重文件时推理引擎初始化失败。
- 权限未授予时看似“运行中”但映射动作不生效。

## 示例片段
```swift
@Test
func matcherAllowsTolerancePlusMinusOne() {
    let matcher = StepMatcher()
    #expect(matcher.matches(expectedNotes: [60, 64], pressedNotes: [59, 65], tolerance: 1) == true)
}
```

```swift
@Test
func mappingEngineChordUsesStrictEquality() {
    // 只有当前按下集合与规则集合完全相等时触发
}
```

## Coverage Gaps
- 尚未看到统一的跨进程自动化（macOS 发 WS、Python 回应、AVP 消费）全链路测试。

## 来源引用（Source References）
- `AGENTS.md`
- `LonelyPianistTests/SilenceDetectionServiceTests.swift`
- `LonelyPianistTests/Mapping/UnifiedMappingConfigTests.swift`
- `LonelyPianistTests/Recording/DefaultRecordingServiceTests.swift`
- `LonelyPianistTests/ViewModels/LonelyPianistViewModelRecorderStateTests.swift`
- `LonelyPianistTests/TestDoubles/RecorderTestDoubles.swift`
- `LonelyPianistAVPTests/StepMatcherTests.swift`
- `LonelyPianistAVPTests/ChordAttemptAccumulatorTests.swift`
- `LonelyPianistAVPTests/PracticeStepBuilderTests.swift`
- `LonelyPianistAVPTests/MusicXMLParserTests.swift`
- `piano_dialogue_server/server/test_client.py`
- `piano_dialogue_server/scripts/test_generate.py`
- `piano_dialogue_server/README.md`
